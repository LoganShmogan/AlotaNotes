// Sync against a real Convex deployment, two devices and two accounts.
// Skipped unless pointed at one (see Docs/testing.md, "Live sync check"):
//
//   QUILLFIN_LIVE_CONVEX_URL=http://127.0.0.1:3210 \
//   QUILLFIN_LIVE_TOKEN_A=<ID token> QUILLFIN_LIVE_TOKEN_B=<ID token for another user> \
//   flutter test test/sync/convex_live_test.dart
//
// The deployment must accept the tokens (auth.config.ts), and the users
// should start empty: the test only adds rows with fresh uids, then deletes
// what it made.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:quillfin/auth/clerk_oauth.dart';
import 'package:quillfin/core/models.dart';
import 'package:quillfin/storage/folders_repo.dart';
import 'package:quillfin/storage/notes_repo.dart';
import 'package:quillfin/storage/questions_repo.dart';
import 'package:quillfin/sync/cloud_session.dart';
import 'package:quillfin/sync/convex_client.dart';
import 'package:quillfin/sync/sync_service.dart';

import '../helpers/test_env.dart';

final _env = Platform.environment;
final _url = _env['QUILLFIN_LIVE_CONVEX_URL'];
final _tokenA = _env['QUILLFIN_LIVE_TOKEN_A'];
final _tokenB = _env['QUILLFIN_LIVE_TOKEN_B'];

void main() {
  setUpTestEnv();
  final skip = _url == null || _tokenA == null || _tokenB == null
      ? 'Set QUILLFIN_LIVE_CONVEX_URL, QUILLFIN_LIVE_TOKEN_A and QUILLFIN_LIVE_TOKEN_B to run'
      : false;

  Future<(Database, SyncService)> device(String token) async {
    final db = await openTestDatabase();
    final client = ConvexClient(deploymentUrl: Uri.parse(_url!), token: () async => token);
    final sync = SyncService(db: db, client: client, userId: decodeJwtPayload(token)['sub'] as String);
    addTearDown(() async {
      sync.dispose();
      await db.close();
    });
    return (db, sync);
  }

  test('two devices converge through the real backend, and accounts stay apart', () async {
    final (dbA1, syncA1) = await device(_tokenA!);
    final (dbA2, syncA2) = await device(_tokenA!);
    final (dbB, syncB) = await device(_tokenB!);

    // Device 1 writes a folder, a note and a multiple-choice question.
    final folder = await FoldersRepo(dbA1).create('Live check ${DateTime.now().toIso8601String()}');
    final note = await NotesRepo(dbA1).create(folder.id, 'Cells', 'Mitochondria make ATP.');
    await QuestionsRepo(dbA1).create(note.id, questionTypeMultipleChoice, 'What makes ATP?', 'Mitochondria',
        choices: [('Mitochondria', true), ('Ribosomes', false)]);
    await syncA1.syncNow();
    expect(syncA1.value.error, isNull);
    expect(syncA1.value.pendingChanges, 0);

    // Device 2 gets all of it, linked up.
    await syncA2.syncNow();
    expect(syncA2.value.error, isNull);
    final folder2 = (await dbA2.query('folders', where: 'name = ?', whereArgs: [folder.name])).single;
    final note2 = (await NotesRepo(dbA2).listByFolder(folder2['id'] as int)).single;
    final question2 = (await QuestionsRepo(dbA2).listByNote(note2.id)).single;
    expect(question2.prompt, 'What makes ATP?');
    expect((await dbA2.query('question_choices', where: 'question_id = ?', whereArgs: [question2.id])), hasLength(2));

    // An edit on device 2 comes back to device 1.
    await NotesRepo(dbA2).update(note2.id, title: 'Cells (edited)');
    await syncA2.syncNow();
    await syncA1.syncNow();
    expect((await NotesRepo(dbA1).get(note.id)).title, 'Cells (edited)');

    // The other account sees none of it.
    await syncB.syncNow();
    expect(syncB.value.error, isNull);
    expect(await dbB.query('folders', where: 'name = ?', whereArgs: [folder.name]), isEmpty);

    // Deleting the folder on device 1 removes everything under it on device 2.
    await FoldersRepo(dbA1).delete(folder.id);
    await syncA1.syncNow();
    await syncA2.syncNow();
    expect(await dbA2.query('folders', where: 'name = ?', whereArgs: [folder.name]), isEmpty);
    expect(await dbA2.query('notes', where: 'id = ?', whereArgs: [note2.id]), isEmpty);
  }, skip: skip);

  test('the backend rejects an oversized push with its own error code', () async {
    final client = ConvexClient(deploymentUrl: Uri.parse(_url!), token: () async => _tokenA);
    await expectLater(
      client.mutation('sync:push', {
        'changes': {
          'folders': [
            for (var i = 0; i < 201; i++) {'uid': 'x$i', 'updatedAt': 1, 'deletedAt': 1},
          ],
        },
      }),
      throwsA(isA<ConvexException>().having((e) => e.code, 'code', 'BATCH_TOO_LARGE')),
    );
  }, skip: skip);

  test("the real billing:me parses as the app's PlanInfo", () async {
    final client = ConvexClient(deploymentUrl: Uri.parse(_url!), token: () async => _tokenA);
    final plan = PlanInfo.fromJson(Map<String, dynamic>.from(await client.query('billing:me') as Map));
    expect(plan.plan, anyOf('free', 'pro'));
    expect(plan.aiNotesLimit, greaterThan(0));
  }, skip: skip);
}
