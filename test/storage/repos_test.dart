// Real in-memory sqlite via sqflite_common_ffi for every case here --
// higher fidelity than a hand-written fake (catches real SQL/constraint
// bugs), same reasoning as the Python desktop app's repo tests.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:quizapp/core/models.dart';
import 'package:quizapp/storage/db.dart';
import 'package:quizapp/storage/folders_repo.dart';
import 'package:quizapp/storage/notes_repo.dart';
import 'package:quizapp/storage/questions_repo.dart';
import 'package:quizapp/storage/reviews_repo.dart';

Future<Database> _openTestDatabase() async {
  final db = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await db.execute('PRAGMA foreign_keys = ON');
  for (final statement in schemaStatements) {
    await db.execute(statement);
  }
  return db;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('NotesRepo', () {
    test('listByFolder orders by sort_order first, falling back to title', () async {
      final db = await _openTestDatabase();
      final folder = await FoldersRepo(db).create('Physics');
      final notes = NotesRepo(db);

      await notes.create(folder.id, 'Zebra', '', sortOrder: 1);
      await notes.create(folder.id, 'Apple', '', sortOrder: 0);
      await notes.create(folder.id, 'Mango', '', sortOrder: 0); // ties with Apple on sort_order

      final result = await notes.listByFolder(folder.id);
      expect(result.map((n) => n.title), ['Apple', 'Mango', 'Zebra']);
    });

    test('update can change sort_order without touching title/body', () async {
      final db = await _openTestDatabase();
      final folder = await FoldersRepo(db).create('Physics');
      final notes = NotesRepo(db);
      final note = await notes.create(folder.id, 'Note', 'body', sortOrder: 5);

      final updated = await notes.update(note.id, sortOrder: 2);
      expect(updated.sortOrder, 2);
      expect(updated.title, 'Note');
      expect(updated.body, 'body');
    });
  });

  group('QuestionsRepo.updateContent', () {
    test('edits prompt/expected answer and marks isManuallyEdited', () async {
      final db = await _openTestDatabase();
      final folder = await FoldersRepo(db).create('Physics');
      final note = await NotesRepo(db).create(folder.id, 'Note', 'body');
      final questions = QuestionsRepo(db);
      final question = await questions.create(note.id, questionTypeShortAnswer, 'Old prompt', 'old answer');

      final updated = await questions.updateContent(
        question.id,
        prompt: 'New prompt',
        expectedAnswer: 'new answer',
      );

      expect(updated.prompt, 'New prompt');
      expect(updated.expectedAnswer, 'new answer');
      expect(updated.isManuallyEdited, isTrue);
    });

    test('replaces multiple-choice choices entirely, not just correctness', () async {
      final db = await _openTestDatabase();
      final folder = await FoldersRepo(db).create('Physics');
      final note = await NotesRepo(db).create(folder.id, 'Note', 'body');
      final questions = QuestionsRepo(db);
      final question = await questions.create(
        note.id,
        questionTypeMultipleChoice,
        'Pick one',
        'B',
        choices: [('A', false), ('B', true), ('C', false)],
      );

      final updated = await questions.updateContent(
        question.id,
        prompt: 'Pick one',
        expectedAnswer: 'X',
        choices: [('X', true), ('Y', false)],
      );

      expect(updated.choices.map((c) => c.choiceText), ['X', 'Y']);
      expect(updated.choices.firstWhere((c) => c.isCorrect).choiceText, 'X');
    });
  });

  group('ReviewsRepo', () {
    test('record() is append-only and listForQuestion returns them in order', () async {
      final db = await _openTestDatabase();
      final folder = await FoldersRepo(db).create('Physics');
      final note = await NotesRepo(db).create(folder.id, 'Note', 'body');
      final question = await QuestionsRepo(db).create(note.id, questionTypeShortAnswer, 'Q', 'A');
      final reviews = ReviewsRepo(db);

      await reviews.record(question.id, 'wrong', false, 0, 0, gradingMethodKeywordMatch,
          askedAt: DateTime.utc(2026, 1, 1));
      await reviews.record(question.id, 'A', true, 0, 1, gradingMethodExactMatch,
          askedAt: DateTime.utc(2026, 1, 2));

      final history = await reviews.listForQuestion(question.id);
      expect(history, hasLength(2));
      expect(history[0].isCorrect, isFalse);
      expect(history[1].isCorrect, isTrue);
      expect(history[1].intervalIndexAfter, 1);
    });
  });
}
