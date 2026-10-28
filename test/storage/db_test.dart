import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:quillfin/core/models.dart';
import 'package:quillfin/storage/db.dart';

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

    test('creates quillfin.db in the documents directory with the full schema', () async {
      final db = await openAppDatabase();
      addTearDown(db.close);

      expect(db.path, p.join(documentsDir.path, 'quillfin.db'));
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name");
      expect(
        tables.map((r) => r['name']),
        containsAll([
          'folders',
          'notes',
          'questions',
          'question_choices',
          'question_history',
          'problems',
          'problem_attempts',
        ]),
      );
      expect(await db.getVersion(), schemaVersion);
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

    test('adopts a pre-QuillFin quizapp.db and upgrades it to FSRS, keeping every row and id', () async {
      // Written under the old file name, as the app did before the rename.
      final path = p.join(documentsDir.path, 'quizapp.db');
      final v1 = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            for (final statement in schemaStatementsV1) {
              await db.execute(statement);
            }
          },
        ),
      );
      final created = dtToIso(DateTime.utc(2026, 1, 1));
      final folderId = await v1.insert('folders', {'name': 'Bio', 'created_at': created});
      final noteId = await v1.insert('notes', {
        'folder_id': folderId,
        'title': 'Cells',
        'body': '',
        'created_at': created,
        'updated_at': created,
      });
      Map<String, Object?> question(String prompt, int index, String? lastAsked, String due) => {
            'note_id': noteId,
            'question_type': 'multiple_choice',
            'prompt': prompt,
            'expected_answer': 'A',
            'interval_index': index,
            'last_asked_at': lastAsked,
            'next_due_at': due,
            'created_at': created,
            'active': 1,
            'is_manually_edited': 1,
          };
      final freshId = await v1.insert('questions', question('Fresh', 0, null, '2026-01-02T00:00:00.000Z'));
      final seenId = await v1.insert('questions', question('Seen', 3, '2026-01-10T00:00:00.000Z', '2026-01-15T00:00:00.000Z'));
      await v1.insert('question_choices', {'question_id': seenId, 'choice_text': 'A', 'is_correct': 1, 'sort_order': 0});
      for (final (correct, after) in [(0, 0), (1, 3)]) {
        await v1.insert('question_history', {
          'question_id': seenId,
          'asked_at': '2026-01-10T00:00:00.000Z',
          'given_answer': 'A',
          'is_correct': correct,
          'interval_index_before': 0,
          'interval_index_after': after,
          'grading_method': 'mcq_exact',
        });
      }
      await v1.close();

      final db = await openAppDatabase();
      addTearDown(db.close);
      expect(db.path, p.join(documentsDir.path, 'quillfin.db'));
      expect(File(path).existsSync(), isFalse);
      expect(await db.getVersion(), schemaVersion);
      expect((await db.rawQuery('PRAGMA foreign_keys')).first.values.first, 1);

      final questions = {for (final row in await db.query('questions')) row['id']: row};
      final fresh = srsCardFromRow(questions[freshId]!)!;
      expect((fresh.state, fresh.step, fresh.due), (srsStateLearning, 0, DateTime.utc(2026, 1, 2)));
      final seen = srsCardFromRow(questions[seenId]!)!;
      expect((seen.state, seen.stability, seen.difficulty), (srsStateReview, 5.0, 5.0));
      expect((seen.due, seen.lastReview), (DateTime.utc(2026, 1, 15), DateTime.utc(2026, 1, 10)));
      expect((questions[seenId]!['prompt'], questions[seenId]!['is_manually_edited']), ('Seen', 1));

      // Choices survive the questions table being rebuilt underneath them.
      expect((await db.query('question_choices')).single['question_id'], seenId);
      final history = await db.query('question_history', orderBy: 'id');
      expect(history.map((r) => r['rating']), [1, 3]); // wrong -> Again, right -> Good
      expect(history.map((r) => r['next_due_after']), ['2026-01-11T00:00:00.000Z', '2026-01-15T00:00:00.000Z']);
      expect(await db.query('problems'), isEmpty);

      // And the rebuilt tables still cascade.
      await db.delete('folders');
      expect(await db.query('question_history'), isEmpty);
    });
  });

  group('adoptLegacyDatabaseFile', () {
    test('leaves an existing quillfin.db alone', () async {
      File(p.join(documentsDir.path, 'quizapp.db')).writeAsStringSync('old');
      File(p.join(documentsDir.path, 'quillfin.db')).writeAsStringSync('new');
      await adoptLegacyDatabaseFile(documentsDir.path);
      expect(File(p.join(documentsDir.path, 'quillfin.db')).readAsStringSync(), 'new');
      expect(File(p.join(documentsDir.path, 'quizapp.db')).existsSync(), isTrue);
    });

    test('does nothing without an old file', () async {
      await adoptLegacyDatabaseFile(documentsDir.path);
      expect(documentsDir.listSync(), isEmpty);
    });
  });

  group('srs card columns', () {
    test('round-trip every field', () {
      final card = SrsCard(
        state: srsStateRelearning,
        step: 0,
        stability: 2.5,
        difficulty: 6.1,
        due: DateTime.utc(2026, 2, 1),
        lastReview: DateTime.utc(2026, 1, 31),
      );
      final back = srsCardFromRow(srsCardToRow(card))!;
      expect((back.state, back.step, back.stability, back.difficulty, back.due, back.lastReview),
          (card.state, card.step, card.stability, card.difficulty, card.due, card.lastReview));
    });

    test('a null card clears every column and reads back as null', () {
      final row = srsCardToRow(null);
      expect(row.values, everyElement(isNull));
      expect(srsCardFromRow(row), isNull);
    });
  });
}
