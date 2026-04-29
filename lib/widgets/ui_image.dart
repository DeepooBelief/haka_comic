import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:haka_comic/router/route_observer.dart';
import 'package:haka_comic/utils/extension.dart';
import 'package:pool/pool.dart';

class _UiImage extends StatefulWidget {
  const _UiImage({
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.cacheWidth = 300,
    this.cacheHeight,
    this.shape,
    this.border,
    this.borderRadius,
    this.clipBehavior = Clip.antiAlias,
    this.filterQuality = FilterQuality.low,
    this.onFinally,
  });

  final String url;

  final BoxFit fit;

  final double? width;

  final double? height;

  final int cacheWidth;

  final int? cacheHeight;

  final BoxShape? shape;

  final BoxBorder? border;

  final BorderRadius? borderRadius;

  final Clip clipBehavior;

  final FilterQuality filterQuality;

  final VoidCallback? onFinally;

  @override
  State<_UiImage> createState() => _UiImageState();
}

class _UiImageState extends State<_UiImage> {
  int _reloadToken = 0;

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final memCacheWidth =
        ((widget.width ?? widget.cacheWidth) * devicePixelRatio).round();

    return CachedNetworkImage(
      key: ValueKey('${widget.url}#$_reloadToken'),
      imageUrl: widget.url,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      memCacheWidth: memCacheWidth,
      memCacheHeight: widget.cacheHeight,
      filterQuality: widget.filterQuality,
      fadeInDuration: const Duration(milliseconds: 250),
      fadeInCurve: Curves.easeOutQuad,
      disablePlaceholderOnCacheHit: true,
      placeholder: (context, url) => _frame(context),
      imageBuilder: (context, imageProvider) {
        widget.onFinally?.call();
        return _frame(
          context,
          child: Image(
            key: ValueKey(imageProvider),
            image: imageProvider,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            filterQuality: widget.filterQuality,
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        widget.onFinally?.call();
        return _frame(
          context,
          child: Center(
            child: IconButton(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ),
        );
      },
    );
  }

  Future<void> _reload() async {
    await CachedNetworkImage.evictFromCache(widget.url);
    if (mounted) {
      setState(() => _reloadToken++);
    }
  }

  Widget _frame(BuildContext context, {Widget? child}) {
    final shape = widget.shape ?? BoxShape.rectangle;
    return Container(
      width: widget.width,
      height: widget.height,
      clipBehavior: widget.clipBehavior,
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHigh,
        shape: shape,
        border: widget.border,
        borderRadius: shape == BoxShape.circle ? null : widget.borderRadius,
      ),
      child: child,
    );
  }
}

// 同时加载的图片数量
final _imageLoadPool = Pool(6);

class UiImage extends StatefulWidget {
  const UiImage({
    super.key,
    this.placeholder,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.cacheWidth = 300,
    this.cacheHeight,
    this.shape,
    this.border,
    this.borderRadius,
    this.clipBehavior = Clip.antiAlias,
    this.filterQuality = FilterQuality.low,
  });

  final String url;

  final BoxFit fit;

  final double? width;

  final double? height;

  final int cacheWidth;

  final int? cacheHeight;

  final BoxShape? shape;

  final BoxBorder? border;

  final BorderRadius? borderRadius;

  final Clip clipBehavior;

  final FilterQuality filterQuality;

  final Widget? placeholder;

  @override
  State<UiImage> createState() => _UiImageOuterState();
}

class _UiImageOuterState extends State<UiImage> with RouteAware {
  PoolResource? _resource;
  bool _ready = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _acquire();
  }

  // 订阅路由监听
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _isDisposed = true;
    _releaseCurrentResource();
    super.dispose();
  }

  @override
  void didPushNext() {
    _releaseCurrentResource();
  }

  @override
  void didPopNext() {
    if (_resource == null) {
      _acquire();
    }
  }

  Future<void> _acquire() async {
    if (_resource != null) return;

    final resource = await _imageLoadPool.request();

    if (!mounted || _isDisposed) {
      resource.release();
      return;
    }

    // 双重保险：检查当前页面是否可见
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      resource.release();
      return;
    }

    _resource = resource;
    if (mounted) {
      setState(() => _ready = true);
    }
  }

  void _releaseCurrentResource() {
    final target = _resource;
    _resource = null;
    target?.release();
  }

  void _onImageLoadFinally() {
    if (_isDisposed) return;
    _releaseCurrentResource();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return widget.placeholder ??
          Container(
            clipBehavior: widget.clipBehavior,
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: context.colorScheme.surfaceContainerHigh,
              borderRadius: widget.shape == BoxShape.circle
                  ? null
                  : widget.borderRadius,
              shape: widget.shape ?? BoxShape.rectangle,
              border: widget.border,
            ),
          );
    }
    return _UiImage(
      url: widget.url,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      cacheWidth: widget.cacheWidth,
      cacheHeight: widget.cacheHeight,
      shape: widget.shape,
      border: widget.border,
      borderRadius: widget.borderRadius,
      clipBehavior: widget.clipBehavior,
      filterQuality: widget.filterQuality,
      onFinally: _onImageLoadFinally,
    );
  }
}
