import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:haka_comic/database/read_record_helper.dart';
import 'package:haka_comic/network/models.dart';
import 'package:haka_comic/views/reader/providers/reader_provider.dart';
import 'package:haka_comic/views/reader/state/comic_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final chapter = Chapter(
    uid: 'chapter-uid',
    title: 'Chapter 1',
    order: 1,
    updated_at: '',
    id: 'chapter-id',
  );
  final nextChapter = Chapter(
    uid: 'next-chapter-uid',
    title: 'Chapter 2',
    order: 2,
    updated_at: '',
    id: 'next-chapter-id',
  );

  ReaderProvider createProvider(
    List<ComicReadRecord> savedRecords, {
    List<Chapter>? chapters,
  }) {
    return ReaderProvider(
      state: ComicState(
        id: 'comic-id',
        title: 'Comic',
        chapters: chapters ?? [chapter],
        chapter: chapter,
        pageNo: 0,
      ),
      fetchImages: (_) => Completer<List<ImageBase>>().future,
      saveReadRecord: (record) async {
        savedRecords.add(record);
      },
      readRecordDebounceDuration: const Duration(milliseconds: 50),
    );
  }

  testWidgets(
    'updates pageNo immediately while debouncing read record writes',
    (tester) async {
      final savedRecords = <ComicReadRecord>[];
      final provider = createProvider(savedRecords);

      provider.onPageNoChanged(3);

      expect(provider.pageNo, 3);
      expect(savedRecords, isEmpty);

      await tester.pump(const Duration(milliseconds: 25));

      provider.onPageNoChanged(0);

      expect(provider.pageNo, 0);

      await tester.pump(const Duration(milliseconds: 49));

      expect(savedRecords, isEmpty);

      await tester.pump(const Duration(milliseconds: 1));

      expect(savedRecords, hasLength(1));
      expect(savedRecords.single.pageNo, 0);

      provider.onPageNoChanged(0);
      await tester.pump(const Duration(milliseconds: 50));

      expect(savedRecords, hasLength(1));
    },
  );

  testWidgets(
    'smooth scroll waits while the vertical list controller is detached',
    (tester) async {
      final provider = createProvider(
        <ComicReadRecord>[],
        chapters: [chapter, nextChapter],
      );

      provider.handler.mutate([
        LocalImage(uid: 'page-1', id: 'page-1', url: 'page-1.jpg'),
        LocalImage(uid: 'page-2', id: 'page-2', url: 'page-2.jpg'),
      ]);

      provider.startSmoothScroll(const TestVSync());
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(provider.isPageTurning, isTrue);
      expect(provider.isSmoothScroll, isTrue);

      provider.stopPageTurn();
    },
  );
}
