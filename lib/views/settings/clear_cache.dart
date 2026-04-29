import 'dart:io';
import 'dart:math';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:haka_comic/views/settings/widgets/menu_list_tile.dart';
import 'package:haka_comic/widgets/toast.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

const _cachedNetworkImageCeCacheFolderName = 'cached_network_image_ce';

class ClearCache extends StatefulWidget {
  const ClearCache({super.key});

  @override
  State<ClearCache> createState() => _ClearCacheState();
}

class _ClearCacheState extends State<ClearCache> {
  int _cacheSize = 0;
  bool _isClearing = false;
  bool _isCalculating = false;

  // 获取缓存目录
  Future<List<String>> _getCacheDirs() async {
    final tempDir = await getTemporaryDirectory();
    final cachedNetworkImageCeCachePath = p.join(
      tempDir.path,
      _cachedNetworkImageCeCacheFolderName,
    );
    final cacheDir = await getApplicationCacheDirectory();
    return _normalizeCacheDirs([cachedNetworkImageCeCachePath, cacheDir.path]);
  }

  static List<String> _normalizeCacheDirs(List<String> dirPaths) {
    final normalizedDirs = <String>[];
    for (final dirPath in dirPaths) {
      final normalizedPath = p.normalize(dirPath);
      final isCovered = normalizedDirs.any(
        (existingPath) =>
            p.equals(existingPath, normalizedPath) ||
            p.isWithin(existingPath, normalizedPath),
      );
      if (isCovered) continue;

      normalizedDirs.removeWhere(
        (existingPath) => p.isWithin(normalizedPath, existingPath),
      );
      normalizedDirs.add(normalizedPath);
    }
    return normalizedDirs;
  }

  // 计算缓存大小
  static int _calculateCacheSizeIsolate(List<String> dirPaths) {
    int totalSize = 0;
    for (var dirPath in dirPaths) {
      final dir = Directory(dirPath);
      if (dir.existsSync()) {
        final files = dir.listSync(recursive: true);
        for (var file in files) {
          if (file is File) {
            totalSize += file.lengthSync();
          }
        }
      }
    }
    return totalSize;
  }

  static void _clearCache(List<String> dirPaths) {
    for (var dirPath in dirPaths) {
      final cacheDir = Directory(dirPath);
      if (cacheDir.existsSync()) {
        cacheDir.deleteSync(recursive: true);
      }
    }
  }

  // 格式化文件大小
  String formatSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    int i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  // 清理缓存
  Future<void> _handleClearCache() async {
    setState(() => _isClearing = true);
    try {
      final paths = await _getCacheDirs();
      await CachedNetworkImageProvider.defaultCacheManager.emptyCache();
      await compute(_clearCache, paths);
      _loadCacheSize(); // 重新加载大小
      Toast.show(message: '缓存已清理');
    } catch (e) {
      Toast.show(message: '清理缓存失败');
    } finally {
      setState(() => _isClearing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  void _loadCacheSize() async {
    setState(() => _isCalculating = true);
    final paths = await _getCacheDirs();
    final size = await compute(_calculateCacheSizeIsolate, paths);
    if (!mounted) return;
    setState(() {
      _cacheSize = size;
      _isCalculating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MenuListTile.withAction(
      icon: Icons.delete_sweep_outlined,
      title: '清理缓存',
      value: _isClearing
          ? "清理中..."
          : _isCalculating
          ? '计算中...'
          : formatSize(_cacheSize),
      onTap: () async {
        final bool? result = await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('清理缓存'),
              content: const Text('确定要清理缓存吗？'),
              actions: <Widget>[
                TextButton(
                  child: const Text('取消'),
                  onPressed: () => context.pop(false),
                ),
                TextButton(
                  child: const Text('确定'),
                  onPressed: () => context.pop(true),
                ),
              ],
            );
          },
        );
        if (result == true) {
          _handleClearCache();
        }
      },
    );
  }
}
