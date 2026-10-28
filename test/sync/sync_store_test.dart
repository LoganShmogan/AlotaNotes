import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:quillfin/core/models.dart';
import 'package:quillfin/storage/db.dart';
import 'package:quillfin/storage/folders_repo.dart';
import 'package:quillfin/storage/notes_repo.dart';
import 'package:quillfin/storage/problems_repo.dart';
import 'package:quillfin/storage/questions_repo.dart';
import 'package:quillfin/sync/sync_store.dart';
import 'package:quillfin/sync/sync_tables.dart';

import '../helpers/test_env.dart';

Map<String, Object?> folderRow(String uid, String name, {int updatedAt = 1000, String? parent}) => {
      'uid': uid,
      'updatedAt': updatedAt,
      'deletedAt': null,
      'data': {'parentFolderUid': parent, 'name': name, 'createdAt': '2026-10-01T00:00:00.000Z'},
    };
Map<String, Object?> noteRow(String uid, String folderUid) => {
      'uid': uid,
      'updatedAt': 1000,
      'deletedAt': null,
      'data': {
        'folderUid': folderUid,
        'title': 'Cells',
        'body': 'ATP',
        'sourceFilename': null,
        'sortOrder': 0,
        'createdAt': '2026-10-01T00:00:00.000Z',
        'updatedAt': '2026-10-01T00:00:00.000Z',
      },
    };


