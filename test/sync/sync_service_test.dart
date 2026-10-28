import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:quillfin/storage/folders_repo.dart';
import 'package:quillfin/storage/notes_repo.dart';
import 'package:quillfin/sync/convex_client.dart';
import 'package:quillfin/sync/sync_service.dart';

import '../helpers/fake_convex.dart';
import '../helpers/test_env.dart';

void main() {
  setUpTestEnv();
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeConvex server;
  setUp(() => server = FakeConvex());

  ConvexClient clientFor(String? token) => ConvexClient(
        deploymentUrl: Uri.parse('https://quillfin-test.convex.cloud'),
        token: () async => token,
        httpClient: server.httpClient,
      );

  /// One device: its own database, signed in as alice unless told otherwise.
  Future<(Database, SyncService)> device({String token = 'token-alice', String user = 'user_alice', VoidCallback? onRemote}) async {
    final db = await openTestDatabase();
    final sync = SyncService(db: db, client: clientFor(token), userId: user, onRemoteChanges: onRemote);
    addTearDown(() async {
      sync.dispose();
      await db.close();
    });
    return (db, sync);
  }

  test('a note made on one device reaches another, and edits and deletes follow', () async {
    final (dbA, syncA) = await device();
    var remoteChanges = 0;
    final (dbB, syncB) = await device(onRemote: () => remoteChanges++);

    final folder = await FoldersRepo(dbA).create('Bio');
    final note = await NotesRepo(dbA).create(folder.id, 'Cells', 'ATP');
    await syncA.syncNow();
    expect(syncA.value.phase, SyncPhase.idle);
    expect(syncA.value.pendingChanges, 0);
    expect(syncA.value.lastSyncedAt, isNotNull);
    expect(server.rows('user_alice', 'notes'), hasLength(1));

    await syncB.syncNow();
    expect(remoteChanges, 1);
    final notesB = await NotesRepo(dbB).listByFolder((await FoldersRepo(dbB).listChildren(null)).single.id);
    expect(notesB.single.title, 'Cells');

    await NotesRepo(dbB).update(notesB.single.id, title: 'Cells, edited on B');
    await syncB.syncNow();
    await syncA.syncNow();
    expect((await NotesRepo(dbA).get(note.id)).title, 'Cells, edited on B');

    await FoldersRepo(dbA).delete(folder.id);
    await syncA.syncNow();
    await syncB.syncNow();
    expect(await FoldersRepo(dbB).listChildren(null), isEmpty);
    expect(await dbB.query('notes'), isEmpty);
  });

  test('pushes in batches of 200 and pulls in pages', () async {
    final (dbA, syncA) = await device();
    final folders = FoldersRepo(dbA);
    for (var i = 0; i < 450; i++) {
      await folders.create('F$i');
    }
    await syncA.syncNow();
    expect(server.calls.where((c) => c == 'mutation:sync:push'), hasLength(3));
    expect(server.rows('user_alice', 'folders'), hasLength(450));

    final (dbB, syncB) = await device();
    server.calls.clear();
    await syncB.syncNow();
    expect(server.calls.where((c) => c == 'query:sync:pull'), hasLength(3));
    expect(await dbB.query('folders'), hasLength(450));
  });

  test('a server error is reported, and the next sync recovers', () async {
    final (dbA, syncA) = await device();
    await FoldersRepo(dbA).create('Bio');
    server.failNext['sync:push'] = {'code': 'ROW_LIMIT', 'message': "You've reached the limit of 50,000 folders."};

    await syncA.syncNow();
    expect(syncA.value.phase, SyncPhase.error);
    expect(syncA.value.errorCode, 'ROW_LIMIT');
    expect(syncA.value.error, contains('50,000 folders'));
    expect(syncA.value.pendingChanges, 1);

    await syncA.syncNow();
    expect(syncA.value.phase, SyncPhase.idle);
    expect(syncA.value.error, isNull);
    expect(syncA.value.pendingChanges, 0);
  });

  test('offline, changes wait and the error says so', () async {
    final (dbA, syncA) = await device();
    await FoldersRepo(dbA).create('Bio');
    server.offline = true;
    await syncA.syncNow();
    expect(syncA.value.errorCode, ConvexException.networkError);
    expect(syncA.value.pendingChanges, 1);

    server.offline = false;
    await syncA.syncNow();
    expect(server.rows('user_alice', 'folders'), hasLength(1));
  });

  test('signed out (no token) is an error, not a crash', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    final sync = SyncService(db: db, client: clientFor(null), userId: 'user_alice');
    addTearDown(sync.dispose);
    await sync.syncNow();
    expect(sync.value.errorCode, ConvexException.unauthenticated);
  });

  test("accounts don't see each other's data", () async {
    final (dbA, syncA) = await device();
    await FoldersRepo(dbA).create('Alice only');
    await syncA.syncNow();
    final (dbBob, syncBob) = await device(token: 'token-bob', user: 'user_bob');
    await syncBob.syncNow();
    expect(await dbBob.query('folders'), isEmpty);
  });

  test('a call while syncing queues exactly one more run', () async {
    final (dbA, syncA) = await device();
    await FoldersRepo(dbA).create('Bio');
    final first = syncA.syncNow();
    final second = syncA.syncNow();
    final third = syncA.syncNow();
    await Future.wait([first, second, third]);
    expect(server.calls.where((c) => c == 'mutation:users:ensure'), hasLength(1));
    expect(server.calls.where((c) => c == 'query:sync:pull'), hasLength(2));
  });

  testWidgets('start syncs at once, then on resume, on local changes and on the timer', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      final sync = SyncService(
        db: db,
        client: clientFor('token-alice'),
        userId: 'user_alice',
        interval: const Duration(milliseconds: 500),
        changeCheckInterval: const Duration(milliseconds: 50),
      );
      sync.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server.calls.where((c) => c == 'query:sync:pull'), hasLength(1));

      // A local change is picked up by the change check.
      await FoldersRepo(db).create('Bio');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(server.rows('user_alice', 'folders'), hasLength(1));

      final pulls = server.calls.where((c) => c == 'query:sync:pull').length;
      sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
      sync.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(server.calls.where((c) => c == 'query:sync:pull').length, pulls + 1);

      // The periodic timer runs with nothing to push.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(server.calls.where((c) => c == 'query:sync:pull').length, greaterThan(pulls + 1));

      sync.dispose();
      await db.close();
    });
  });

  test('a database closed mid-sync after dispose is ignored', () async {
    final db = await openTestDatabase();
    final sync = SyncService(db: db, client: clientFor('token-alice'), userId: 'user_alice');
    final running = sync.syncNow();
    sync.dispose();
    await db.close();
    await running;
  });

  test('a database error while still running is reported', () async {
    final db = await openTestDatabase();
    final sync = SyncService(db: db, client: clientFor('token-alice'), userId: 'user_alice');
    addTearDown(sync.dispose);
    await db.execute('DROP TABLE sync_tombstones');
    await sync.syncNow();
    expect(sync.value.phase, SyncPhase.error);
    expect(sync.value.error, startsWith('Sync failed'));
    await db.close();
  });

  group('ConvexClient', () {
    ConvexClient withResponse(http.Response Function(http.Request) respond) => ConvexClient(
          deploymentUrl: Uri.parse('https://x.convex.cloud'),
          token: () async => 't',
          httpClient: MockClient((r) async => respond(r)),
        );

    test('posts the path and args to the right endpoint with the bearer token', () async {
      late http.Request seen;
      final client = withResponse((r) {
        seen = r;
        return http.Response(jsonEncode({'status': 'success', 'value': 42}), 200);
      });
      expect(await client.action('ai:generateQuestions', {'n': 1}), 42);
      expect(seen.url.toString(), 'https://x.convex.cloud/api/action');
      expect(seen.headers['authorization'], 'Bearer t');
      expect(jsonDecode(seen.body), {'path': 'ai:generateQuestions', 'args': {'n': 1}, 'format': 'json'});
    });

    test('a 401 without error data means the session expired', () async {
      final client = withResponse((_) => http.Response('Unauthorized', 401));
      await expectLater(
        client.query('x:y'),
        throwsA(isA<ConvexException>().having((e) => e.code, 'code', ConvexException.unauthenticated)),
      );
    });

    test('other failures become a generic server error', () async {
      final client = withResponse((_) => http.Response(jsonEncode({'status': 'error', 'errorMessage': 'Server Error'}), 500));
      await expectLater(
        client.query('x:y'),
        throwsA(isA<ConvexException>()
            .having((e) => e.code, 'code', ConvexException.serverError)
            .having((e) => e.toString(), 'message', contains('HTTP 500'))),
      );
    });

    test('a ConvexError without a message uses its code', () async {
      final client = withResponse((_) => http.Response(jsonEncode({'status': 'error', 'errorData': {'code': 'ODD'}}), 400));
      await expectLater(client.query('x:y'), throwsA(isA<ConvexException>().having((e) => e.message, 'message', 'ODD')));
    });

    test('defaults to a real HTTP client', () {
      expect(ConvexClient(deploymentUrl: Uri.parse('https://x'), token: () async => 't').httpClient, isA<http.Client>());
    });

    test('a failure refreshing the sign-in is a network error', () async {
      final client = ConvexClient(
        deploymentUrl: Uri.parse('https://x.convex.cloud'),
        token: () async => throw Exception('offline'),
        httpClient: MockClient((_) async => http.Response('', 200)),
      );
      await expectLater(
        client.query('x:y'),
        throwsA(isA<ConvexException>()
            .having((e) => e.code, 'code', ConvexException.networkError)
            .having((e) => e.message, 'message', contains("Couldn't refresh your sign-in"))),
      );
    });

    test('a timeout is a network error', () async {
      final client = ConvexClient(
        deploymentUrl: Uri.parse('https://x.convex.cloud'),
        token: () async => 't',
        timeout: const Duration(milliseconds: 10),
        httpClient: MockClient((_) => Future.delayed(const Duration(seconds: 1), () => http.Response('', 200))),
      );
      await expectLater(
        client.query('x:y'),
        throwsA(isA<ConvexException>().having((e) => e.code, 'code', ConvexException.networkError)),
      );
    });
  });
}
