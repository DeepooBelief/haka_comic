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

  /// Fix 2 — Confidence floor: the denominator used when normalizing score maps
  /// is max(actual_max, threshold). This prevents a single weak read from being
  /// inflated to a perfect 1.0 score. Value ≈ weight of one recently-finished,
  /// moderately-sized book (recency=1 × completion=1.5 × engagement=1.5).
  static const _minConfidenceThreshold = 2.0;

  /// Fix 3 — Serendipity: fraction of the final list filled with exploration
  /// picks from categories adjacent to the user's top preferences.
  static const _serendipityRatio = 0.15;

  /// Number of adjacent (less-dominant) categories used as serendipity source.
  static const _serendipityCats = 2;

  final _rng = Random();

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

    // Fix 2: normalize with a confidence floor so isolated weak signals
    // are not mathematically inflated to a perfect 1.0.
    _normalize(tagScores);
    _normalize(catScores);
    _normalize(authorScores);

    final topTags = _topN(tagScores, _topTags);
    final topCats = _topN(catScores, _topCats);
    final topAuthors = _topN(authorScores, _topAuthors);

    // Fix 3: serendipity source — categories present in history but below
    // the top-N cut, representing adjacent/less-dominant interests.
    final serendipityCats =
        _topN(catScores, _topCats + _serendipityCats).skip(_topCats).toList();

    // Fetch main candidates and serendipity candidates concurrently.
    final mainFutures = [
      for (final tag in topTags) _fetchDocs(t: tag),
      for (final cat in topCats) _fetchDocs(c: cat),
      for (final author in topAuthors) _fetchDocs(a: author),
    ];
    final serendipityFutures = [
      for (final cat in serendipityCats) _fetchDocs(c: cat),
    ];

    final allBatches = await Future.wait(
      [...mainFutures, ...serendipityFutures],
      eagerError: false,
    );
    final mainBatches = allBatches.take(mainFutures.length);
    final serendipityBatches = allBatches.skip(mainFutures.length);

    // Deduplicate main candidates, removing already-read comics.
    final seen = <String>{};
    final candidates = <Doc>[];
    for (final batch in mainBatches) {
      for (final doc in batch) {
        final cid = doc.uid;
        if (readCids.contains(cid)) continue;
        if (!seen.add(cid)) continue;
        candidates.add(doc);
      }
    }

    // Fix 1: score candidates using *averages* for tag and category overlap
    // so a comic with 15 mediocre tags can't outscore one with 3 perfect tags.
    final scored = candidates.map((doc) {
      double score = 0;

      // Average tag relevance — neutralises tag-stuffing.
      if (doc.tags.isNotEmpty) {
        final tagSum =
            doc.tags.fold(0.0, (s, tag) => s + (tagScores[tag] ?? 0.0));
        score += tagSum / doc.tags.length;
      }

      // Average category relevance.
      if (doc.categories.isNotEmpty) {
        final catSum = doc.categories
            .fold(0.0, (s, cat) => s + (catScores[cat] ?? 0.0));
        score += catSum / doc.categories.length;
      }

      // Author is a stronger signal — ×2 weight preserved.
      score += (authorScores[doc.author] ?? 0.0) * 2;

      return (doc: doc, score: score);
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    // Fix 3: build serendipity pool from adjacent-category results, excluding
    // anything already in the main candidate set.
    final serendipityPool = <Doc>[];
    for (final batch in serendipityBatches) {
      for (final doc in batch) {
        final cid = doc.uid;
        if (readCids.contains(cid)) continue;
        if (!seen.add(cid)) continue;
        serendipityPool.add(doc);
      }
    }
    serendipityPool.shuffle(_rng);

    final mainLimit = (_resultLimit * (1 - _serendipityRatio)).ceil();
    final serendipityLimit = _resultLimit - mainLimit;

    final mainPicks = scored.take(mainLimit).map((e) => e.doc).toList();
    final serendipityPicks = serendipityPool.take(serendipityLimit).toList();

    return _interleave(mainPicks, serendipityPicks);
  }

  /// Evenly interleaves [discovery] items into [main].
  List<Doc> _interleave(List<Doc> main, List<Doc> discovery) {
    if (discovery.isEmpty) return main;
    final result = <Doc>[];
    final step = max(1, main.length ~/ max(1, discovery.length));
    int di = 0;
    for (int i = 0; i < main.length; i++) {
      result.add(main[i]);
      if ((i + 1) % step == 0 && di < discovery.length) {
        result.add(discovery[di++]);
      }
    }
    while (di < discovery.length) {
      result.add(discovery[di++]);
    }
    return result;
  }

  void _normalize(Map<String, double> map) {
    if (map.isEmpty) return;
    final maxVal = map.values.reduce((a, b) => a > b ? a : b);
    // Fix 2: clamp denominator to _minConfidenceThreshold so that a single
    // weakly-engaged read can't be divided to an artificially perfect 1.0.
    final effectiveMax = max(maxVal, _minConfidenceThreshold);
    for (final k in map.keys) {
      map[k] = map[k]! / effectiveMax;
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
