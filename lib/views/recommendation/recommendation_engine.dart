import 'dart:math';

import 'package:haka_comic/database/history_helper.dart';
import 'package:haka_comic/network/http.dart';
import 'package:haka_comic/network/models.dart';

/// Scores tags/categories/authors from reading history, fetches candidate
/// comics from the API, and returns a ranked list of unread comics.
class RecommendationEngine {
  static const _topTags = 5;
  static const _topCats = 3;
  static const _topAuthors = 2;
  static const _resultLimit = 60;

  Future<List<Doc>> compute() async {
    final history = await HistoryHelper().queryAllForScoring();
    if (history.isEmpty) return [];

    // cids already read – use uid which equals the stored cid
    final readCids = history.map((h) => h.uid).toSet();

    final now = DateTime.now();
    final tagScores = <String, double>{};
    final catScores = <String, double>{};
    final authorScores = <String, double>{};

    for (final h in history) {
      // Parse SQLite DATETIME string "YYYY-MM-DD HH:MM:SS"
      DateTime updatedAt;
      try {
        updatedAt = DateTime.parse(h.updatedAt.replaceAll(' ', 'T'));
      } catch (_) {
        updatedAt = now;
      }

      final days = now.difference(updatedAt).inDays.clamp(0, 365);
      final recency = exp(-days / 30.0);
      final completion = h.finished ? 1.5 : 1.0;
      final engagement = (h.pagesCount / 20.0).clamp(0.5, 3.0);
      final w = recency * completion * engagement;

      for (final tag in h.tags) {
        if (tag.isNotEmpty) tagScores[tag] = (tagScores[tag] ?? 0) + w;
      }
      for (final cat in h.categories) {
        if (cat.isNotEmpty) catScores[cat] = (catScores[cat] ?? 0) + w;
      }
      if (h.author.isNotEmpty) {
        authorScores[h.author] = (authorScores[h.author] ?? 0) + w;
      }
    }

    _normalize(tagScores);
    _normalize(catScores);
    _normalize(authorScores);

    final topTags = _topN(tagScores, _topTags);
    final topCats = _topN(catScores, _topCats);
    final topAuthors = _topN(authorScores, _topAuthors);

    // Fetch candidates concurrently; failures are silently ignored
    final futures = [
      for (final tag in topTags) _fetchDocs(t: tag),
      for (final cat in topCats) _fetchDocs(c: cat),
      for (final author in topAuthors) _fetchDocs(a: author),
    ];
    final batches = await Future.wait(futures, eagerError: false);

    // Deduplicate and remove already-read comics
    final seen = <String>{};
    final candidates = <Doc>[];
    for (final batch in batches) {
      for (final doc in batch) {
        final cid = doc.uid;
        if (readCids.contains(cid)) continue;
        if (!seen.add(cid)) continue;
        candidates.add(doc);
      }
    }

    // Score candidates by preference overlap
    final scored = candidates.map((doc) {
      double score = 0;
      for (final tag in doc.tags) {
        score += tagScores[tag] ?? 0;
      }
      for (final cat in doc.categories) {
        score += catScores[cat] ?? 0;
      }
      // Author is a stronger signal
      score += (authorScores[doc.author] ?? 0) * 2;
      return (doc: doc, score: score);
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return scored.take(_resultLimit).map((e) => e.doc).toList();
  }

  void _normalize(Map<String, double> map) {
    if (map.isEmpty) return;
    final maxVal = map.values.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return;
    for (final k in map.keys) {
      map[k] = map[k]! / maxVal;
    }
  }

  List<String> _topN(Map<String, double> map, int n) {
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(n).map((e) => e.key).toList();
  }

  Future<List<Doc>> _fetchDocs({String? t, String? c, String? a}) async {
    try {
      final r = await fetchComics(
        ComicsPayload(t: t, c: c, a: a, s: ComicSortType.dd, page: 1),
      );
      return r.comics.docs;
    } catch (_) {
      return [];
    }
  }
}
