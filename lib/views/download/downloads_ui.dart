import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:go_router/go_router.dart';
import 'package:haka_comic/database/read_record_helper.dart';
import 'package:haka_comic/rust/api/compress.dart';
import 'package:haka_comic/rust/api/simple.dart';
import 'package:haka_comic/utils/android_download_saver.dart';
import 'package:haka_comic/utils/common.dart';
import 'package:haka_comic/utils/extension.dart';
import 'package:haka_comic/utils/loader.dart';
import 'package:haka_comic/utils/log.dart';
import 'package:haka_comic/utils/save_to_folder_ios.dart';
import 'package:haka_comic/utils/ui.dart';
import 'package:haka_comic/views/download/background_downloader.dart';
import 'package:haka_comic/views/reader/state/comic_state.dart';
import 'package:haka_comic/widgets/empty.dart';
import 'package:haka_comic/widgets/slide_transition_x.dart';
import 'package:haka_comic/widgets/toast.dart';
import 'package:haka_comic/widgets/ui_image.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

enum ExportFileType { pdf, zip }

enum _DownloadExportPlatform { android, desktop, ios }

typedef _DownloadTaskAction = ({
  IconData icon,
  void Function(String taskId) action,
});

typedef _DownloadExportItem = ({String fileStem, String sourceFolderPath});

_DownloadTaskAction _resolveDownloadTaskAction(DownloadTaskStatus status) {
  return switch (status) {
    DownloadTaskStatus.paused => (
      icon: Icons.play_arrow,
      action: BackgroundDownloader.resumeTask,
    ),
    DownloadTaskStatus.downloading => (
      icon: Icons.pause,
      action: BackgroundDownloader.pauseTask,
    ),
    DownloadTaskStatus.error => (
      icon: Icons.refresh,
      action: BackgroundDownloader.resumeTask,
    ),
    _ => (icon: Icons.error, action: (_) {}),
  };
}

class Downloads extends StatefulWidget {
  const Downloads({super.key});

  @override
  State<Downloads> createState() => _DownloadsState();
}

class _DownloadsState extends State<Downloads> {
  List<ComicDownloadTask> tasks = [];
  late final StreamSubscription _subscription;
  late final StreamSubscription<int> _speedSubscription;
  bool _isSelecting = false;
  Set<String> _selectedTaskIds = {};
  int _downloadSpeed = 0;

  @override
  void initState() {
    super.initState();
    _subscription = BackgroundDownloader.streamController.stream.listen(
      (event) => setState(() {
        tasks = event;
      }),
    );
    _speedSubscription = BackgroundDownloader.speedStreamController.stream
        .listen((speed) => setState(() => _downloadSpeed = speed));
    BackgroundDownloader.getTasks();
  }

  @override
  void dispose() {
    _subscription.cancel();
    _speedSubscription.cancel();
    super.dispose();
  }

  List<ComicDownloadTask> get _selectedTasks {
    return tasks
        .where((task) => _selectedTaskIds.contains(task.comic.id))
        .toList();
  }

  void clearTasks() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('确认删除'),
          content: const Text('是否删除选中的下载任务？'),
          actions: [
            TextButton(
              onPressed: () => context.pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => context.pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      BackgroundDownloader.deleteTasks(_selectedTaskIds.toList());
      close();
    }
  }

  _DownloadExportPlatform get _exportPlatform {
    if (isAndroid) {
      return _DownloadExportPlatform.android;
    }

    if (isDesktop) {
      return _DownloadExportPlatform.desktop;
    }

    return _DownloadExportPlatform.ios;
  }

  bool get _canExportSelectedTasks {
    return _selectedTaskIds.isNotEmpty && isAllCompleted;
  }

  Future<List<_DownloadExportItem>> _getSelectedExportItems() async {
    final downloadPath = await getDownloadDirectory();
    return [
      for (final task in _selectedTasks)
        (
          fileStem: task.comic.title.legalized,
          sourceFolderPath: p.join(downloadPath, task.comic.title.legalized),
        ),
    ];
  }

  Future<Directory> _createCleanExportTempDirectory() async {
    final cacheDir = await getApplicationCacheDirectory();
    final tempDir = Directory(p.join(cacheDir.path, 'temp'));

    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }

