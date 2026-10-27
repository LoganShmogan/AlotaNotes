import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizapp/core/models.dart';
import 'package:quizapp/core/scheduling.dart';
import 'package:quizapp/screens/quiz/quiz_screen.dart';
import 'package:quizapp/screens/today/today_screen.dart';
import 'package:quizapp/screens/tracker/problem_detail_screen.dart';
import 'package:quizapp/storage/folders_repo.dart';
import 'package:quizapp/storage/notes_repo.dart';
import 'package:quizapp/storage/problems_repo.dart';
import 'package:quizapp/storage/questions_repo.dart';
import 'package:quizapp/storage/reviews_repo.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/test_env.dart';

void main() {
  setUpTestEnv();
  late Database db;
  final now = DateTime.now().toUtc();

  Future<void> show(WidgetTester tester, {Listenable? refresh, VoidCallback? onChanged}) async {
    await tester.pumpWidget(MaterialApp(home: TodayScreen(db: db, refresh: refresh, onChanged: onChanged)));
    await waitForLoad(tester);
  }

  Future<Question> question(String prompt, {DateTime? due}) async {
    final folder = await FoldersRepo(db).create('F');
    final note = await NotesRepo(db).create(folder.id, 'N', '');
    final q = await QuestionsRepo(db).create(note.id, questionTypeShortAnswer, prompt, 'A', now: now);
    if (due != null) await QuestionsRepo(db).updateScheduling(q.id, SrsCard(state: srsStateReview, due: due, stability: 5, difficulty: 5, lastReview: now));
    return q;
  }

  Future<Problem> problem(String title, DateTime due, {List<String> tags = const []}) async {
    final p = await ProblemsRepo(db).create(title, tags: tags, platform: 'LeetCode');
    await ProblemsRepo(db).recordAttempt(p.id,
        solved: true,
        rating: ReviewRating.good,
        after: SrsCard(state: srsStateReview, due: due, stability: 4, difficulty: 5, lastReview: now.subtract(const Duration(days: 4))));
    return p;
  }

  testWidgets('an empty app is all caught up, with no recall figure yet', (tester) async {
    await tester.runAsync(() async {
      db = await openTestDatabase();
      await show(tester);

      expect(find.text('All caught up'), findsOneWidget);
      expect(find.textContaining('Start quiz'), findsNothing);
      expect(find.text('–'), findsOneWidget); // average recall
      expect(find.text('Tmrw'), findsOneWidget);
    });
  });

  testWidgets('counts what is due, what was reviewed today, and forecasts the week', (tester) async {
    await tester.runAsync(() async {
      db = await openTestDatabase();
      final q = await question('Due now'); // brand new: due straight away
      await question('Tomorrow', due: now.add(const Duration(days: 1)));
      await question('Far off', due: now.add(const Duration(days: 30)));
      await problem('Two Sum', now.subtract(const Duration(hours: 1)), tags: ['arrays']);
      await problem('Not yet', now.add(const Duration(days: 2)));
      await ReviewsRepo(db).record(q.id, 'A', true, ReviewRating.good, gradingMethodExactMatch, q.card, askedAt: now);
      await show(tester);

      expect(find.text('2 ready to review'), findsOneWidget);
      expect(find.text('Start quiz (1)'), findsOneWidget);
      // Questions due, problems due: 1 each. Reviewed today: 1 answer + 2 attempts.
      expect(find.text('1'), findsWidgets);
      expect(find.text('3'), findsOneWidget);
      expect(find.textContaining('%'), findsOneWidget);
      expect(find.text('Two Sum'), findsOneWidget);
      expect(find.text('#arrays'), findsOneWidget);
      expect(find.text('Not yet'), findsNothing);
    });
  });

  testWidgets('a due problem with no tags shows its platform', (tester) async {
    await tester.runAsync(() async {
      db = await openTestDatabase();
      await problem('Untagged', now.subtract(const Duration(minutes: 5)));
      await show(tester);
      expect(find.text('LeetCode'), findsOneWidget);
    });
  });

  testWidgets('Start quiz opens the session; coming back refreshes and reports a change', (tester) async {
    await tester.runAsync(() async {
      db = await openTestDatabase();
      await question('Q');
      var changes = 0;
      await show(tester, onChanged: () => changes++);

      await tester.tap(find.text('Start quiz (1)'));
      await settleNavigation(tester);
      expect(find.byType(QuizScreen), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'A');
      await tester.tap(find.text('Submit'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rating-easy')));
      await pumpUntil(tester, () => find.textContaining('Session done').evaluate().isNotEmpty);
      await tester.pageBack();
      await settleNavigation(tester);

      expect(changes, 1);
      expect(find.text('All caught up'), findsOneWidget);
    });
  });

  testWidgets('tapping a due problem opens it', (tester) async {
    await tester.runAsync(() async {
      db = await openTestDatabase();
      await problem('Two Sum', now.subtract(const Duration(hours: 1)));
      await show(tester);

      await tester.scrollUntilVisible(find.text('Two Sum'), 200);
      await tester.tap(find.text('Two Sum'));
      await settleNavigation(tester);
      expect(find.byType(ProblemDetailScreen), findsOneWidget);
    });
  });

  testWidgets('reloads when the refresh signal fires, and pull-to-refresh works', (tester) async {
    await tester.runAsync(() async {
      db = await openTestDatabase();
      final signal = ValueNotifier(0);
      await show(tester, refresh: signal);
      expect(find.text('All caught up'), findsOneWidget);

      await question('New');
      signal.value++;
      await pumpUntil(tester, () => find.text('1 ready to review').evaluate().isNotEmpty);

      await question('Another');
      await tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
      await tester.pump();
      expect(find.text('2 ready to review'), findsOneWidget);

      // Disposing stops listening.
      await tester.pumpWidget(const SizedBox());
      signal.value++;
    });
  });

  test('average recall only counts reviewed cards', () {
    // Guard for the stat's definition: a never-reviewed card has 0 recall
    // and would drag the average down if it were included.
    expect(retrievability(newCard(now), now), 0);
  });
}
