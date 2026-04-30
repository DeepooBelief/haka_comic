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

  ReaderProvider createProvider(List<ComicReadRecord> savedRecords) {
    return ReaderProvider(
      state: ComicState(
        id: 'comic-id',
        title: 'Comic',
        chapters: [chapter],
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
}