    await tempDir.create(recursive: true);
    return tempDir;
  }

  Future<void> _buildExportFile({
    required String sourceFolderPath,
    required String outputPath,
    required ExportFileType type,
  }) async {
    switch (type) {
      case ExportFileType.pdf:
        await exportPdf(
          sourceFolderPath: sourceFolderPath,
          outputPdfPath: outputPath,
        );
      case ExportFileType.zip:
        await compress(
          sourceFolderPath: sourceFolderPath,
          outputZipPath: outputPath,
          compressionMethod: CompressionMethod.stored,
        );
    }
  }

  Future<String> _buildIosZipExportPath(
    List<_DownloadExportItem> exportItems,
  ) async {
    final tempDir = await _createCleanExportTempDirectory();

    final name = exportItems.length == 1
        ? '${exportItems.first.fileStem}.zip'
        : 'comics.zip';

    var zipPath = p.join(tempDir.path, name);

    final zipper = await createZipper(
      zipPath: zipPath,
      compressionMethod: CompressionMethod.stored,
    );

    for (final item in exportItems) {
      await zipper.addDirectory(dirPath: item.sourceFolderPath);
    }

    await zipper.close();
    return zipPath;
  }

  Future<String> _buildIosPdfExportPath(
    List<_DownloadExportItem> exportItems,
  ) async {
    final tempDir = await _createCleanExportTempDirectory();

    if (exportItems.length == 1) {
      final item = exportItems.first;
      final pdfPath = p.join(tempDir.path, '${item.fileStem}.pdf');
      await _buildExportFile(
        sourceFolderPath: item.sourceFolderPath,
        outputPath: pdfPath,
        type: ExportFileType.pdf,
      );
      return pdfPath;
    }

    final zipPath = p.join(tempDir.path, 'comics.zip');
    final zipper = await createZipper(
      zipPath: zipPath,
      compressionMethod: CompressionMethod.stored,
    );

    for (final item in exportItems) {
      final pdfPath = p.join(tempDir.path, '${item.fileStem}.pdf');
      await _buildExportFile(
        sourceFolderPath: item.sourceFolderPath,
        outputPath: pdfPath,
        type: ExportFileType.pdf,
      );
      await zipper.addFile(filePath: pdfPath);
    }

    await zipper.close();
    return zipPath;
  }

  Future<String> _buildIosExportPath({
    required ExportFileType type,
    required List<_DownloadExportItem> exportItems,
  }) {
    return switch (type) {
      ExportFileType.pdf => _buildIosPdfExportPath(exportItems),
      ExportFileType.zip => _buildIosZipExportPath(exportItems),
    };
  }

  Future<bool> _ensureAndroidExportPermission() async {
    final version = await AndroidDownloadSaver.getAndroidVersion();

    if (version > 28) {
      return true;
    }

    final status = await Permission.storage.request();
    if (status.isGranted) {
      return true;
    }

    if (status.isPermanentlyDenied) {
      if (!mounted) {
        return false;
      }

      await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('缺少权限'),
            content: const Text('请在设置中开启存储权限后重试'),
            actions: [
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  openAppSettings();
                  context.pop();
                },
                child: const Text('打开设置'),
              ),
            ],
          );
        },
      );
      return false;
    }

    Toast.show(message: "没有必要的存储权限");
    return false;
  }

  void _showExportLoader() {
    if (mounted) {
      Loader.show(context);
    }
  }

  Future<void> _runExportTask(Future<void> Function() action) async {
    try {
      await action();
    } catch (e, st) {
      Log.e("export comic failed", error: e, stackTrace: st);
      Toast.show(message: "导出失败");
    } finally {
      if (mounted) {
        Loader.hide(context);
      }
      close();
    }
  }

  Future<void> _exportTasksForDesktop({required ExportFileType type}) async {
    await _runExportTask(() async {
      final selectedDirectoryPath = await FilePicker.platform
          .getDirectoryPath();

      if (selectedDirectoryPath == null) {
        Toast.show(message: "未选择导出目录");
        return;
      }

      _showExportLoader();
      final exportItems = await _getSelectedExportItems();

      for (final item in exportItems) {
        final destPath = p.join(
          selectedDirectoryPath,
          '${item.fileStem}.${type.name}',
        );

        await _buildExportFile(
          sourceFolderPath: item.sourceFolderPath,
          outputPath: destPath,
          type: type,
        );
      }

      Toast.show(message: "导出成功");
    });
  }

  Future<void> _exportTasksForIos({required ExportFileType type}) async {
    await _runExportTask(() async {
      _showExportLoader();

      final exportItems = await _getSelectedExportItems();
      final path = await _buildIosExportPath(
        type: type,
        exportItems: exportItems,
      );

      final success = await SaveToFolderIos.copy(path);
      Toast.show(message: success ? "导出成功" : "导出失败");
    });
  }

  Future<void> _exportTasksForAndroid({required ExportFileType type}) async {
    await _runExportTask(() async {
      if (!await _ensureAndroidExportPermission()) {
        return;
      }

      _showExportLoader();

      final cacheDir = await getApplicationCacheDirectory();
      final exportItems = await _getSelectedExportItems();

      for (final item in exportItems) {
        final fileName = '${item.fileStem}.${type.name}';
        final destPath = p.join(cacheDir.path, fileName);

        await _buildExportFile(
          sourceFolderPath: item.sourceFolderPath,
          outputPath: destPath,
          type: type,
        );

        await AndroidDownloadSaver.saveToDownloads(
          filePath: destPath,
          fileName: fileName,
        );
      }

      Toast.show(message: "导出成功");
    });
  }

  Future<void> _exportSelectedTasks({required ExportFileType type}) {
    return switch (_exportPlatform) {
      _DownloadExportPlatform.android => _exportTasksForAndroid(type: type),
      _DownloadExportPlatform.desktop => _exportTasksForDesktop(type: type),
      _DownloadExportPlatform.ios => _exportTasksForIos(type: type),
    };
  }

  VoidCallback? exportFile({required ExportFileType type}) {
    if (!_canExportSelectedTasks) {
      return null;
    }

    return () => _exportSelectedTasks(type: type);
  }

  void close() {
    setState(() {
      _isSelecting = false;
      _selectedTaskIds.clear();
    });
  }

  bool get isAllCompleted => _selectedTasks.every(
    (task) => task.status == DownloadTaskStatus.completed,
  );

  final entries = <ContextMenuEntry>[
    MenuItem(
      label: Text(
        '复制标题',
        style: TextStyle(fontFamily: isLinux ? 'HarmonyOS Sans' : null),
      ),
      icon: const Icon(Icons.copy),
      value: 'copy',
    ),
    MenuItem(
      label: Text(
        '选中该项',
        style: TextStyle(fontFamily: isLinux ? 'HarmonyOS Sans' : null),
      ),
      icon: const Icon(Icons.check),
      value: 'select',
    ),
  ];

  late final menu = ContextMenu(
    entries: entries,
    padding: const EdgeInsets.all(8.0),
  );

  Future<void> _onContextMenuItemPress(
    String value,
    ComicDownloadTask task,
  ) async {
    switch (value) {
      case 'copy':
        final title = task.comic.title;
        await Clipboard.setData(ClipboardData(text: title));
        Toast.show(message: '已复制');
        break;
      case 'select':
        setState(() {
          _isSelecting = true;
          _selectedTaskIds.add(task.comic.id);
        });
        break;
    }
  }

  void _startReader(ComicDownloadTask task) async {
    if (task.status != DownloadTaskStatus.completed) {
      Toast.show(message: '任务未完成');
      return;
    }
    final chapters = task.chapters.map((e) => e.toChapter()).toList();

    chapters.sort((a, b) => a.order.compareTo(b.order));

    final helper = ReadRecordHelper();

    final record = await helper.query(task.comic.id);

    var pageNo = 0;
    var chapter = chapters.firstWhereOrNull((e) => e.id == record?.chapterId);

    if (chapter != null) {
      pageNo = record!.pageNo;
    }

    if (!mounted) return;
    context.push(
      '/reader',
      extra: ComicState(
        id: task.comic.id,
        title: task.comic.title,
        chapters: chapters,
        pageNo: pageNo,
        chapter: chapter ?? chapters.first,
        type: ReaderType.local,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = context.width;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isSelecting) {
          close();
        } else {
          context.pop();
        }
      },
      child: Scaffold(
        appBar: _isSelecting
            ? _SelectionAppBar(
                selectedCount: _selectedTaskIds.length,
                onClose: close,
                onDeselectAll: () => setState(() => _selectedTaskIds.clear()),
                onSelectAll: () => setState(
                  () => _selectedTaskIds = tasks.map((e) => e.comic.id).toSet(),
                ),
                onInvertSelection: () {
                  final allIds = tasks.map((e) => e.comic.id).toSet();
                  setState(() {
                    _selectedTaskIds = allIds.difference(_selectedTaskIds);
                  });
                },
              )
            : _NormalAppBar(
                onEnterSelection: () => setState(() => _isSelecting = true),
                downloadSpeed: _downloadSpeed,
              ),
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              if (tasks.isEmpty) const SliverToBoxAdapter(child: Empty()),
              SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: UiMode.m1(context)
                      ? width
                      : UiMode.m2(context)
                      ? width / 2
                      : width / 3,
                  mainAxisSpacing: 5,
                  crossAxisSpacing: 5,
                  childAspectRatio: 2.5,
                ),
                itemBuilder: (context, index) {
                  final task = tasks[index];
                  final isSelected = _selectedTaskIds.contains(task.comic.id);
                  return _DownloadTaskItem(
                    task: task,
                    isSelecting: _isSelecting,
                    isSelected: isSelected,
                    contextMenu: menu,
                    onTap: () {
                      if (_isSelecting) {
                        setState(() {
                          if (isSelected) {
                            _selectedTaskIds.remove(task.comic.id);
                          } else {
                            _selectedTaskIds.add(task.comic.id);
                          }
                        });
                      } else {
                        _startReader(task);
                      }
                    },
                    onItemSelected: _onContextMenuItemPress,
                    downloadSpeed: _downloadSpeed,
                  );
                },
                itemCount: tasks.length,
              ),
            ],
          ),
        ),
        persistentFooterButtons: _isSelecting
            ? [
                FilledButton.tonalIcon(
                  onPressed: exportFile(type: ExportFileType.pdf),
                  label: const Text('PDF'),
                  icon: const Icon(Icons.picture_as_pdf),
                ),
                FilledButton.tonalIcon(
                  onPressed: exportFile(type: ExportFileType.zip),
                  label: const Text('ZIP'),
                  icon: const Icon(Icons.folder_zip),
                ),
                FilledButton.tonalIcon(
                  onPressed: _selectedTaskIds.isEmpty ? null : clearTasks,
                  label: const Text('删除'),
                  icon: const Icon(Icons.delete_forever),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.colorScheme.error,
                    foregroundColor: context.colorScheme.onError,
                  ),
                ),
              ]
            : null,
      ),
    );
  }
}

