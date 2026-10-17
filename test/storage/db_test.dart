import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:quizapp/storage/db.dart';

import '../helpers/test_env.dart';

void main() {
  setUpTestEnv();

  group('timestamp helpers', () {
    test('dtToIso always stores UTC', () {
      final local = DateTime.utc(2026, 3, 1, 12).toLocal();
      expect(dtToIso(local), '2026-03-01T12:00:00.000Z');
    });

    test('isoToDt parses back to the same UTC instant', () {
      final value = DateTime.utc(2026, 3, 1, 12, 30);
      expect(isoToDt(dtToIso(value)), value);
      expect(isoToDt('2026-03-01T12:30:00.000Z').isUtc, isTrue);
    });

    test('utcNow is UTC', () {
      expect(utcNow().isUtc, isTrue);
    });
  });

  group('appDatabaseFactory', () {
    test('web uses the IndexedDB-backed factory (unavailable on the VM)', () {
      expect(() => appDatabaseFactory(isWeb: true), throwsUnsupportedError);
    });

    for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
      test('$platform uses the FFI factory', () {
        expect(appDatabaseFactory(platform: platform), same(databaseFactoryFfi));
      });
    }

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.macOS]) {
      test('$platform uses the sqflite plugin', () {
        expect(appDatabaseFactory(platform: platform), same(databaseFactorySqflitePlugin));
      });
    }

    test('defaults to the current platform', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(appDatabaseFactory(), same(databaseFactoryFfi));
    });
  });

  group('openAppDatabase', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('creates quizapp.db in the documents directory with the full schema', () async {
      final db = await openAppDatabase();
      addTearDown(db.close);

      expect(db.path, p.join(documentsDir.path, 'quizapp.db'));
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name");
      expect(
        tables.map((r) => r['name']),
        containsAll(['folders', 'notes', 'questions', 'question_choices', 'question_history']),
      );
    });

    test('enables foreign keys, so deleting a folder cascades to its notes', () async {
      final db = await openAppDatabase();
      addTearDown(db.close);

      expect((await db.rawQuery('PRAGMA foreign_keys')).first.values.first, 1);
      final folderId = await db.insert('folders', {'name': 'F', 'created_at': dtToIso(utcNow())});
      await db.insert('notes', {
        'folder_id': folderId,
        'title': 'T',
        'body': '',
        'created_at': dtToIso(utcNow()),
        'updated_at': dtToIso(utcNow()),
      });
      await db.delete('folders', where: 'id = ?', whereArgs: [folderId]);
      expect(await db.query('notes'), isEmpty);
    });

    test('reopening keeps existing data (schema is only created once)', () async {
      final first = await openAppDatabase();
      await first.insert('folders', {'name': 'Kept', 'created_at': dtToIso(utcNow())});
      await first.close();

      final second = await openAppDatabase();
      addTearDown(second.close);
      expect((await second.query('folders')).single['name'], 'Kept');
    });
  });
}
