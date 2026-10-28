// The signed-in side of the app: account sign-in, sync starting with the
// shell, Settings > Sync and > Plan, signing out, and AI generation on
// QuillFin's key. The backend is FakeConvex; nothing leaves the machine.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:quillfin/ai/base.dart';
import 'package:quillfin/app.dart';
import 'package:quillfin/auth/auth_service.dart';
import 'package:quillfin/auth/clerk_oauth.dart';
import 'package:quillfin/screens/account/account_screen.dart';
import 'package:quillfin/screens/login/login_screen.dart';
import 'package:quillfin/screens/notes/note_editor_screen.dart';
import 'package:quillfin/screens/root_shell.dart';
import 'package:quillfin/screens/settings/cloud_sections.dart';
import 'package:quillfin/screens/settings/settings_screen.dart';
import 'package:quillfin/services/reminder_service.dart';
import 'package:quillfin/storage/folders_repo.dart';
import 'package:quillfin/storage/notes_repo.dart';
import 'package:quillfin/storage/questions_repo.dart';
import 'package:quillfin/sync/cloud_session.dart';
import 'package:quillfin/sync/sync_service.dart';

import '../helpers/fake_auth.dart';
import '../helpers/fake_convex.dart';
import '../helpers/fake_url_launcher.dart';
import '../helpers/test_env.dart';

final linux = TargetPlatformVariant.only(TargetPlatform.linux);

