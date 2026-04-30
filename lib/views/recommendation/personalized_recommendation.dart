import 'package:flutter/material.dart';
import 'package:haka_comic/network/models.dart';
import 'package:haka_comic/utils/extension.dart';
import 'package:haka_comic/views/comics/list_item.dart';
import 'package:haka_comic/views/recommendation/recommendation_engine.dart';

class PersonalizedRecommendation extends StatefulWidget {
  const PersonalizedRecommendation({super.key});

  @override
  State<PersonalizedRecommendation> createState() =>
      _PersonalizedRecommendationState();
}

class _PersonalizedRecommendationState
    extends State<PersonalizedRecommendation> {
  late Future<List<Doc>> _future;

  @override
  void initState() {
    super.initState();
    _future = RecommendationEngine().compute();
  }

  void _refresh() {
    setState(() {
      _future = RecommendationEngine().compute();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Doc>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('加载失败: ${snapshot.error}'),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          );
        }

        final docs = snapshot.data ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 64,
                  color: context.colorScheme.outline,
                ),
                const SizedBox(height: 12),
                const Text('暂无推荐，多读几本后再来看看'),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新'),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView.builder(
            padding: EdgeInsets.only(
              top: context.top,
              bottom: context.bottom,
            ),
            itemCount: docs.length,
            itemBuilder: (context, index) => ListItem(doc: docs[index]),
          ),
        );
      },
    );
  }
}