class _SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int selectedCount;
  final VoidCallback onClose;
  final VoidCallback onDeselectAll;
  final VoidCallback onSelectAll;
  final VoidCallback onInvertSelection;

  const _SelectionAppBar({
    required this.selectedCount,
    required this.onClose,
    required this.onDeselectAll,
    required this.onSelectAll,
    required this.onInvertSelection,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        transitionBuilder: (child, animation) {
          return SlideTransitionX(
            position: animation,
            direction: AxisDirection.down,
            child: child,
          );
        },
        child: Text('$selectedCount', key: ValueKey(selectedCount)),
      ),
      leading: IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
      actions: [
        IconButton(onPressed: onDeselectAll, icon: const Icon(Icons.deselect)),
        IconButton(onPressed: onSelectAll, icon: const Icon(Icons.select_all)),
        IconButton(
          onPressed: onInvertSelection,
          icon: const Icon(Icons.repeat),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _NormalAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onEnterSelection;
  final int downloadSpeed;
  const _NormalAppBar({
    required this.onEnterSelection,
    required this.downloadSpeed,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('我的下载'),
      actions: [
        IconButton(
          onPressed: onEnterSelection,
          icon: const Icon(Icons.checklist_rtl),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

String _formatSpeed(int bytesPerSecond) {
  if (bytesPerSecond >= 1024 * 1024) {
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)}MB/s';
  } else if (bytesPerSecond >= 1024) {
    return '${(bytesPerSecond / 1024).toStringAsFixed(0)}KB/s';
  }
  return '${bytesPerSecond}B/s';
}

class _DownloadTaskItem extends StatelessWidget {
  final ComicDownloadTask task;
  final bool isSelecting;
  final bool isSelected;
  final VoidCallback onTap;
  final Future<void> Function(String, ComicDownloadTask) onItemSelected;
  final ContextMenu contextMenu;
  final int downloadSpeed;

  const _DownloadTaskItem({
    required this.task,
    required this.isSelecting,
    required this.isSelected,
    required this.onTap,
    required this.onItemSelected,
    required this.contextMenu,
    required this.downloadSpeed,
  });

  @override
  Widget build(BuildContext context) {
    return ContextMenuRegion(
      key: ValueKey(task.comic.id),
      contextMenu: contextMenu,
      enableDefaultGestures: !isSelecting,
      onItemSelected: (value) => onItemSelected(value!, task),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: isSelected
              ? BoxDecoration(
                  color: context.colorScheme.secondaryContainer.withValues(
                    alpha: 0.65,
                  ),
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: Row(
            children: [
              AspectRatio(
                aspectRatio: 90 / 130,
                child: UiImage(
                  url: task.comic.cover,
                  cacheWidth: 180,
                  shape: .rectangle,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.comic.title,
                      style: context.textTheme.titleSmall,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    if (task.status.isOperable)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Builder(
                            builder: (_) {
                              final action = _resolveDownloadTaskAction(
                                task.status,
                              );
                              return IconButton(
                                onPressed: () {
                                  action.action(task.comic.id);
                                },
                                icon: Icon(action.icon),
                              );
                            },
                          ),
                        ],
                      ),
                    Row(
                      spacing: 8,
                      children: [
                        Text(
                          task.status.displayName,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${task.completed} / ${task.total}',
                          style: context.textTheme.bodySmall,
                        ),
                        if (downloadSpeed > 0 &&
                            task.status == DownloadTaskStatus.downloading)
                          Text(
                            _formatSpeed(downloadSpeed),
                            style: context.textTheme.bodySmall,
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    LinearProgressIndicator(
                      borderRadius: BorderRadius.circular(99),
                      value: task.total == 0
                          ? null
                          : task.completed / task.total,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
