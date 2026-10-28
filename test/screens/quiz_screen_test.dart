import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quillfin/core/models.dart';
import 'package:quillfin/core/scheduling.dart';
import 'package:quillfin/screens/quiz/quiz_screen.dart';
import 'package:quillfin/settings/app_settings.dart';
import 'package:quillfin/storage/folders_repo.dart';
import 'package:quillfin/storage/notes_repo.dart';
import 'package:quillfin/storage/questions_repo.dart';
import 'package:quillfin/storage/reviews_repo.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/test_env.dart';

void main() {
  setUpTestEnv();

  late Database db;
  late QuestionsRepo questions;
  late int noteId;
  final weekAgo = DateTime.now().toUtc().subtract(const Duration(days: 7));

  Future<void> setUpDb() async {
    db = await openTestDatabase();
    questions = QuestionsRepo(db);
    final folder = await FoldersRepo(db).create('Biology');
    noteId = (await NotesRepo(db).create(folder.id, 'Cells', '')).id;
  }

  // New questions are due as soon as they're created.
  Future<Question> due(String prompt, String answer, {List<(String, bool)>? choices, DateTime? createdAt}) =>
      questions.create(
        noteId,
        choices == null ? questionTypeShortAnswer : questionTypeMultipleChoice,
        prompt,
        answer,
        choices: choices,
        now: createdAt ?? weekAgo,
      );

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: QuizScreen(db: db)));
    await waitForLoad(tester);
  }

  Future<void> submit(WidgetTester tester, String resultText) async {
    await tester.tap(find.text('Submit'));
    await pumpUntil(tester, () => find.textContaining(resultText).evaluate().isNotEmpty);
  }

  Future<void> rate(WidgetTester tester, ReviewRating rating) async {
    await tester.ensureVisible(find.byKey(ValueKey('rating-${rating.name}')));
    await tester.tap(find.byKey(ValueKey('rating-${rating.name}')));
    await pumpUntil(tester, () => find.byKey(ValueKey('rating-${rating.name}')).evaluate().isEmpty);
  }

  /// Background colour of a rating button: yellow = highlighted.
  Color? ratingColor(WidgetTester tester, ReviewRating rating) => tester
      .widget<OutlinedButton>(find.byKey(ValueKey('rating-${rating.name}')))
      .style!
      .backgroundColor!
      .resolve({});

  testWidgets('nothing due shows the all-done message', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      await due('Not yet', 'x', createdAt: DateTime.now().toUtc().add(const Duration(days: 1)));
      await show(tester);

      expect(find.text('Nothing due right now. Nice work!'), findsOneWidget);
    });
  });

  testWidgets('a correct answer suggests Good; rating saves the card and the history row', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      final q = await due('Powerhouse of the cell?', 'Mitochondria');
      await show(tester);

      expect(find.text('Powerhouse of the cell?'), findsOneWidget);
      expect(find.text('0 more due after this one'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'mitochondria!');
      await submit(tester, 'Correct!');
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      // Nothing is saved until a rating is picked.
      expect(await ReviewsRepo(db).listForQuestion(q.id), isEmpty);

      expect(ratingColor(tester, ReviewRating.good), isNot(ratingColor(tester, ReviewRating.hard)));
      // Each button says when that rating would bring the question back.
      expect(find.text('10m'), findsOneWidget); // Good on a new card
      expect(find.text('16d'), findsOneWidget); // Easy skips learning

      await rate(tester, ReviewRating.good);
      final updated = await questions.get(q.id);
      expect(updated.card.lastReview, isNotNull);
      expect(updated.card.step, 1);
      final review = (await ReviewsRepo(db).listForQuestion(q.id)).single;
      expect((review.givenAnswer, review.isCorrect, review.rating, review.gradingMethod),
          ('mitochondria!', true, ReviewRating.good, gradingMethodExactMatch));
      expect(review.nextDueAfter, updated.nextDueAt);

      expect(find.text('Session done: 1 reviewed. Nothing else is due right now.'), findsOneWidget);
    });
  });

  testWidgets('the suggested rating can be overridden', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      final q = await due('Powerhouse of the cell?', 'Mitochondria');
      await show(tester);

      await tester.enterText(find.byType(TextField), 'Mitochondria');
      await submit(tester, 'Correct!');
      await rate(tester, ReviewRating.easy);

      final updated = await questions.get(q.id);
      expect(updated.card.state, srsStateReview);
      expect((await ReviewsRepo(db).listForQuestion(q.id)).single.rating, ReviewRating.easy);
    });
  });

  testWidgets('a close-enough answer is graded by keyword match', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      final q = await due('What does the nucleus do?', 'stores the genetic material');
      await show(tester);

      await tester.enterText(find.byType(TextField), 'it stores genetic material');
      await submit(tester, 'Correct!');
      await rate(tester, ReviewRating.good);

      expect((await ReviewsRepo(db).listForQuestion(q.id)).single.gradingMethod, gradingMethodKeywordMatch);
    });
  });

  testWidgets('a wrong answer shows the expected answer and suggests Again, a lapse', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      final q = await due('Powerhouse of the cell?', 'Mitochondria');
      final reviewed = SrsCard(
        state: srsStateReview,
        stability: 20,
        difficulty: 5,
        due: weekAgo,
        lastReview: weekAgo.subtract(const Duration(days: 20)),
      );
      await questions.updateScheduling(q.id, reviewed);
      await show(tester);

      await tester.enterText(find.byType(TextField), 'ribosome');
      await submit(tester, 'Incorrect. Expected: Mitochondria');
      expect(ratingColor(tester, ReviewRating.again), isNot(ratingColor(tester, ReviewRating.good)));
      await rate(tester, ReviewRating.again);

      expect((await questions.get(q.id)).card.state, srsStateRelearning);
      final review = (await ReviewsRepo(db).listForQuestion(q.id)).single;
      expect((review.isCorrect, review.rating), (false, ReviewRating.again));
    });
  });

  testWidgets('the target retention setting changes the intervals offered', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      final q = await due('Q', 'A');
      final card = SrsCard(
        state: srsStateReview,
        stability: 10,
        difficulty: 5,
        due: weekAgo,
        lastReview: weekAgo.subtract(const Duration(days: 10)),
      );
      await questions.updateScheduling(q.id, card);
      await const AppSettingsStore().save(const AppSettings(desiredRetention: maxDesiredRetention));
      await show(tester);

      await tester.enterText(find.byType(TextField), 'A');
      await submit(tester, 'Correct!');
      await rate(tester, ReviewRating.good);

      final strict = buildScheduler(desiredRetention: maxDesiredRetention);
      final answeredAt = (await ReviewsRepo(db).listForQuestion(q.id)).single.askedAt;
      expect((await questions.get(q.id)).nextDueAt, reviewCard(card, ReviewRating.good, answeredAt, scheduler: strict).due);
    });
  });

  testWidgets('multiple choice: picking the correct choice is graded mcq_exact', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      final q = await due('What holds DNA?', 'Nucleus', choices: [('Ribosome', false), ('Nucleus', true)]);
      await show(tester);

      await tester.tap(find.text('Nucleus'));
      await tester.pump();
      await submit(tester, 'Correct!');

      // Choices lock once answered.
      // ignore: deprecated_member_use
      expect(tester.widget<RadioListTile<String>>(find.byType(RadioListTile<String>).first).onChanged, isNull);
      await rate(tester, ReviewRating.good);
      final review = (await ReviewsRepo(db).listForQuestion(q.id)).single;
      expect((review.givenAnswer, review.gradingMethod), ('Nucleus', gradingMethodMcqExact));
    });
  });

  testWidgets('multiple choice: submitting with nothing selected is wrong', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      final q = await due('What holds DNA?', 'Nucleus', choices: [('Ribosome', false), ('Nucleus', true)]);
      await show(tester);

      await submit(tester, 'Incorrect. Expected: Nucleus');
      await rate(tester, ReviewRating.again);
      expect((await ReviewsRepo(db).listForQuestion(q.id)).single.givenAnswer, '');
    });
  });

  testWidgets('multiple choice with no correct choice stored can never be right', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      await due('Broken', 'A', choices: [('A', false), ('B', false)]);
      await show(tester);

      await tester.tap(find.text('A'));
      await tester.pump();
      await submit(tester, 'Incorrect. Expected: A');
    });
  });

  testWidgets('questions come in due order with a running count', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      await due('Second', 'x', createdAt: weekAgo.add(const Duration(hours: 1)));
      await due('First', 'x');
      await show(tester);

      expect(find.text('First'), findsOneWidget);
      expect(find.text('1 more due after this one'), findsOneWidget);

      await submit(tester, 'Incorrect');
      await rate(tester, ReviewRating.again);
      expect(find.text('Second'), findsOneWidget);
      expect(find.text('0 more due after this one'), findsOneWidget);
    });
  });

  testWidgets('pull-to-refresh reloads what is due', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      await show(tester);
      expect(find.text('Nothing due right now. Nice work!'), findsOneWidget);

      await due('Added later', 'x');
      await tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
      await tester.pump();

      expect(find.text('Added later'), findsOneWidget);
    });
  });
}
