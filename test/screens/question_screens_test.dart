// NoteQuestionsScreen (a note's question list) and QuestionEditorScreen
// (editing one question), which navigate into each other.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizapp/core/models.dart';
import 'package:quizapp/screens/notes/note_editor_screen.dart';
import 'package:quizapp/screens/notes/note_questions_screen.dart';
import 'package:quizapp/screens/quiz/question_editor_screen.dart';
import 'package:quizapp/storage/folders_repo.dart';
import 'package:quizapp/storage/notes_repo.dart';
import 'package:quizapp/storage/questions_repo.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/test_env.dart';

void main() {
  setUpTestEnv();

  late Database db;
  late QuestionsRepo questions;
  late int noteId;

  Future<void> setUpDb() async {
    db = await openTestDatabase();
    questions = QuestionsRepo(db);
    final folder = await FoldersRepo(db).create('Biology');
    noteId = (await NotesRepo(db).create(folder.id, 'Cells', 'Cells have a nucleus.')).id;
  }

  Future<Question> multipleChoice() => questions.create(
        noteId,
        questionTypeMultipleChoice,
        'What holds DNA?',
        'Nucleus',
        choices: [('Nucleus', true), ('Ribosome', false), ('Membrane', false)],
      );

  group('NoteQuestionsScreen', () {
    testWidgets('empty state', (tester) async {
      await tester.runAsync(() async {
        await setUpDb();
        await tester.pumpWidget(MaterialApp(home: NoteQuestionsScreen(db: db, noteId: noteId)));
        await waitForLoad(tester);

        expect(find.text('No questions generated yet.'), findsOneWidget);
      });
    });

    testWidgets('lists each question with its type, edited flag and active state', (tester) async {
      await tester.runAsync(() async {
        await setUpDb();
        await questions.create(noteId, questionTypeShortAnswer, 'What is a cell?', 'Unit of life');
        final mcq = await multipleChoice();
        await questions.updateContent(mcq.id, prompt: mcq.prompt, expectedAnswer: 'Nucleus');
        final off = await questions.create(noteId, questionTypeShortAnswer, 'Retired', 'x');
        await db.update('questions', {'active': 0}, where: 'id = ?', whereArgs: [off.id]);

        await tester.pumpWidget(MaterialApp(home: NoteQuestionsScreen(db: db, noteId: noteId)));
        await waitForLoad(tester);

        expect(find.text('What is a cell?'), findsOneWidget);
        expect(find.text('Short answer'), findsNWidgets(2));
        expect(find.text('Multiple choice · edited'), findsOneWidget);
        expect(find.byIcon(Icons.quiz_outlined), findsNWidgets(2));
        expect(find.byIcon(Icons.block), findsOneWidget);
      });
    });

    testWidgets('tapping a question opens the editor; edits show on return', (tester) async {
      await tester.runAsync(() async {
        await setUpDb();
        await questions.create(noteId, questionTypeShortAnswer, 'Old prompt', 'Answer');
        await tester.pumpWidget(MaterialApp(home: NoteQuestionsScreen(db: db, noteId: noteId)));
        await waitForLoad(tester);

        await tester.tap(find.text('Old prompt'));
        await settleNavigation(tester);
        expect(find.byType(QuestionEditorScreen), findsOneWidget);

        await tester.enterText(find.widgetWithText(TextField, 'Old prompt'), 'New prompt');
        await tester.tap(find.byIcon(Icons.save));
        await pumpUntil(tester, () => find.text('Saved.').evaluate().isNotEmpty);
        await tester.pageBack();
        await settleNavigation(tester);

        expect(find.text('New prompt'), findsOneWidget);
        expect(find.text('Short answer · edited'), findsOneWidget);
      });
    });
  });

  group('QuestionEditorScreen', () {
    Future<void> show(WidgetTester tester, int questionId) async {
      await tester.pumpWidget(MaterialApp(home: QuestionEditorScreen(db: db, questionId: questionId)));
      await waitForLoad(tester);
    }

    testWidgets('short answer: shows the source note and saves trimmed edits', (tester) async {
      await tester.runAsync(() async {
        await setUpDb();
        final q = await questions.create(noteId, questionTypeShortAnswer, 'What is a cell?', 'Unit of life');
        await show(tester, q.id);

        expect(find.text('Generated from'), findsOneWidget);
        expect(find.text('Cells'), findsOneWidget);
        expect(find.text('Manually edited'), findsNothing);
        expect(find.byType(Radio<int>), findsNothing);

        await tester.enterText(find.widgetWithText(TextField, 'What is a cell?'), ' Define a cell. ');
        await tester.enterText(find.widgetWithText(TextField, 'Unit of life'), ' Smallest unit of life ');
        await tester.tap(find.byIcon(Icons.save));
        await pumpUntil(tester, () => find.text('Saved.').evaluate().isNotEmpty);

        final saved = await questions.get(q.id);
        expect(saved.prompt, 'Define a cell.');
        expect(saved.expectedAnswer, 'Smallest unit of life');
        expect(saved.isManuallyEdited, isTrue);
      });
    });

    testWidgets('shows the "Manually edited" marker for an edited question', (tester) async {
      await tester.runAsync(() async {
        await setUpDb();
        final q = await questions.create(noteId, questionTypeShortAnswer, 'P', 'A');
        await questions.updateContent(q.id, prompt: 'P', expectedAnswer: 'A');
        await show(tester, q.id);

        expect(find.text('Manually edited'), findsOneWidget);
      });
    });

    testWidgets('multiple choice: changing the correct choice also updates the expected answer', (tester) async {
      await tester.runAsync(() async {
        await setUpDb();
        final q = await multipleChoice();
        await show(tester, q.id);

        expect(find.text('CHOICES (SELECT THE CORRECT ONE)'), findsOneWidget);
        expect(find.byType(Radio<int>), findsNWidgets(3));

        await tester.enterText(find.widgetWithText(TextField, 'Ribosome'), ' Chromosome ');
        await tester.tap(find.byType(Radio<int>).at(1));
        await tester.pump();
        await tester.tap(find.byIcon(Icons.save));
        await pumpUntil(tester, () => find.text('Saved.').evaluate().isNotEmpty);

        final saved = await questions.get(q.id);
        expect(
          saved.choices.map((c) => (c.choiceText, c.isCorrect)),
          [('Nucleus', false), ('Chromosome', true), ('Membrane', false)],
        );
        expect(saved.expectedAnswer, 'Chromosome');
      });
    });

    testWidgets('tapping "Generated from" opens the source note', (tester) async {
      await tester.runAsync(() async {
        await setUpDb();
        final q = await questions.create(noteId, questionTypeShortAnswer, 'P', 'A');
        await show(tester, q.id);

        await tester.tap(find.text('Generated from'));
        await settleNavigation(tester);

        expect(find.byType(NoteEditorScreen), findsOneWidget);
        expect(find.text('Cells have a nucleus.'), findsOneWidget);
      });
    });
  });
}
