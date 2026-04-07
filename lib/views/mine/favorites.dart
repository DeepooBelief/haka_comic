import 'package:flutter/material.dart';
import 'package:haka_comic/mixin/pagination.dart';
import 'package:haka_comic/network/http.dart';
import 'package:haka_comic/network/models.dart';
import 'package:haka_comic/router/aware_page_wrapper.dart';
import 'package:haka_comic/utils/extension.dart';
import 'package:haka_comic/utils/log.dart';
import 'package:haka_comic/utils/request/request.dart';
import 'package:haka_comic/views/comics/common_pagination_footer.dart';
import 'package:haka_comic/views/comics/common_tmi_list.dart';
import 'package:haka_comic/views/comics/page_selector.dart';
import 'package:haka_comic/views/download/background_downloader.dart';
import 'package:haka_comic/widgets/error_page.dart';
import 'package:haka_comic/widgets/toast.dart';

class Favorites extends StatefulWidget {
  const Favorites({super.key});

  @override
  State<Favorites> createState() => _FavoritesState();
}

class _FavoritesState extends State<Favorites>
    with RequestMixin, PaginationMixin {
  int _page = 1;
  ComicSortType _sortType = ComicSortType.dd;

  bool _isSelecting = false;
  Set<String> _selectedCids = {};
  bool _isDownloading = false;

  late final _handler = fetchFavoriteComics.useRequest(
    defaultParams: UserFavoritePayload(page: _page, sort: _sortType),
    onSuccess: (data, _) {
      Log.i('Fetch favorite comics success', data.toString());
    },
    onError: (e, _) {
      Log.e('Fetch favorite comics error', error: e);
    },
    reducer: pagination
        ? null
        : (prev, current) {
            if (prev == null) return current;
            return current.copyWith.comics(
              docs: [...prev.comics.docs, ...current.comics.docs],
            );
          },
  );

  @override
  List<RequestHandler> registerHandler() => [_handler];

  @override
  Future<void> loadMore() async {
    final pages = _handler.state.data?.comics.pages ?? 1;
    if (_page >= pages) return;
    await _onPageChange(_page + 1);
  }

  Future<void> _onPageChange(int page) async {
    setState(() {
      _page = page;
      _isSelecting = false;
      _selectedCids = {};
    });
    await _handler.run(UserFavoritePayload(page: page, sort: _sortType));
  }

  void _onSortChange(ComicSortType sortType) {
    if (sortType == _sortType) return;
    setState(() {
      _page = 1;
      _sortType = sortType;
      _isSelecting = false;
      _selectedCids = {};
    });
    _handler.mutate(ComicsResponse.empty);
    _handler.run(UserFavoritePayload(page: 1, sort: sortType));
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelecting = false;
      _selectedCids = {};
    });
  }

  void _selectAll(List<ComicBase> comics) {
    setState(() {
      _selectedCids = comics.map((c) => c.uid).toSet();
    });
  }

  void _invertSelection(List<ComicBase> comics) {
    setState(() {
      final allCids = comics.map((c) => c.uid).toSet();
      _selectedCids = allCids.difference(_selectedCids);
    });
  }

  Future<void> _batchDownload(List<ComicBase> allComics) async {
    if (_selectedCids.isEmpty) return;

    setState(() => _isDownloading = true);

    final selectedComics =
        allComics.where((c) => _selectedCids.contains(c.uid)).toList();

    int successCount = 0;
    int failCount = 0;

    try {
      final futures = selectedComics.map((comic) async {
        try {
          final chapters = await fetchChapters(comic.uid);
          if (chapters.isEmpty) return false;

          final downloadChapters = chapters
              .map(
                (chapter) => DownloadChapter(
                  id: chapter.uid,
                  title: chapter.title,
                  order: chapter.order,
                ),
              )
              .toList();

          BackgroundDownloader.addTask(
            ComicDownloadTask(
              comic: DownloadComic(
                id: comic.uid,
                title: comic.title,
                cover: comic.thumb.url,
              ),
              chapters: downloadChapters,
            ),
          );
          return true;
        } catch (e) {
          Log.e('Batch download comic failed: ${comic.title}', error: e);
          return false;
        }
      }).toList();

      final results = await Future.wait(futures);
      successCount = results.where((r) => r).length;
      failCount = results.where((r) => !r).length;
    } catch (e) {
      Log.e('Batch download error', error: e);
    }

    if (mounted) {
      if (failCount == 0) {
        Toast.show(message: '已添加 $successCount 个下载任务');
      } else {
        Toast.show(message: '成功 $successCount 个，失败 $failCount 个');
      }
      setState(() {
        _isSelecting = false;
        _selectedCids = {};
        _isDownloading = false;
      });
    }
  }

  List<Widget> _buildAppBarActions(List<ComicBase> comics) {
    if (_isSelecting) {
      return [
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: '退出选择',
          onPressed: _exitSelectionMode,
        ),
        IconButton(
          icon: const Icon(Icons.select_all),
          tooltip: '全选',
          onPressed: () => _selectAll(comics),
        ),
        IconButton(
          icon: const Icon(Icons.repeat),
          tooltip: '反选',
          onPressed: () => _invertSelection(comics),
        ),
      ];
    }

    return [
      MenuAnchor(
        menuChildren: <Widget>[
          ...[
            {'label': '新到旧', 'type': ComicSortType.dd},
            {'label': '旧到新', 'type': ComicSortType.da},
          ].map(
            (e) => MenuItemButton(
              onPressed: _isDownloading
                  ? null
                  : () {
                      _onSortChange(e['type'] as ComicSortType);
                    },
              child: Row(
                spacing: 5,
                children: [
                  Text(e['label'] as String),
                  if (_sortType == e['type'])
                    Icon(
                      Icons.done,
                      size: 16,
                      color: context.colorScheme.primary,
                    ),
                ],
              ),
            ),
          ),
        ],
        builder: (_, MenuController controller, Widget? child) {
          return IconButton(
            onPressed: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            icon: const Icon(Icons.sort),
            tooltip: '排序',
          );
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return RouteAwarePageWrapper(
      builder: (context, completed) {
        final data = _handler.state.data;
        final comics = data?.comics.docs ?? [];

        return Scaffold(
          appBar: AppBar(
            title: _isSelecting
                ? Text('已选 ${_selectedCids.length} 项')
                : const Text('收藏漫画'),
            actions: _buildAppBarActions(comics),
          ),
          body: Stack(
            children: [
              switch (_handler.state) {
                RequestState(:final data) when data != null => CommonTMIList(
                  comics: data.comics.docs,
                  selectedCids: _isSelecting ? _selectedCids : null,
                  onItemLongPress: (comic) {
                    if (!_isSelecting) {
                      setState(() {
                        _isSelecting = true;
                        _selectedCids = {comic.uid};
                      });
                    }
                  },
                  onItemSelected: _isSelecting
                      ? (key, comic) {
                          setState(() {
                            if (_selectedCids.contains(comic.uid)) {
                              _selectedCids.remove(comic.uid);
                            } else {
                              _selectedCids.add(comic.uid);
                            }
                          });
                        }
                      : null,
                  enableDefaultGestures: !_isSelecting,
                  pageSelectorBuilder: pagination
                      ? (context) {
                          return PageSelector(
                            currentPage: _page,
                            pages: data.comics.pages,
                            onPageChange: _isDownloading
                                ? (_) async {}
                                : _onPageChange,
                          );
                        }
                      : null,
                  controller: pagination ? null : scrollController,
                  footerBuilder: pagination
                      ? null
                      : (context) {
                          final loading = _handler.state.loading;
                          return CommonPaginationFooter(loading: loading);
                        },
                ),
                Error(:final error) => ErrorPage(
                  errorMessage: error.toString(),
                  onRetry: _handler.refresh,
                ),
                _ => const Center(child: CircularProgressIndicator()),
              },
              if (_isSelecting && _selectedCids.isNotEmpty)
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: FilledButton(
                    onPressed: _isDownloading ? null : () => _batchDownload(comics),
                    child: _isDownloading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('批量下载(${_selectedCids.length})'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
