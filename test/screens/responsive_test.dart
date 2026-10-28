// Layouts that depend on the window size (Docs/quillfin_plan.md §5): the
// shell's bar / rail / sidebar, list-detail panes, wide sign-in and
// settings, the quiz's pinned rating bar, and keyboard shortcuts.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quillfin/core/models.dart';
import 'package:quillfin/screens/login/login_screen.dart';
import 'package:quillfin/screens/notes/folder_detail_screen.dart';
import 'package:quillfin/screens/notes/note_editor_screen.dart';
import 'package:quillfin/screens/quiz/quiz_screen.dart';
import 'package:quillfin/screens/root_shell.dart';
import 'package:quillfin/screens/settings/settings_screen.dart';
import 'package:quillfin/screens/today/today_screen.dart';
import 'package:quillfin/screens/tracker/problem_detail_screen.dart';
import 'package:quillfin/screens/tracker/problems_screen.dart';
import 'package:quillfin/services/reminder_service.dart';
import 'package:quillfin/settings/app_settings.dart';
import 'package:quillfin/settings/theme_controller.dart';
import 'package:quillfin/storage/folders_repo.dart';
import 'package:quillfin/storage/notes_repo.dart';
import 'package:quillfin/storage/problems_repo.dart';
import 'package:quillfin/storage/questions_repo.dart';
import 'package:quillfin/storage/reviews_repo.dart';
import 'package:quillfin/theme/widgets.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/fake_auth.dart';
import '../helpers/test_env.dart';

const phone = Size(400, 820);
const phoneLandscape = Size(820, 400);
const tablet = Size(1000, 800);
const desktop = Size(1400, 900);

void setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}


final linux = TargetPlatformVariant.only(TargetPlatform.linux);