void main() {
  setUpTestEnv();

  late Database db;
  late SyncStore store;

  setUp(() async {
    db = await openTestDatabase();
    store = SyncStore(db);
  });
  tearDown(() => db.close());

  Future<Map<String, Object?>> row(String table, int id) async =>
      (await db.query(table, where: 'id = ?', whereArgs: [id])).single;

  Future<void> markAllClean() async => store.markPushed(await store.nextPushBatch());

  group('triggers', () {
    test('every synced table in db.dart has a mapping', () {
      expect(syncTables.map((t) => t.local), syncedLocalTables);
    });

    test('a new row gets a uid, a clock and the dirty flag', () async {
      final before = DateTime.now().millisecondsSinceEpoch;
      final folder = await FoldersRepo(db).create('Bio');
      final r = await row('folders', folder.id);
      expect(r['uid'], matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(r['dirty'], 1);
      expect(r['sync_updated_at'] as int, greaterThanOrEqualTo(before - 1));
    });

    test('an edit after a push makes the row dirty again with a newer clock', () async {
      final note = await NotesRepo(db).create((await FoldersRepo(db).create('Bio')).id, 'Cells', 'ATP');
      await markAllClean();
      final pushed = await row('notes', note.id);
      expect(pushed['dirty'], 0);

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await NotesRepo(db).update(note.id, title: 'Cells 2', body: 'ATP');
      final edited = await row('notes', note.id);
      expect(edited['dirty'], 1);
      expect(edited['uid'], pushed['uid']);
      expect(edited['sync_updated_at'] as int, greaterThan(pushed['sync_updated_at'] as int));
    });

    test('deleting a row, including by cascade, leaves a tombstone for each', () async {
      final folder = await FoldersRepo(db).create('Bio');
      final note = await NotesRepo(db).create(folder.id, 'Cells', 'ATP');
      await QuestionsRepo(db).create(note.id, questionTypeMultipleChoice, 'Q', 'A', choices: [('A', true), ('B', false)]);
      final uids = {for (final t in ['folders', 'notes', 'questions']) t: (await db.query(t)).single['uid']};

      await FoldersRepo(db).delete(folder.id);
      final tombstones = await db.query('sync_tombstones');
      expect(tombstones.map((t) => t['table_name']).toList()..sort(),
          ['folders', 'notes', 'question_choices', 'question_choices', 'questions']);
      for (final entry in uids.entries) {
        expect(tombstones.where((t) => t['table_name'] == entry.key).single['uid'], entry.value);
      }
    });
  });

  group('migration v2 -> v3', () {
    test('gives existing rows uids and queues them all for the first push', () async {
      final v2 = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(v2.close);
      for (final statement in schemaStatementsV2) {
        await v2.execute(statement);
      }
      final folderId = await v2.insert('folders', {'name': 'Bio', 'created_at': dtToIso(utcNow())});
      await v2.insert('folders', {'name': 'Chem', 'created_at': dtToIso(utcNow())});
      await v2.insert('notes', {
        'folder_id': folderId,
        'title': 'Cells',
        'body': '',
        'created_at': dtToIso(utcNow()),
        'updated_at': dtToIso(utcNow()),
      });

      await migrateSchema(v2, 2);
      final folders = await v2.query('folders');
      expect(folders.map((f) => f['uid']).toSet(), hasLength(2));
      expect(folders.every((f) => f['dirty'] == 1 && (f['sync_updated_at'] as int) > 0), isTrue);
      expect(await SyncStore(v2).pendingChanges(), 3);
      expect(await SyncStore(v2).cursor(), 0);
    });
  });

  group('nextPushBatch', () {
    test('maps local rows to the server shape, with parent uids and booleans', () async {
      final folder = await FoldersRepo(db).create('Bio', now: DateTime.utc(2026, 10, 1));
      final note = await NotesRepo(db).create(folder.id, 'Cells', 'ATP', now: DateTime.utc(2026, 10, 1));
      await QuestionsRepo(db).create(note.id, questionTypeMultipleChoice, 'Q', 'A',
          choices: [('A', true)], now: DateTime.utc(2026, 10, 1));
      final uid = {for (final t in ['folders', 'notes', 'questions']) t: (await db.query(t)).single['uid']};

      final batch = await store.nextPushBatch();
      expect(batch.length, 4);
      expect(batch.changes['folders']!.single['data'], {
        'parentFolderUid': null,
        'name': 'Bio',
        'createdAt': '2026-10-01T00:00:00.000Z',
      });
      expect(batch.changes['notes']!.single['data'], containsPair('folderUid', uid['folders']));
      final question = batch.changes['questions']!.single;
      expect(question['uid'], uid['questions']);
      expect(question['updatedAt'], isA<int>());
      expect(question['data'], containsPair('noteUid', uid['notes']));
      expect(question['data'], containsPair('active', true));
      expect(question['data'], containsPair('isManuallyEdited', false));
      expect(batch.changes['questionChoices']!.single['data'],
          {'questionUid': uid['questions'], 'choiceText': 'A', 'isCorrect': true, 'sortOrder': 0});
    });

    test('maps problems and attempts, including FSRS fields', () async {
      final problem = await ProblemsRepo(db).create('Two Sum', difficulty: problemDifficultyEasy, tags: ['array']);
      final card = SrsCard(state: srsStateReview, step: null, stability: 3.5, difficulty: 5, due: DateTime.utc(2026, 11, 1), lastReview: DateTime.utc(2026, 10, 28));
      await ProblemsRepo(db).recordAttempt(problem.id, solved: true, rating: ReviewRating.good, after: card, durationMinutes: 12);

      final batch = await store.nextPushBatch();
      final p = batch.changes['problems']!.single['data'] as Map;
      expect(p['difficulty'], 'easy');
      expect(p['fsrsState'], srsStateReview);
      expect(p['fsrsStability'], 3.5);
      expect(p['fsrsDifficulty'], isA<double>());
      final attempt = batch.changes['problemAttempts']!.single['data'] as Map;
      expect(attempt['problemUid'], batch.changes['problems']!.single['uid']);
      expect((attempt['solved'], attempt['durationMinutes'], attempt['rating']), (true, 12, 3));
    });

    test('respects the limit across tables, and sends deletions after changes', () async {
      final folders = FoldersRepo(db);
      for (var i = 0; i < 3; i++) {
        await folders.create('F$i');
      }
      final doomed = await ProblemsRepo(db).create('Old');
      await markAllClean();
      await ProblemsRepo(db).delete(doomed.id);
      await folders.create('F3');
      await folders.create('F4');

      final first = await store.nextPushBatch(limit: 1);
      expect(first.length, 1);
      expect(first.changes['folders']!.single['data'], containsPair('name', 'F3'));

      final both = await store.nextPushBatch(limit: 3);
      expect(both.changes['folders'], hasLength(2));
      expect(both.changes['problems']!.single, {
        'uid': (await db.query('sync_tombstones')).single['uid'],
        'updatedAt': (await db.query('sync_tombstones')).single['deleted_at'],
        'deletedAt': (await db.query('sync_tombstones')).single['deleted_at'],
      });
    });

    test('holds back notes over the size limit and reports them', () async {
      final folder = await FoldersRepo(db).create('Bio');
      await NotesRepo(db).create(folder.id, 'Huge', 'é' * (maxSyncedNoteBytes ~/ 2 + 1));
      await NotesRepo(db).create(folder.id, 'Small', 'ok');

      final batch = await store.nextPushBatch();
      expect(batch.changes['notes']!.single['data'], containsPair('title', 'Small'));
      expect(await store.oversizedNotes(), 1);
      expect(await store.pendingChanges(), 2); // the folder and the small note
    });
  });

  group('markPushed', () {
    test('clears the pushed rows and tombstones', () async {
      final folder = await FoldersRepo(db).create('Bio');
      await FoldersRepo(db).create('Chem');
      await markAllClean();
      await FoldersRepo(db).delete(folder.id);
      expect(await store.pendingChanges(), 1);

      await store.markPushed(await store.nextPushBatch());
      expect(await store.pendingChanges(), 0);
      expect(await db.query('sync_tombstones'), isEmpty);
    });

    test('keeps a row dirty if it changed again after being read', () async {
      final folder = await FoldersRepo(db).create('Bio');
      final batch = await store.nextPushBatch();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await db.update('folders', {'name': 'Biology'}, where: 'id = ?', whereArgs: [folder.id]);

      await store.markPushed(batch);
      expect((await row('folders', folder.id))['dirty'], 1);
    });
  });

  group('applyPulled', () {
    test('inserts new rows as clean, linking children to local parent ids', () async {
      final applied = await store.applyPulled({
        'folders': [folderRow('fa', 'Bio')],
        'notes': [noteRow('na', 'fa')],
      });
      expect(applied, 2);
      final folder = (await db.query('folders')).single;
      final note = (await db.query('notes')).single;
      expect((folder['name'], folder['uid'], folder['dirty'], folder['sync_updated_at']), ('Bio', 'fa', 0, 1000));
      expect(note['folder_id'], folder['id']);
      expect(await store.pendingChanges(), 0);
      expect((await db.query('sync_state')).single['applying'], 0);
    });

    test('updates an existing row, and a newer local edit wins over an older pull', () async {
      await store.applyPulled({'folders': [folderRow('fa', 'Bio')]});
      await store.applyPulled({'folders': [folderRow('fa', 'Biology', updatedAt: 2000)]});
      expect((await db.query('folders')).single['name'], 'Biology');

      await db.update('folders', {'name': 'Mine'});
      final local = (await db.query('folders')).single;
      expect(local['dirty'], 1);
      await store.applyPulled({'folders': [folderRow('fa', 'Older', updatedAt: (local['sync_updated_at'] as int) - 1)]});
      expect((await db.query('folders')).single['name'], 'Mine');
    });

    test('deletes on a tombstone without making a tombstone of its own', () async {
      await store.applyPulled({
        'folders': [folderRow('fa', 'Bio')],
        'notes': [noteRow('na', 'fa')],
      });
      final applied = await store.applyPulled({
        'folders': [
          {'uid': 'fa', 'updatedAt': 2000, 'deletedAt': 2000, 'data': null},
          {'uid': 'never-seen', 'updatedAt': 2000, 'deletedAt': 2000, 'data': null},
        ],
      });
      expect(applied, 1);
      expect(await db.query('folders'), isEmpty);
      expect(await db.query('notes'), isEmpty);
      expect(await db.query('sync_tombstones'), isEmpty);
    });

    test('holds a child back until its parent arrives', () async {
      // A subfolder and a note arrive before the folder they belong to.
      expect(
        await store.applyPulled({
          'folders': [folderRow('sub', 'Cells', parent: 'top')],
          'notes': [noteRow('na', 'sub')],
        }),
        0,
      );
      expect(await store.heldBackRows(), 2);

      expect(await store.applyPulled({'folders': [folderRow('top', 'Bio')]}), 3);
      expect(await store.heldBackRows(), 0);
      final sub = (await db.query('folders', where: 'uid = ?', whereArgs: ['sub'])).single;
      final top = (await db.query('folders', where: 'uid = ?', whereArgs: ['top'])).single;
      expect(sub['parent_folder_id'], top['id']);
      expect((await db.query('notes')).single['folder_id'], sub['id']);
    });

    test('a later version or a delete replaces a held-back row', () async {
      await store.applyPulled({'notes': [noteRow('na', 'missing')]});
      final pending = (await db.query('sync_pending')).single;
      expect(jsonDecode(pending['payload'] as String)['uid'], 'na');

      await store.applyPulled({
        'notes': [
          {'uid': 'na', 'updatedAt': 2000, 'deletedAt': 2000, 'data': null},
        ],
      });
      expect(await store.heldBackRows(), 0);
    });

    test('rolls back, leaving the triggers on, if a row is malformed', () async {
      await expectLater(
        store.applyPulled({
          'folders': [
            folderRow('fa', 'Bio'),
            {'uid': 'bad', 'updatedAt': 1000, 'deletedAt': null, 'data': {'parentFolderUid': null}},
          ],
        }),
        throwsA(anything),
      );
      expect(await db.query('folders'), isEmpty);
      expect((await db.query('sync_state')).single['applying'], 0);
    });
  });

  group('account binding', () {
    test('the first account takes the local data as it is', () async {
      await FoldersRepo(db).create('Bio');
      await store.bindUser('user_a');
      expect(await store.userId(), 'user_a');
      expect(await store.pendingChanges(), 1);
    });

    test('switching accounts re-sends everything and pulls from the start', () async {
      await FoldersRepo(db).create('Bio');
      await store.bindUser('user_a');
      await markAllClean();
      await store.setCursor(42);
      await store.setLastSyncedAt(DateTime.utc(2026, 10, 28));

      await store.bindUser('user_a');
      expect(await store.cursor(), 42);

      await store.bindUser('user_b');
      expect(await store.cursor(), 0);
      expect(await store.lastSyncedAt(), isNull);
      expect(await store.pendingChanges(), 1);
    });

    test('last sync time round-trips in UTC', () async {
      await store.setLastSyncedAt(DateTime.utc(2026, 10, 28, 9, 30));
      expect(await store.lastSyncedAt(), DateTime.utc(2026, 10, 28, 9, 30));
    });

    test('deleteLocalData empties every table without leaving tombstones', () async {
      final folder = await FoldersRepo(db).create('Bio');
      await NotesRepo(db).create(folder.id, 'Cells', 'ATP');
      await ProblemsRepo(db).create('Two Sum');
      await store.applyPulled({'notes': [noteRow('orphan', 'missing')]});
      await store.bindUser('user_a');

      await store.deleteLocalData();
      for (final table in [...syncedLocalTables, 'sync_tombstones', 'sync_pending']) {
        expect(await db.query(table), isEmpty, reason: table);
      }
      expect(await store.userId(), isNull);
      expect((await db.query('sync_state')).single['applying'], 0);

      // The triggers are back on afterwards.
      await FoldersRepo(db).create('New');
      expect(await store.pendingChanges(), 1);
    });
  });
}
