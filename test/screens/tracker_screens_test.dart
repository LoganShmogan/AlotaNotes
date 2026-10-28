import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quillfin/core/models.dart';
import 'package:quillfin/core/scheduling.dart';
import 'package:quillfin/screens/tracker/problem_detail_screen.dart';
import 'package:quillfin/screens/tracker/problem_editor_screen.dart';
import 'package:quillfin/screens/tracker/problems_screen.dart';
import 'package:quillfin/storage/problems_repo.dart';
import 'package:quillfin/theme/widgets.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../helpers/fake_url_launcher.dart';
import '../helpers/test_env.dart';

void main() {
  setUpTestEnv();
  late Database db;
  late ProblemsRepo repo;
  final now = DateTime.now().toUtc();

  Future<void> setUpDb() async {
    db = await openTestDatabase();
    repo = ProblemsRepo(db);
  }

  // Forms and detail pages here are taller than the default 800x600 test
  // screen, and ListView only builds what's on screen.
  void tallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Finder field(String label) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);
  Finder hinted(String hint) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == hint);

  Future<Problem> attempted(String title, {required DateTime due, bool solved = true, String difficulty = 'medium', List<String> tags = const []}) async {
    final p = await repo.create(title, difficulty: difficulty, tags: tags, platform: 'LeetCode');
    await repo.recordAttempt(p.id,
        solved: solved,
        rating: solved ? ReviewRating.good : ReviewRating.again,
        after: SrsCard(state: srsStateReview, due: due, stability: 6, difficulty: 5, lastReview: now.subtract(const Duration(days: 2))));
    return p;
  }

  group('ProblemsScreen', () {
    Future<void> show(WidgetTester tester, {Listenable? refresh, VoidCallback? onChanged}) async {
      await tester.pumpWidget(MaterialApp(home: ProblemsScreen(db: db, refresh: refresh, onChanged: onChanged)));
      await waitForLoad(tester);
    }

    testWidgets('empty: explains the tracker and offers to add one', (tester) async {
      tallScreen(tester);
      await tester.runAsync(() async {
        await setUpDb();
        await show(tester);
        expect(find.textContaining('LeetCode-style'), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsNothing);

        await tester.tap(find.text('Add a problem'));
        await settleNavigation(tester);
        expect(find.byType(ProblemEditorScreen), findsOneWidget);
        // Backing out of the editor adds nothing.
        await tester.pageBack();
        await settleNavigation(tester);
        expect(find.byType(ProblemsScreen), findsOneWidget);
        expect(await repo.list(), isEmpty);
      });
    });

    testWidgets('lists problems with status, schedule and recall, filterable and searchable', (tester) async {
      tallScreen(tester);
      await tester.runAsync(() async {
        await setUpDb();
        await repo.create('Untried', difficulty: problemDifficultyHard);
        await attempted('Two Sum', due: now.subtract(const Duration(hours: 1)), difficulty: 'easy', tags: ['arrays']);
        await attempted('LRU Cache', due: now.add(const Duration(days: 3)), solved: false, tags: ['design']);
        await show(tester);

        expect(find.text('3 problems · 1 solved · 1 due'), findsOneWidget);
        expect(find.text('Not attempted'), findsNothing); // combined line below
        expect(find.text('0 attempts · Not attempted'), findsOneWidget);
        expect(find.text('1 attempt · Due now'), findsOneWidget);
        expect(find.textContaining('1 attempt · Next in'), findsOneWidget);
        Finder pill(String label) => find.descendant(of: find.byType(Pill), matching: find.text(label));
        expect(pill('Easy'), findsOneWidget);
        expect(pill('Hard'), findsOneWidget);
        expect(pill('To do'), findsOneWidget);
        expect(find.text('Solved'), findsWidgets);
        expect(find.text('Attempted'), findsWidgets);

        Future<void> chip(String label) async {
          await tester.tap(find.widgetWithText(ChoiceChip, label));
          await tester.pump();
        }

        List<String> titles() => [
              for (final t in ['Untried', 'Two Sum', 'LRU Cache'])
                if (find.text(t).evaluate().isNotEmpty) t,
            ];

        await chip('Due (1)');
        expect(titles(), ['Two Sum']);
        await chip('To do');
        expect(titles(), ['Untried']);
        await chip('Attempted');
        expect(titles(), ['LRU Cache']);
        await chip('Solved');
        expect(titles(), ['Two Sum']);
        await chip('All');
        expect(titles(), hasLength(3));

        await tester.ensureVisible(find.widgetWithText(FilterChip, 'Hard'));
        await tester.tap(find.widgetWithText(FilterChip, 'Hard'));
        await tester.pump();
        expect(titles(), ['Untried']);
        await tester.tap(find.widgetWithText(FilterChip, 'Hard'));
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'DESIGN');
        await tester.pump();
        expect(titles(), ['LRU Cache']);
        await tester.enterText(find.byType(TextField), 'leetcode');
        await tester.pump();
        expect(titles(), hasLength(2)); // platform match; the untried one has none
        await tester.enterText(find.byType(TextField), 'two');
        await tester.pump();
        expect(titles(), ['Two Sum']);
        await tester.enterText(find.byType(TextField), 'zzz');
        await tester.pump();
        expect(find.text('No problems match.'), findsOneWidget);
      });
    });

    testWidgets('the + button adds a problem and opens it; coming back refreshes and reports a change', (tester) async {
      tallScreen(tester);
      await tester.runAsync(() async {
        await setUpDb();
        await repo.create('Existing');
        var changes = 0;
        await show(tester, onChanged: () => changes++);
        await settleNavigation(tester); // FAB entrance animation

        await tester.tap(find.byType(FloatingActionButton));
        await settleNavigation(tester);
        await tester.enterText(field('Problem name'), 'Valid Parentheses');
        await tester.tap(find.byIcon(Icons.save));
        await settleNavigation(tester);
        expect(find.byType(ProblemDetailScreen), findsOneWidget);

        await tester.pageBack();
        await settleNavigation(tester);
        expect(find.text('Valid Parentheses'), findsOneWidget);
        expect(changes, 1);
      });
    });

    testWidgets('reloads on the refresh signal and pull-to-refresh', (tester) async {
      tallScreen(tester);
      await tester.runAsync(() async {
        await setUpDb();
        await repo.create('First');
        final signal = ValueNotifier(0);
        await show(tester, refresh: signal);

        await repo.create('Second');
        signal.value++;
        await pumpUntil(tester, () => find.text('Second').evaluate().isNotEmpty);

        await repo.create('Third');
        await tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
        await tester.pump();
        expect(find.text('Third'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        signal.value++;
      });
    });
  });

  group('ProblemEditorScreen', () {
    testWidgets('a name is required', (tester) async {
      tallScreen(tester);
      await tester.runAsync(() async {
        await setUpDb();
        await tester.pumpWidget(MaterialApp(home: ProblemEditorScreen(db: db)));
        await waitForLoad(tester);

        await tester.tap(find.byIcon(Icons.save));
        await tester.pump();
        expect(find.text('Give the problem a name.'), findsOneWidget);
        expect(await repo.list(), isEmpty);
      });
    });

    testWidgets('creating saves every field and pops with the new id', (tester) async {
      tallScreen(tester);
      await tester.runAsync(() async {
        await setUpDb();
        final result = PopResult<int>();
        await tester.pumpWidget(hostFor(ProblemEditorScreen(db: db), result));
        await tester.tap(find.text('open'));
        await settleNavigation(tester);
        expect(find.text('New problem'), findsOneWidget);

        await tester.enterText(field('Problem name'), '  Two Sum ');
        await tester.tap(find.widgetWithText(ChoiceChip, 'Easy'));
        await tester.enterText(field('Link (optional)'), ' https://leetcode.com/problems/two-sum/ ');
        await tester.enterText(field('Platform (optional)'), 'LeetCode');
        await tester.enterText(field('Tags, comma separated'), 'Arrays, hash map');
        await tester.enterText(hinted('Paste your code or describe the approach'), 'seen = {}');
        await tester.enterText(hinted('Key insight, gotchas, complexity...'), 'O(n)');
        await tester.tap(find.text('Add problem'));
        await settleNavigation(tester);

        final saved = await repo.get(result.value!);
        expect((saved.title, saved.difficulty, saved.url, saved.platform), ('Two Sum', 'easy', 'https://leetcode.com/problems/two-sum/', 'LeetCode'));
        expect(saved.tags, ['arrays', 'hash map']);
        expect((saved.solution, saved.notes), ('seen = {}', 'O(n)'));
      });
    });

    testWidgets('a blank link is stored as none', (tester) async {
      tallScreen(tester);
      await tester.runAsync(() async {
        await setUpDb();
        final result = PopResult<int>();
        await tester.pumpWidget(hostFor(ProblemEditorScreen(db: db), result));
        await tester.tap(find.text('open'));
        await settleNavigation(tester);
        await tester.enterText(field('Problem name'), 'No link');
        await tester.tap(find.byIcon(Icons.save));
        await settleNavigation(tester);
        expect((await repo.get(result.value!)).url, isNull);
      });
    });

    testWidgets('editing pre-fills the problem and saves changes, including clearing the link', (tester) async {
      tallScreen(tester);
      await tester.runAsync(() async {
        await setUpDb();
        final p = await repo.create('Old', difficulty: problemDifficultyHard, url: 'https://x', tags: ['a', 'b'], solution: 's');
        final result = PopResult<int>();
        await tester.pumpWidget(hostFor(ProblemEditorScreen(db: db, problemId: p.id), result));
        await tester.tap(find.text('open'));
        await settleNavigation(tester);

        expect(find.text('Edit problem'), findsOneWidget);
        expect(tester.widget<TextField>(field('Problem name')).controller!.text, 'Old');
        expect(tester.widget<TextField>(field('Tags, comma separated')).controller!.text, 'a, b');
        expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Hard')).selected, isTrue);

        await tester.enterText(field('Problem name'), 'New');
        await tester.enterText(field('Link (optional)'), '');
        await tester.tap(find.byIcon(Icons.save));
        await settleNavigation(tester);

        final saved = await repo.get(p.id);
        expect((result.value, saved.title, saved.url, saved.solution), (p.id, 'New', null, 's'));
      });
    });
  });

  group('ProblemDetailScreen', () {
    late FakeUrlLauncher launcher;

    Future<void> show(WidgetTester tester, int id) async {
      launcher = FakeUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
      await tester.pumpWidget(MaterialApp(home: ProblemDetailScreen(db: db, problemId: id)));
      await waitForLoad(tester);
    }

    testWidgets('a new problem shows its details and no schedule yet', (tester) async {
      tallScreen(tester);
      await tester.runAsync(() async {
        await setUpDb();
        final p = await repo.create('Two Sum',
            difficulty: problemDifficultyEasy, platform: 'LeetCode', tags: ['arrays'], solution: 'seen = {}', notes: 'O(n)');
        await show(tester, p.id);

        expect(find.text('Two Sum'), findsOneWidget);
        expect(find.text('Easy'), findsOneWidget);
        expect(find.text('To do'), findsOneWidget);
        expect(find.text('LeetCode'), findsOneWidget);
        expect(find.text('#arrays'), findsOneWidget);
        expect(find.textContaining('Not attempted yet'), findsOneWidget);
        expect(find.text('seen = {}'), findsOneWidget);
        expect(find.text('O(n)'), findsOneWidget);
        expect(find.text('None yet.'), findsOneWidget);
        expect(find.byIcon(Icons.open_in_new), findsNothing);
      });
    });

    testWidgets('logging a first attempt starts its schedule and lists it', (tester) async {
      tallScreen(tester);
      await tester.runAsync(() async {
        await setUpDb();
        final p = await repo.create('Two Sum');
        await show(tester, p.id);

        await tester.tap(find.text('Log attempt'));
        await settleNavigation(tester);
        // Solved suggests Good; on a new card that's 10 minutes.
        expect(find.text('10m'), findsOneWidget);
        await tester.enterText(field('Time taken (minutes, optional)'), '12');
        await tester.enterText(field('Notes (optional)'), 'Used a hash map');
        await tester.tap(find.text('Save attempt'));
        await settleNavigation(tester);

        expect(find.text('Logged. Next re-solve in 10m.'), findsOneWidget);
        expect(find.text('Solved'), findsWidgets);
        expect(find.text('Next re-solve'), findsOneWidget);
        expect(find.text('in 10m'), findsOneWidget);
        final attempt = (await repo.listAttempts(p.id)).single;
        expect((attempt.solved, attempt.rating, attempt.durationMinutes, attempt.notes), (true, ReviewRating.good, 12, 'Used a hash map'));

        expect(find.text('Attempts (1)'), findsOneWidget);
        expect(find.textContaining('12 min · Good'), findsOneWidget);
      });
    });

    testWidgets('not solved suggests Again; the rating and bad minutes can be changed', (tester) async {
      tallScreen(tester);
      await tester.runAsync(() async {
        await setUpDb();
        final p = await attempted('LRU Cache', due: now.subtract(const Duration(days: 1)));
        await show(tester, p.id);
        expect(find.text('Due now'), findsOneWidget);
        expect(find.text('Recall now'), findsOneWidget);
        expect(find.text('6d'), findsOneWidget); // memory = stability

        await tester.tap(find.text('Log attempt'));
        await settleNavigation(tester);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Not solved'));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('rating-hard')));
        await tester.pump();
        await tester.tap(find.widgetWithText(ChoiceChip, 'Solved'));
        await tester.pump();
        await tester.tap(find.widgetWithText(ChoiceChip, 'Not solved'));
        await tester.pump();
        await tester.enterText(field('Time taken (minutes, optional)'), '-3');
        await tester.tap(find.text('Save attempt'));
        await settleNavigation(tester);

        final attempt = (await repo.listAttempts(p.id)).first;
        expect((attempt.solved, attempt.rating, attempt.durationMinutes), (false, ReviewRating.hard, null));
        expect((await repo.get(p.id)).status, ProblemStatus.attempted);
        expect(find.text('Not solved'), findsOneWidget);
      });
    });

    testWidgets('dismissing the attempt sheet logs nothing', (tester) async {
      tallScreen(tester);
      await tester.runAsync(() async {
        await setUpDb();
        final p = await repo.create('P');
        await show(tester, p.id);

        await tester.tap(find.text('Log attempt'));
        await settleNavigation(tester);
        await tester.tapAt(const Offset(10, 10)); // the barrier
        await settleNavigation(tester);
        expect(await repo.listAttempts(p.id), isEmpty);
      });
    });

    testWidgets('the attempt timer counts up and pre-fills the minutes', (tester) async {
      tallScreen(tester);
      await tester.runAsync(() async {
        await setUpDb();
        final p = await repo.create('P');
        await show(tester, p.id);

        await tester.tap(find.text('Timer'));
        await tester.pump();
        expect(find.text('00:00'), findsOneWidget);
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        await tester.pump();
        expect(find.text('00:01'), findsOneWidget);

        // Stopping clears it; starting again and logging pre-fills 0 minutes.
        await tester.tap(find.text('00:01'));
        await tester.pump();
        expect(find.text('Timer'), findsOneWidget);
        await tester.tap(find.text('Timer'));
        await tester.pump();
        await tester.tap(find.text('Log attempt'));
        await settleNavigation(tester);
        expect(tester.widget<TextField>(field('Time taken (minutes, optional)')).controller!.text, '0');
        await tester.tap(find.text('Save attempt'));
        await settleNavigation(tester);
        expect(find.text('Timer'), findsOneWidget);
      });
    });

    testWidgets('the link opens in the browser, with a message if it cannot', (tester) async {
      tallScreen(tester);
      await tester.runAsync(() async {
        await setUpDb();
        final p = await repo.create('Two Sum', url: 'https://leetcode.com/problems/two-sum/');
        await show(tester, p.id);

        await tester.tap(find.byIcon(Icons.open_in_new));
        await tester.pump();
        expect(launcher.launched, ['https://leetcode.com/problems/two-sum/']);

        launcher.succeed = false;
        await tester.tap(find.byIcon(Icons.open_in_new));
        await pumpUntil(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
        expect(find.text("Couldn't open https://leetcode.com/problems/two-sum/"), findsOneWidget);
      });
    });

    testWidgets('edit opens the editor and shows the changes on return', (tester) async {
      tallScreen(tester);
      await tester.runAsync(() async {
        await setUpDb();
        final p = await repo.create('Old');
        await show(tester, p.id);

        await tester.tap(find.byTooltip('Edit'));
        await settleNavigation(tester);
        await tester.enterText(field('Problem name'), 'Renamed');
        await tester.tap(find.byIcon(Icons.save));
        await settleNavigation(tester);
        expect(find.text('Renamed'), findsOneWidget);
      });
    });

    testWidgets('delete asks first; confirming removes it and leaves', (tester) async {
      tallScreen(tester);
      await tester.runAsync(() async {
        await setUpDb();
        final p = await repo.create('Doomed');
        final result = PopResult<void>();
        launcher = FakeUrlLauncher();
        await tester.pumpWidget(hostFor(ProblemDetailScreen(db: db, problemId: p.id), result));
        await tester.tap(find.text('open'));
        await settleNavigation(tester);

        await tester.tap(find.byTooltip('Delete'));
        await settleNavigation(tester);
        await tester.tap(find.text('Cancel'));
        await settleNavigation(tester);
        expect(await repo.list(), hasLength(1));

        await tester.tap(find.byTooltip('Delete'));
        await settleNavigation(tester);
        await tester.tap(find.text('Delete'));
        await settleNavigation(tester);
        expect(result.popped, isTrue);
        expect(await repo.list(), isEmpty);
      });
    });
  });

  test('a scheduler with the default retention is what the screens fall back to', () {
    expect(buildScheduler().desiredRetention, defaultDesiredRetention);
  });
}
