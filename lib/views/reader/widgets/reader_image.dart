import 'dart:io';
import 'dart:async';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:haka_comic/database/images_helper.dart';
import 'package:haka_comic/utils/extension.dart';
import 'package:haka_comic/views/reader/utils/utils.dart';

class ReaderImage extends StatefulWidget {
  const ReaderImage({
    super.key,
    required this.url,
    this.imageSize,
    this.enableCache = true,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.medium,
    this.cacheWidth,
    this.timeRetry = const Duration(milliseconds: 300),
    required this.onImageSizeChanged,
  });

  // 图片url 或 本地文件路径
  final String url;

  // 缓存的图片尺寸
  final ImageSize? imageSize;
  final BoxFit fit;

  // 是否使用缓存的尺寸
  final bool enableCache;
  final FilterQuality filterQuality;
  final int? cacheWidth;
  final Duration timeRetry;

  // 尺寸回调
  final void Function(int width, int height) onImageSizeChanged;

  @override
  State<ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<ReaderImage> {
  static const double _fallbackAspectRatio = 3 / 4;
  static const int _maxAutoRetryCount = 2;

  bool _isReported = false;
  int _reloadToken = 0;
  int _autoRetryCount = 0;
  Timer? _retryTimer;
  ImageProvider? _listeningProvider;
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;

  bool get isNetwork {
    final scheme = Uri.tryParse(widget.url)?.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  @override
  void didUpdateWidget(covariant ReaderImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _resetImageReport();
      _reloadToken = 0;
      _autoRetryCount = 0;
      _retryTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _removeImageSizeListener();
    super.dispose();
  }

  Widget _buildPlaceholder(Widget child, [Key? key]) {
    if (!widget.enableCache) {
      return Center(key: key, child: child);
    }
    return AspectRatio(
      key: key,
      aspectRatio: _placeholderAspectRatio,
      child: Center(child: child),
    );
  }

  double get _placeholderAspectRatio {
    final size = widget.imageSize;
    if (size == null || size.width <= 0 || size.height <= 0) {
      return _fallbackAspectRatio;
    }
    return size.width / size.height;
  }

  Widget _buildErrorPlaceholder(VoidCallback onReload) {
    return _buildPlaceholder(
      IconButton(onPressed: onReload, icon: const Icon(Icons.refresh)),
    );
  }

  Widget _buildProgressPlaceholder(DownloadProgress progress) {
    final value = progress.progress ?? computeProgress(progress.downloaded);
    return _buildProgressIndicator(value);
  }

  Widget _buildRetryProgressPlaceholder() {
    return _buildProgressIndicator(null);
  }

  Widget _buildProgressIndicator(double? value) {
    return _buildPlaceholder(
      CircularProgressIndicator(
        value: value ?? 0.0,
        strokeWidth: 3,
        constraints: BoxConstraints.tight(const Size(28, 28)),
        backgroundColor: Colors.grey.shade300,
        color: context.colorScheme.primary,
        strokeCap: StrokeCap.round,
      ),
    );
  }

  bool get _hasAutoRetryRemaining => _autoRetryCount < _maxAutoRetryCount;

  Widget _buildRetryAwareErrorPlaceholder(VoidCallback onReload) {
    _scheduleAutoRetry();
    if (_hasAutoRetryRemaining || _retryTimer?.isActive == true) {
      return _buildRetryProgressPlaceholder();
    }
    return _buildErrorPlaceholder(onReload);
  }

  void _listenForImageSize(ImageProvider provider) {
    if (_isReported || _listeningProvider == provider) {
      return;
    }

    _removeImageSizeListener();

    final stream = provider.resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!mounted || _isReported) {
          return;
        }
        _isReported = true;
        widget.onImageSizeChanged(info.image.width, info.image.height);
        _removeImageSizeListener();
      },
      onError: (_, _) {
        _scheduleAutoRetry();
        _removeImageSizeListener();
      },
    );

    _listeningProvider = provider;
    _imageStream = stream;
    _imageStreamListener = listener;
    stream.addListener(listener);
  }

  void _removeImageSizeListener() {
    final stream = _imageStream;
    final listener = _imageStreamListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _listeningProvider = null;
    _imageStream = null;
    _imageStreamListener = null;
  }

  void _resetImageReport() {
    _removeImageSizeListener();
    _isReported = false;
  }

  void _scheduleAutoRetry() {
    if (_autoRetryCount >= _maxAutoRetryCount ||
        _retryTimer?.isActive == true) {
      return;
    }

    _autoRetryCount++;
    _retryTimer = Timer(widget.timeRetry, () {
      if (!mounted) return;
      _resetImageReport();
      setState(() => _reloadToken++);
    });
  }

  Future<void> _reloadNetworkImage() async {
    _retryTimer?.cancel();
    _autoRetryCount = 0;
    _resetImageReport();
    await CachedNetworkImage.evictFromCache(widget.url);
    if (mounted) {
      setState(() => _reloadToken++);
    }
  }

  Future<void> _reloadLocalImage() async {
    _retryTimer?.cancel();
    _autoRetryCount = 0;
    _resetImageReport();
    await FileImage(File(widget.url)).evict();
    if (mounted) {
      setState(() => _reloadToken++);
    }
  }

  Widget _buildNetworkImage() {
    return CachedNetworkImage(
      key: ValueKey('${widget.url}#$_reloadToken'),
      imageUrl: widget.url,
      fit: widget.fit,
      filterQuality: widget.filterQuality,
      memCacheWidth: widget.cacheWidth,
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: Duration.zero,
      disablePlaceholderOnCacheHit: false,
      progressIndicatorBuilder: (context, url, progress) {
        return _buildProgressPlaceholder(progress);
      },
      imageBuilder: (context, imageProvider) {
        _listenForImageSize(imageProvider);
        return Image(
          key: ValueKey(imageProvider),
          image: imageProvider,
          fit: widget.fit,
          filterQuality: widget.filterQuality,
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return _buildRetryAwareErrorPlaceholder(_reloadNetworkImage);
      },
    );
  }

  Widget _buildLocalImage() {
    final provider = ResizeImage.resizeIfNeeded(
      widget.cacheWidth,
      null,
      FileImage(File(widget.url)),
    );
    _listenForImageSize(provider);

    return Image(
      key: ValueKey('${widget.url}#$_reloadToken'),
      image: provider,
      fit: widget.fit,
      filterQuality: widget.filterQuality,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return _buildPlaceholder(const SizedBox.expand());
      },
      errorBuilder: (context, error, stackTrace) {
        return _buildRetryAwareErrorPlaceholder(_reloadLocalImage);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return isNetwork ? _buildNetworkImage() : _buildLocalImage();
  }
}