void main() {
  setUpTestEnv();
  late Database db;

  group('RootShell navigation', () {
    Future<void> show(WidgetTester tester, Size size) async {
      setSize(tester, size);
      await tester.pumpWidget(MaterialApp(home: RootShell(authService: await signedInLocally())));
      await waitForLoad(tester);
    }

    testWidgets('phone: bottom navigation bar', (tester) async {
      await tester.runAsync(() async {
        await show(tester, phone);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(NavigationRail), findsNothing);
      });
    }, variant: linux);

    testWidgets('phone in landscape: a compact rail instead', (tester) async {
      await tester.runAsync(() async {
        await show(tester, const Size(560, 400));
        expect(find.byType(NavigationBar), findsNothing);
        expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended, isFalse);
        expect(find.byType(QuillFinMark), findsOneWidget);
      });
    }, variant: linux);

    testWidgets('desktop: a labelled sidebar with the lockup; shortcuts switch sections', (tester) async {
      await tester.runAsync(() async {
        await show(tester, desktop);
        expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended, isTrue);
        expect(find.byType(BrandLockup), findsOneWidget);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
        await waitForLoad(tester);
        expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex, 2);
        expect(find.byType(ProblemsScreen), findsOneWidget);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
        await tester.pump();
        expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex, 4);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyEvent(LogicalKeyboardKey.slash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
        await settleNavigation(tester);
        expect(find.text('Keyboard shortcuts'), findsOneWidget);
        expect(find.text('Switch section'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await settleNavigation(tester);

        await tester.tap(find.byTooltip('Keyboard shortcuts (Ctrl+/)'));
        await settleNavigation(tester);
        expect(find.text('Keyboard shortcuts'), findsOneWidget);
      });
    }, variant: linux);
  });

  testWidgets('sign-in on a wide window splits brand panel and form', (tester) async {
    setSize(tester, desktop);
    await tester.pumpWidget(MaterialApp(home: LoginScreen(authService: localAuth())));
    expect(find.textContaining('right before you would forget it'), findsOneWidget);
    expect(find.text('Welcome to QuillFin'), findsOneWidget);
    expect(find.byType(BrandLockup), findsOneWidget); // on the brand panel only
  });

  group('Today', () {
    Future<void> show(WidgetTester tester, Size size) async {
      setSize(tester, size);
      await tester.pumpWidget(MaterialApp(home: TodayScreen(db: db)));
      await waitForLoad(tester);
    }

    testWidgets('wide: problems column beside the main column', (tester) async {
      await tester.runAsync(() async {
        db = await openTestDatabase();
        await show(tester, tablet);
        expect(find.text('None due. Nice.'), findsOneWidget);

        final p = await ProblemsRepo(db).create('Two Sum');
        await ProblemsRepo(db).recordAttempt(p.id,
            solved: true, rating: ReviewRating.good, after: SrsCard(state: srsStateReview, due: DateTime.utc(2020)));
        await tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
        await tester.pump();
        expect(tester.getTopLeft(find.text('Two Sum')).dx, greaterThan(tester.getTopLeft(find.text('Questions due')).dx));
      });
    });

    testWidgets('medium: the four stats in one row; compact: two rows', (tester) async {
      await tester.runAsync(() async {
        db = await openTestDatabase();
        await show(tester, const Size(700, 900));
        final y = tester.getTopLeft(find.text('Questions due')).dy;
        expect(tester.getTopLeft(find.text('Average recall')).dy, y);

        await show(tester, phone);
        expect(tester.getTopLeft(find.text('Average recall')).dy, greaterThan(tester.getTopLeft(find.text('Questions due')).dy));
      });
    });
  });

  group('Quiz', () {
    Future<void> seed() async {
      db = await openTestDatabase();
      final folder = await FoldersRepo(db).create('F');
      final note = await NotesRepo(db).create(folder.id, 'N', '');
      await QuestionsRepo(db).create(note.id, questionTypeShortAnswer, 'Q?', 'A', now: DateTime.utc(2020));
    }

    testWidgets('phone: ratings pinned to the bottom; Enter submits and 1-4 rate', (tester) async {
      await tester.runAsync(() async {
        await seed();
        setSize(tester, phone);
        await tester.pumpWidget(MaterialApp(home: QuizScreen(db: db)));
        await waitForLoad(tester);

        await tester.enterText(find.byType(TextField), 'A');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(find.text('Correct!'), findsOneWidget);
        final bar = tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar;
        expect(bar, isNotNull);
        expect(find.descendant(of: find.byWidget(bar!), matching: find.byKey(const ValueKey('rating-good'))), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
        await pumpUntil(tester, () => find.textContaining('Session done').evaluate().isNotEmpty);
        final review = (await ReviewsRepo(db).listForQuestion(1)).single;
        expect(review.rating, ReviewRating.easy);
      });
    });

    testWidgets('wide: ratings sit under the answer', (tester) async {
      await tester.runAsync(() async {
        await seed();
        setSize(tester, desktop);
        await tester.pumpWidget(MaterialApp(home: QuizScreen(db: db)));
        await waitForLoad(tester);
        await tester.enterText(find.byType(TextField), 'nope');
        await tester.tap(find.text('Submit'));
        await tester.pump();
        expect(tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar, isNull);
        expect(find.byKey(const ValueKey('rating-again')), findsOneWidget);
      });
    });
  });

  group('Tracker list-detail', () {
    Future<void> show(WidgetTester tester, Size size, {VoidCallback? onChanged}) async {
      setSize(tester, size);
      await tester.pumpWidget(MaterialApp(home: ProblemsScreen(db: db, onChanged: onChanged)));
      await waitForLoad(tester);
    }

    testWidgets('tablet: the selected problem opens beside the list; deleting it clears the pane', (tester) async {
      await tester.runAsync(() async {
        db = await openTestDatabase();
        await ProblemsRepo(db).create('Two Sum');
        await ProblemsRepo(db).create('LRU Cache');
        var changes = 0;
        await show(tester, tablet, onChanged: () => changes++);
        expect(find.text('Select a problem to see it here.'), findsOneWidget);

        await tester.tap(find.text('Two Sum'));
        await settleNavigation(tester);
        expect(find.byType(ProblemDetailScreen), findsOneWidget);
        expect(find.byType(ProblemsScreen), findsOneWidget); // still on screen
        expect(find.byTooltip('Back'), findsNothing);
        expect(changes, 1);

        // Logging an attempt uses a dialog here, not a bottom sheet.
        await tester.tap(find.text('Log attempt'));
        await settleNavigation(tester);
        expect(find.byType(Dialog), findsOneWidget);
        await tester.tap(find.text('Save attempt'));
        await settleNavigation(tester);
        expect(changes, 2);
        expect(find.text('1 attempt · Next in 10m'), findsOneWidget); // the list refreshed too

        await tester.tap(find.byTooltip('Delete'));
        await settleNavigation(tester);
        await tester.tap(find.text('Delete'));
        await settleNavigation(tester);
        expect(find.byType(ProblemDetailScreen), findsNothing);
        expect(find.text('Two Sum'), findsNothing);
        expect(changes, 3);
      });
    });

    testWidgets('phone: logging an attempt uses a bottom sheet', (tester) async {
      await tester.runAsync(() async {
        db = await openTestDatabase();
        final p = await ProblemsRepo(db).create('Two Sum');
        setSize(tester, phone);
        await tester.pumpWidget(MaterialApp(home: ProblemDetailScreen(db: db, problemId: p.id)));
        await waitForLoad(tester);
        await tester.tap(find.text('Log attempt'));
        await settleNavigation(tester);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
      });
    });

    testWidgets('tablet: adding a problem selects it in place', (tester) async {
      await tester.runAsync(() async {
        db = await openTestDatabase();
        await ProblemsRepo(db).create('Existing');
        await show(tester, tablet);
        await settleNavigation(tester);
        await tester.tap(find.byType(FloatingActionButton));
        await settleNavigation(tester);
        await tester.enterText(find.byType(TextField).first, 'New one');
        await tester.tap(find.byIcon(Icons.save));
        await settleNavigation(tester);
        expect(find.byType(ProblemDetailScreen), findsOneWidget);
        expect(find.text('New one'), findsWidgets);
      });
    });

    testWidgets('a selected problem deleted elsewhere drops out of the pane', (tester) async {
      await tester.runAsync(() async {
        db = await openTestDatabase();
        final p = await ProblemsRepo(db).create('Gone soon');
        final signal = ValueNotifier(0);
        setSize(tester, tablet);
        await tester.pumpWidget(MaterialApp(home: ProblemsScreen(db: db, refresh: signal)));
        await waitForLoad(tester);
        await tester.tap(find.text('Gone soon'));
        await settleNavigation(tester);

        await ProblemsRepo(db).delete(p.id);
        signal.value++;
        await pumpUntil(tester, () => find.byType(ProblemDetailScreen).evaluate().isEmpty);
      });
    });

    testWidgets('desktop: table view sorts by any column and opens rows as pages', (tester) async {
      await tester.runAsync(() async {
        db = await openTestDatabase();
        final repo = ProblemsRepo(db);
        await repo.create('Beta', difficulty: problemDifficultyHard);
        final alpha = await repo.create('Alpha', difficulty: problemDifficultyEasy);
        await repo.recordAttempt(alpha.id,
            solved: true,
            rating: ReviewRating.good,
            after: SrsCard(state: srsStateReview, due: DateTime.utc(2099), stability: 5, difficulty: 5, lastReview: DateTime.now().toUtc()));
        await show(tester, desktop);

        await tester.tap(find.byTooltip('Table view'));
        await tester.pump();
        expect(find.byType(DataTable), findsOneWidget);
        List<String> order() => [
              for (final t in ['Alpha', 'Beta'])
                if (find.text(t).evaluate().isNotEmpty) t,
            ]..sort((a, b) => tester.getTopLeft(find.text(a)).dy.compareTo(tester.getTopLeft(find.text(b)).dy));
        expect(order(), ['Alpha', 'Beta']);

        for (final (column, first) in [
          ('Problem', 'Beta'), // same column again: descending
          ('Difficulty', 'Alpha'),
          ('Status', 'Beta'),
          ('Next re-solve', 'Alpha'),
          ('Recall', 'Beta'),
          ('Attempts', 'Beta'),
        ]) {
          await tester.tap(find.text(column));
          await tester.pump();
          expect(order().first, first, reason: column);
        }
        expect(find.text('–'), findsOneWidget); // Beta has no recall yet

        await tester.tap(find.text('Alpha'));
        await settleNavigation(tester);
        expect(find.byType(ProblemDetailScreen), findsOneWidget);
        await tester.pageBack();
        await settleNavigation(tester);

        await tester.tap(find.byTooltip('Card view'));
        await tester.pump();
        expect(find.byType(DataTable), findsNothing);
      });
    });
  });

  group('Notes list-detail', () {
    testWidgets('tablet: notes open beside the list, new notes too, and Ctrl+S saves', (tester) async {
      await tester.runAsync(() async {
        db = await openTestDatabase();
        final folder = await FoldersRepo(db).create('Biology');
        await NotesRepo(db).create(folder.id, 'Cells', 'body');
        setSize(tester, tablet);
        await tester.pumpWidget(MaterialApp(home: FolderDetailScreen(db: db, folder: folder)));
        await waitForLoad(tester);
        expect(find.text('Select a note to edit it here.'), findsOneWidget);

        await tester.tap(find.text('Cells'));
        await settleNavigation(tester);
        expect(find.byType(NoteEditorScreen), findsOneWidget);
        expect(find.byTooltip('Back'), findsNothing);

        await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Cell biology');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
        await pumpUntil(tester, () => find.text('Saved.').evaluate().isNotEmpty);
        await pumpUntil(tester, () => find.text('Cell biology').evaluate().length > 1); // list refreshed

        await tester.tap(find.byIcon(Icons.add));
        await settleNavigation(tester);
        await tester.tap(find.text('New note'));
        await settleNavigation(tester);
        expect(find.text('Untitled note'), findsWidgets);
        expect(find.byType(NoteEditorScreen), findsOneWidget);
      });
    });
  });

  group('Settings sections', () {
    testWidgets('desktop: section list beside the chosen section; Appearance switches theme', (tester) async {
      await tester.runAsync(() async {
        db = await openTestDatabase();
        setSize(tester, desktop);
        final theme = ThemeController();
        await tester.pumpWidget(MaterialApp(
          home: ThemeControllerScope(
            controller: theme,
            child: SettingsScreen(db: db, reminders: ReminderService(delivery: ReminderDelivery.none)),
          ),
        ));
        await waitForLoad(tester);

        expect(find.text('Appearance'), findsNWidgets(2)); // list entry + heading
        await tester.tap(find.text('Dark'));
        await pumpUntil(tester, () => theme.value == ThemeMode.dark);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect((await const AppSettingsStore().load()).themeMode, themeModeDark);

        await tester.tap(find.text('Your data'));
        await tester.pump();
        expect(find.text('Export all data'), findsOneWidget);
        expect(find.text('Target recall: 90%'), findsNothing);
      });
    });
  });
}