void main() {
  setUpTestEnv();

  late FakeConvex server;
  late FakeUrlLauncher launcher;
  setUp(() {
    server = FakeConvex();
    launcher = FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  /// A session over [db] as alice, without starting the timers.
  Future<CloudSession> sessionFor(Database db) async {
    final auth = await signedInToCloud(server);
    final client = auth.convexClient()!;
    final sync = SyncService(db: db, client: client, userId: 'user_alice');
    addTearDown(sync.dispose);
    return CloudSession(user: (await auth.currentUser())!, client: client, sync: sync);
  }

  Widget withCloud(CloudSession? session, Widget home) {
    final holder = CloudSessionHolder()..value = session;
    return MaterialApp(builder: (context, child) => CloudScope(notifier: holder, child: child!), home: home);
  }

  group('sign-in', () {
    /// Clerk's token endpoint answers for alice; everything else is Convex.
    http.Client clerkAndConvex() => MockClient((request) async {
          if (request.url.host == 'clerk.quillfin.test') {
            final token = idTokenFor('user_alice', email: 'alice@example.com', name: 'Alice');
            server.tokens[token] = 'user_alice';
            return http.Response(jsonEncode({'id_token': token, 'refresh_token': 'r1'}), 200);
          }
          // A request can only be sent once, so forward a copy.
          final copy = http.Request(request.method, request.url)
            ..headers.addAll(request.headers)
            ..body = request.body;
          return server.httpClient.send(copy).then(http.Response.fromStream);
        });

    testWidgets('signing in opens the shell, which starts syncing', (tester) async {
      await tester.runAsync(() async {
        final browser = FakeBrowserAuth()..approveWith('code-1');
        final auth = QuillFinAuthService(
          clerk: ClerkOAuth(config: testCloudConfig, browser: browser, httpClient: clerkAndConvex()),
        );
        await tester.pumpWidget(QuillFinApp(authService: auth));
        await waitForLoad(tester);
        expect(find.text('Continue on this device'), findsOneWidget);

        await tester.tap(find.text('Sign in or create an account'));
        await pumpUntil(tester, () => find.byType(RootShell).evaluate().isNotEmpty);
        await settleNavigation(tester);
        await pumpUntil(tester, () => server.calls.contains('query:sync:pull'));
        expect(server.calls.indexOf('mutation:users:ensure'), lessThan(server.calls.indexOf('query:sync:pull')));
        expect((await auth.currentUser())?.displayName, 'Alice');
      });
    }, variant: linux);

    testWidgets('while the browser is open, Cancel goes back to the choices', (tester) async {
      await tester.runAsync(() async {
        final browser = FakeBrowserAuth()..hang();
        final auth = cloudAuth(server, browser: browser);
        await tester.pumpWidget(MaterialApp(home: LoginScreen(authService: auth)));

        await tester.tap(find.text('Sign in or create an account'));
        await pumpUntil(tester, () => find.text('Finish signing in in your browser.').evaluate().isNotEmpty);
        await tester.tap(find.text('Cancel'));
        await pumpUntil(tester, () => find.text('Sign in or create an account').evaluate().isNotEmpty);
        expect(browser.cancels, 1);
        expect(find.textContaining('cancelled'), findsNothing);
        expect(await auth.currentUser(), isNull);
      });
    });

    testWidgets('a failed sign-in shows why and stays on the screen', (tester) async {
      await tester.runAsync(() async {
        final browser = FakeBrowserAuth();
        browser.respond = (url) => browser.redirectUri.replace(queryParameters: {
                'error': 'server_error',
                'error_description': 'Clerk is down',
                'state': url.queryParameters['state'],
              });
        await tester.pumpWidget(MaterialApp(home: LoginScreen(authService: cloudAuth(server, browser: browser))));
        await tester.tap(find.text('Sign in or create an account'));
        await pumpUntil(tester, () => find.textContaining('Clerk is down').evaluate().isNotEmpty);
        expect(find.text('Sign in or create an account'), findsOneWidget);
      });
    });
  });

  group('RootShell signed in', () {
    testWidgets('pushes local data and pulls the account, and pages pushed from the shell see the session', (tester) async {
      await tester.runAsync(() async {
        // Something already in the account from another device.
        server.handlers.clear();
        final auth = await signedInToCloud(server);
        await tester.pumpWidget(QuillFinApp(authService: auth, reminders: ReminderService(delivery: ReminderDelivery.none)));
        await waitForLoad(tester);
        await pumpUntil(tester, () => server.calls.contains('query:sync:pull'));

        final shell = tester.element(find.byType(RootShell));
        final session = CloudScope.maybeOf(shell);
        expect(session?.user.id, 'user_alice');

        // A page pushed onto the app's navigator still finds the session.
        late BuildContext pushed;
        Navigator.of(shell).push(MaterialPageRoute(builder: (context) {
          pushed = context;
          return const SizedBox();
        }));
        await settleNavigation(tester);
        expect(CloudScope.maybeOf(pushed), same(session));

        // Leaving the shell (signing out) clears it.
        Navigator.of(shell).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const Text('gone')), (_) => false);
        await settleNavigation(tester);
        expect(CloudScope.maybeOf(tester.element(find.text('gone'))), isNull);
      });
    }, variant: linux);

    testWidgets('without its own scope above it, the shell provides one', (tester) async {
      await tester.runAsync(() async {
        final auth = await signedInToCloud(server);
        await tester.pumpWidget(MaterialApp(home: RootShell(authService: auth)));
        await waitForLoad(tester);
        await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text('Settings')));
        await waitForLoad(tester);
        expect(find.byType(SyncPanel), findsOneWidget);
      });
    }, variant: linux);
  });

  group('Settings > Sync', () {
    late Database db;
    setUp(() async => db = await openTestDatabase());
    tearDown(() => db.close());

    testWidgets('shows the state, syncs on demand, and explains errors and oversized notes', (tester) async {
      await tester.runAsync(() async {
        final session = await sessionFor(db);
        final folder = await FoldersRepo(db).create('Bio');
        await NotesRepo(db).create(folder.id, 'Huge', 'x' * 300 * 1024);
        await tester.pumpWidget(withCloud(session, Scaffold(body: SyncPanel(session: session))));
        expect(find.text('Not synced yet'), findsOneWidget);

        server.offline = true;
        await tester.tap(find.text('Sync now'));
        await pumpUntil(tester, () => find.byIcon(Icons.sync_problem).evaluate().isNotEmpty);
        expect(find.textContaining("Couldn't reach QuillFin's server"), findsOneWidget);
        expect(find.textContaining('will sync when you\'re back online'), findsOneWidget);
        expect(find.text('1 change waiting to sync.'), findsOneWidget);
        expect(find.text("1 note is over 200 KB and won't sync"), findsOneWidget);

        server.offline = false;
        await tester.tap(find.text('Sync now'));
        await pumpUntil(tester, () => find.text('Last synced just now').evaluate().isNotEmpty);
        expect(find.textContaining('alice@example.com'), findsOneWidget);
        expect(server.rows('user_alice', 'folders'), hasLength(1));
      });
    });

    testWidgets('shows a spinner while syncing and older sync times', (tester) async {
      await tester.runAsync(() async {
        final session = await sessionFor(db);
        await FoldersRepo(db).create('A');
        await FoldersRepo(db).create('B');
        session.sync.value = SyncStatus(
          phase: SyncPhase.syncing,
          lastSyncedAt: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
          pendingChanges: 2,
        );
        await tester.pumpWidget(withCloud(session, Scaffold(body: SyncPanel(session: session))));
        expect(find.text('Syncing...'), findsOneWidget);
        expect(find.text('2 changes waiting to sync.'), findsOneWidget);

        for (final (ago, label) in [
          (const Duration(minutes: 5), '5 min ago'),
          (const Duration(hours: 3), '3 h ago'),
          (const Duration(days: 3), ' 20'), // a date
        ]) {
          session.sync.value = SyncStatus(lastSyncedAt: DateTime.now().toUtc().subtract(ago));
          await tester.pump();
          expect(find.textContaining(label), findsOneWidget, reason: label);
        }
      });
    });

    testWidgets('appear in Settings only when signed in', (tester) async {
      await tester.runAsync(() async {
        final reminders = ReminderService(delivery: ReminderDelivery.none);
        await tester.pumpWidget(withCloud(null, SettingsScreen(db: db, reminders: reminders)));
        await waitForLoad(tester);
        expect(find.text('Sync'), findsNothing);

        final session = await sessionFor(db);
        await tester.pumpWidget(withCloud(session, SettingsScreen(db: db, reminders: reminders)));
        await waitForLoad(tester);
        expect(find.text('Sync'), findsOneWidget);
        expect(find.text('Plan'), findsOneWidget);
      });
    });
  });

  group('Settings > Plan', () {
    late Database db;
    setUp(() async => db = await openTestDatabase());
    tearDown(() => db.close());

    Future<CloudSession> show(WidgetTester tester, {bool isIOS = false}) async {
      final session = await sessionFor(db);
      await tester.pumpWidget(withCloud(session, Scaffold(body: SingleChildScrollView(child: PlanPanel(session: session, isIOS: isIOS)))));
      await waitForLoad(tester);
      return session;
    }

    testWidgets('Free: shows the allowance and opens Stripe Checkout for an upgrade', (tester) async {
      await tester.runAsync(() async {
        server.billing['user_alice'] = FakeConvex.freePlan(used: 20);
        final checkouts = <String>[];
        server.handlers['stripeActions:createCheckoutSession'] = (user, args) {
          checkouts.add(args['interval'] as String);
          return {'url': 'https://checkout.stripe.test/${args['interval']}'};
        };
        await show(tester);

        expect(find.text('QuillFin Free'), findsOneWidget);
        expect(find.text("QuillFin's AI this month: 20 of 20 notes"), findsOneWidget);
        await tester.tap(find.text('Upgrade yearly'));
        await pumpUntil(tester, () => launcher.launched.isNotEmpty);
        await tester.tap(find.text('Upgrade monthly'));
        await pumpUntil(tester, () => launcher.launched.length == 2);
        expect(launcher.launched, ['https://checkout.stripe.test/year', 'https://checkout.stripe.test/month']);
        expect(checkouts, ['year', 'month']);
      });
    });

    testWidgets('Pro: shows the renewal and opens the Billing Portal; reloads on return', (tester) async {
      await tester.runAsync(() async {
        server.billing['user_alice'] = FakeConvex.proPlan();
        server.handlers['stripeActions:createPortalSession'] = (_, _) => {'url': 'https://billing.stripe.test/p'};
        await show(tester);

        expect(find.text('QuillFin Pro'), findsOneWidget);
        expect(find.text('Renews on 28 Oct 2027 (yearly)'), findsOneWidget);
        await tester.tap(find.text('Manage plan'));
        await pumpUntil(tester, () => launcher.launched.isNotEmpty);
        expect(launcher.launched.single, 'https://billing.stripe.test/p');

        server.billing['user_alice'] = FakeConvex.proPlan(cancelAtPeriodEnd: true);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await pumpUntil(tester, () => find.text('Ends on 28 Oct 2027').evaluate().isNotEmpty);
      });
    });

    testWidgets('a checkout that fails or a browser that will not open shows a message', (tester) async {
      await tester.runAsync(() async {
        server.failNext['stripeActions:createCheckoutSession'] = {'code': 'ALREADY_PRO', 'message': "You're already on Pro."};
        server.handlers['stripeActions:createCheckoutSession'] = (_, _) => {'url': 'https://checkout.stripe.test/s'};
        await show(tester);

        await tester.tap(find.text('Upgrade monthly'));
        await pumpUntil(tester, () => find.text("You're already on Pro.").evaluate().isNotEmpty);

        launcher.succeed = false;
        await tester.tap(find.text('Upgrade monthly'));
        await pumpUntil(tester, () => find.text("Couldn't open the browser.").evaluate().isNotEmpty);
      });
    });

    testWidgets('on iOS, plans are managed on the website', (tester) async {
      await tester.runAsync(() async {
        await show(tester, isIOS: true);
        expect(find.text('Upgrade monthly'), findsNothing);
        expect(find.text('Plans are managed on the QuillFin website.'), findsOneWidget);
      });
    });

    testWidgets('a plan that fails to load can be retried', (tester) async {
      await tester.runAsync(() async {
        server.failNext['billing:me'] = {'code': 'SERVER_ERROR', 'message': 'Server is down.'};
        await show(tester);
        expect(find.text('Server is down.'), findsOneWidget);
        await tester.tap(find.text('Retry'));
        await waitForLoad(tester);
        expect(find.text('QuillFin Free'), findsOneWidget);
      });
    });
  });

  group('Account signed in', () {
    late Database db;
    setUp(() async => db = await openTestDatabase());
    tearDown(() => db.close());

    Future<QuillFinAuthService> show(WidgetTester tester) async {
      final session = await sessionFor(db);
      final auth = await signedInToCloud(server);
      await tester.pumpWidget(withCloud(session, AccountScreen(authService: auth)));
      await waitForLoad(tester);
      return auth;
    }

    Future<void> tapSignOut(WidgetTester tester) async {
      await tester.scrollUntilVisible(find.text('Sign out'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Sign out'));
      await settleNavigation(tester);
    }

    testWidgets('shows the account and that the API key is optional', (tester) async {
      await tester.runAsync(() async {
        await show(tester);
        expect(find.text('Alice'), findsOneWidget);
        expect(find.text('alice@example.com'), findsOneWidget);
        expect(find.textContaining("QuillFin's AI is used"), findsOneWidget);
      });
    });

    testWidgets('signing out can keep a copy: changes are pushed first and local data stays', (tester) async {
      await tester.runAsync(() async {
        await FoldersRepo(db).create('Bio');
        final auth = await show(tester);
        await tapSignOut(tester);
        expect(find.text('Sign out?'), findsOneWidget);

        await tester.tap(find.text('Keep a copy'));
        await pumpUntil(tester, () => find.byType(LoginScreen).evaluate().isNotEmpty);
        expect(server.rows('user_alice', 'folders'), hasLength(1));
        expect(await db.query('folders'), hasLength(1));
        expect(await auth.currentUser(), isNull);
      });
    });

    testWidgets('signing out can delete this device\'s copy', (tester) async {
      await tester.runAsync(() async {
        await FoldersRepo(db).create('Bio');
        await show(tester);
        await tapSignOut(tester);
        await tester.tap(find.text('Delete from this device'));
        await pumpUntil(tester, () => find.byType(LoginScreen).evaluate().isNotEmpty);
        expect(server.rows('user_alice', 'folders'), hasLength(1));
        expect(await db.query('folders'), isEmpty);
      });
    });

    testWidgets('cancelling the sign-out dialog stays signed in', (tester) async {
      await tester.runAsync(() async {
        final auth = await show(tester);
        await tapSignOut(tester);
        await tester.tap(find.text('Cancel'));
        await settleNavigation(tester);
        expect(find.byType(AccountScreen), findsOneWidget);
        expect(await auth.currentUser(), isNotNull);
      });
    });

    testWidgets('a device-only user with accounts available is offered sign-in', (tester) async {
      await tester.runAsync(() async {
        final auth = cloudAuth(server);
        await auth.continueOnDevice();
        await tester.pumpWidget(withCloud(null, AccountScreen(authService: auth)));
        await waitForLoad(tester);
        await tester.tap(find.text('Sign in to sync'));
        await settleNavigation(tester);
        expect(find.text('Sign in or create an account'), findsOneWidget);
        expect(await auth.currentUser(), isNull);
      });
    });
  });

  group("generation on QuillFin's AI", () {
    late Database db;
    late int noteId;
    setUp(() async {
      db = await openTestDatabase();
      final folder = await FoldersRepo(db).create('Bio');
      noteId = (await NotesRepo(db).create(folder.id, 'Cells', 'Mitochondria make ATP.')).id;
    });
    tearDown(() => db.close());

    testWidgets('signed in without a key, Generate uses the plan allowance', (tester) async {
      await tester.runAsync(() async {
        server.handlers['ai:generateQuestions'] = (_, args) {
          expect(args['noteText'], 'Mitochondria make ATP.');
          return {
            'questions': [
              {'questionType': 'short_answer', 'prompt': 'What makes ATP?', 'expectedAnswer': 'Mitochondria', 'choices': null, 'correctChoiceIndex': null},
              {'questionType': 'multiple_choice', 'prompt': 'Pick one', 'expectedAnswer': 'B', 'choices': ['A', 'B'], 'correctChoiceIndex': 1},
            ],
            'usage': {'period': '2026-10', 'used': 1, 'limit': 20},
          };
        };
        await tester.pumpWidget(withCloud(await sessionFor(db), NoteEditorScreen(db: db, noteId: noteId)));
        await waitForLoad(tester);
        await tester.tap(find.text('Generate'));
        await pumpUntil(tester, () => find.text('Generated 2 question(s).').evaluate().isNotEmpty);
        final questions = await QuestionsRepo(db).listByNote(noteId);
        expect(questions.map((q) => q.prompt), ['What makes ATP?', 'Pick one']);
      });
    });

    testWidgets('the allowance running out is explained', (tester) async {
      await tester.runAsync(() async {
        server.failNext['ai:generateQuestions'] = {
          'code': 'AI_LIMIT_REACHED',
          'message': "You've used all 20 AI generations this month.",
        };
        await tester.pumpWidget(withCloud(await sessionFor(db), NoteEditorScreen(db: db, noteId: noteId)));
        await waitForLoad(tester);
        await tester.tap(find.text('Generate'));
        await pumpUntil(tester, () => find.textContaining('used all 20 AI generations').evaluate().isNotEmpty);
      });
    });
  });

  test('QuillFinAIProvider sends linked notes, and only when there are some', () async {
    final sent = <Map<String, dynamic>>[];
    server.handlers['ai:generateQuestions'] = (_, args) {
      sent.add(args);
      return {'questions': []};
    };
    final provider = QuillFinAIProvider((await signedInToCloud(server)).convexClient()!);
    await provider.generateQuestions('n', numQuestions: 3, questionFormat: 'multiple_choice', linkedNotesContext: const [
      LinkedNoteContext(noteId: 1, title: 'Cells', excerpt: 'About cells', sharedKeywords: ['atp']),
    ]);
    await provider.generateQuestions('n', linkedNotesContext: const []);
    expect(sent.first, {
      'noteText': 'n',
      'numQuestions': 3,
      'questionFormat': 'multiple_choice',
      'linkedNotes': [
        {'title': 'Cells', 'excerpt': 'About cells', 'sharedKeywords': ['atp']},
      ],
    });
    expect(sent.last.containsKey('linkedNotes'), isFalse);
  });
}
