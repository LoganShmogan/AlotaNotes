import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizapp/core/models.dart';
import 'package:quizapp/screens/quiz/quiz_screen.dart';
import 'package:quizapp/storage/folders_repo.dart';
import 'package:quizapp/storage/notes_repo.dart';
import 'package:quizapp/storage/questions_repo.dart';
import 'package:quizapp/storage/reviews_repo.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/test_env.dart';

void main() {
  setUpTestEnv();

  late Database db;
  late QuestionsRepo questions;
  late int noteId;
  // Created a week ago, so first due six days ago: due now.
  final weekAgo = DateTime.now().toUtc().subtract(const Duration(days: 7));

  Future<void> setUpDb() async {
    db = await openTestDatabase();
    questions = QuestionsRepo(db);
    final folder = await FoldersRepo(db).create('Biology');
    noteId = (await NotesRepo(db).create(folder.id, 'Cells', '')).id;
  }

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

  testWidgets('nothing due shows the all-done message', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      // Created now, so not due until tomorrow.
      await due('Not yet', 'x', createdAt: DateTime.now().toUtc());
      await show(tester);

      expect(find.text('Nothing due right now. Nice work!'), findsOneWidget);
    });
  });

  testWidgets('an exact short answer is correct, advances the schedule, and is logged', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      final q = await due('Powerhouse of the cell?', 'Mitochondria');
      await show(tester);

      expect(find.text('Powerhouse of the cell?'), findsOneWidget);
      expect(find.text('0 more due after this one'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'mitochondria!');
      await submit(tester, 'Correct!');
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

      final updated = await questions.get(q.id);
      expect(updated.intervalIndex, 1);
      expect(updated.lastAskedAt, isNotNull);
      final review = (await ReviewsRepo(db).listForQuestion(q.id)).single;
      expect((review.givenAnswer, review.isCorrect, review.gradingMethod), ('mitochondria!', true, gradingMethodExactMatch));
      expect((review.intervalIndexBefore, review.intervalIndexAfter), (0, 1));

      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('Nothing due right now. Nice work!'), findsOneWidget);
    });
  });

  testWidgets('a close-enough answer is graded by keyword match', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      final q = await due('What does the nucleus do?', 'stores the genetic material');
      await show(tester);

      await tester.enterText(find.byType(TextField), 'it stores genetic material');
      await submit(tester, 'Correct!');

      expect((await ReviewsRepo(db).listForQuestion(q.id)).single.gradingMethod, gradingMethodKeywordMatch);
    });
  });

  testWidgets('a wrong answer shows the expected answer and resets the schedule', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      final q = await due('Powerhouse of the cell?', 'Mitochondria');
      await questions.updateScheduling(q.id, intervalIndex: 4, lastAskedAt: weekAgo, nextDueAt: weekAgo);
      await show(tester);

      await tester.enterText(find.byType(TextField), 'ribosome');
      await submit(tester, 'Incorrect. Expected: Mitochondria');

      expect((await questions.get(q.id)).intervalIndex, 0);
      final review = (await ReviewsRepo(db).listForQuestion(q.id)).single;
      expect((review.isCorrect, review.intervalIndexBefore, review.intervalIndexAfter), (false, 4, 0));
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
      await tester.tap(find.text('Next'));
      await tester.pump();
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
