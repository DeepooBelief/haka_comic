import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:haka_comic/database/history_helper.dart';
import 'package:haka_comic/utils/extension.dart';

class TagStatistics extends StatefulWidget {
  const TagStatistics({super.key});

  @override
  State<TagStatistics> createState() => _TagStatisticsState();
}

class _TagStatisticsState extends State<TagStatistics> {
  late Future<List<MapEntry<String, int>>> _future;
  final _searchController = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _future = _loadTags();
    _searchController.addListener(() {
      setState(() => _filter = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<MapEntry<String, int>>> _loadTags() async {
    final counts = await HistoryHelper().queryAllTags();
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('标签统计')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索标签…',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: _filter.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<MapEntry<String, int>>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('加载失败: ${snapshot.error}'));
                }
                final all = snapshot.data!;
                if (all.isEmpty) {
                  return const Center(child: Text('暂无数据，先去读几本吧 :)'));
                }
                final entries = _filter.isEmpty
                    ? all
                    : all
                        .where(
                          (e) => e.key.toLowerCase().contains(_filter),
                        )
                        .toList();
                if (entries.isEmpty) {
                  return const Center(child: Text('没有匹配的标签'));
                }
                final maxCount = all.first.value;
                return ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final tag = entries[index].key;
                    final count = entries[index].value;
                    return ListTile(
                      onTap: () => context.push('/comics?t=$tag'),
                      title: Text(tag),
                      subtitle: LinearProgressIndicator(
                        value: count / maxCount,
                        borderRadius: BorderRadius.circular(4),
                        backgroundColor: context.colorScheme.surfaceContainerHighest,
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: context.colorScheme.primaryContainer,
                        ),
                        child: Text(
                          '$count',
                          style: context.textTheme.labelMedium?.copyWith(
                            color: context.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
