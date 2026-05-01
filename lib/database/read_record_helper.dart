import 'package:haka_comic/database/utils.dart';
import 'package:flutter/material.dart';
import 'package:haka_comic/utils/log.dart';
import 'package:sqlite_async/sqlite_async.dart';

final migrations = SqliteMigrations()
  ..add(
    SqliteMigration(1, (tx) async {
      await tx.execute('''
          CREATE TABLE IF NOT EXISTS read_record (
            id INTEGER PRIMARY KEY,
            cid TEXT UNIQUE NOT NULL,
            chapter_id TEXT NOT NULL,
            chapter_title TEXT NOT NULL,
            page_no INTEGER NOT NULL
          );
        ''');

      await tx.execute('''
          CREATE INDEX IF NOT EXISTS idx_read_record_cid
          ON read_record (cid);
        ''');
    }),
  )
  ..add(
    SqliteMigration(2, (tx) async {
      await tx.execute('''
          ALTER TABLE read_record ADD COLUMN chapter_no INTEGER DEFAULT 1;
        ''');
    }),
  );

class ReadRecordHelper with ChangeNotifier, DbBackupMixin {
  ReadRecordHelper._internal();

  static final _instance = ReadRecordHelper._internal();

  factory ReadRecordHelper() => _instance;

  @override
  String get dbName => 'read_record.db';

  @override
  Future<void> initialize() async {
    super.initialize();
    await migrations.migrate(db);
  }

  Future<void> insert(ComicReadRecord record) async {
    try {
      await db.writeTransaction((tx) async {
        await tx.execute(
          '''
          INSERT INTO read_record (cid, chapter_id, chapter_title, page_no, chapter_no)
          VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(cid) DO UPDATE SET
            chapter_id = excluded.chapter_id,
            chapter_title = excluded.chapter_title,
            page_no = excluded.page_no,
            chapter_no = excluded.chapter_no
          ''',
          [record.cid, record.chapterId, record.chapterTitle, record.pageNo, record.chapterNo],
        );
      });
      notifyListeners();
    } catch (e, st) {
      Log.e('insert read record error', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<ComicReadRecord?> query(String cid) async {
    final result = await db.getOptional(
      'SELECT * FROM read_record WHERE cid = ?',
      [cid],
    );
    return result == null ? null : ComicReadRecord.fromJson(result);
  }

  /// Returns a map of cid → (chapterNo, pageNo) for every comic the user
  /// has actually opened in the reader. Comics only visited on the detail
  /// page will NOT appear here.
  Future<Map<String, ({int chapterNo, int pageNo})>> queryAllPageNos() async {
    final rows = await db.getAll(
      'SELECT cid, chapter_no, page_no FROM read_record',
    );
    return {
      for (final r in rows)
        r['cid'] as String: (
          chapterNo: (r['chapter_no'] as int?) ?? 1,
          pageNo: r['page_no'] as int,
        ),
    };
  }
}

class ComicReadRecord {
  final String cid;
  final String chapterId;
  final String chapterTitle;
  final int pageNo;
  /// 1-based ordinal index of the chapter within the comic's chapter list.
  final int chapterNo;

  ComicReadRecord({
    required this.cid,
    required this.chapterId,
    required this.pageNo,
    required this.chapterTitle,
    this.chapterNo = 1,
  });

  Map<String, dynamic> toJson() => {
    'cid': cid,
    'chapterId': chapterId,
    'pageNo': pageNo,
    'chapterTitle': chapterTitle,
    'chapterNo': chapterNo,
  };

  factory ComicReadRecord.fromJson(Map<String, dynamic> json) =>
      ComicReadRecord(
        cid: json['cid'] as String,
        chapterId: json['chapter_id'] as String,
        chapterTitle: json['chapter_title'] as String,
        pageNo: json['page_no'] as int,
        chapterNo: (json['chapter_no'] as int?) ?? 1,
      );
}
