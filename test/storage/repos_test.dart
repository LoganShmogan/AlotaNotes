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

  group('FoldersRepo', () {
    test('create/get round-trip, with an explicit timestamp', () async {
      final db = await _openTestDatabase();
      final folders = FoldersRepo(db);
      final created = await folders.create('Physics', now: DateTime.utc(2026, 1, 1));

      final fetched = await folders.get(created.id);
      expect(fetched.name, 'Physics');
      expect(fetched.parentFolderId, isNull);
      expect(fetched.createdAt, DateTime.utc(2026, 1, 1));
    });

    test('get throws StateError for a missing id', () async {
      final db = await _openTestDatabase();
      expect(() => FoldersRepo(db).get(999), throwsStateError);
    });

    test('listChildren separates top-level folders from subfolders, sorted by name', () async {
      final db = await _openTestDatabase();
      final folders = FoldersRepo(db);
      final physics = await folders.create('Physics');
      await folders.create('Biology');
      await folders.create('Optics', parentFolderId: physics.id);
      await folders.create('Mechanics', parentFolderId: physics.id);

      expect((await folders.listChildren(null)).map((f) => f.name), ['Biology', 'Physics']);
      final children = await folders.listChildren(physics.id);
      expect(children.map((f) => f.name), ['Mechanics', 'Optics']);
      expect(children.first.parentFolderId, physics.id);
    });

    test('delete cascades to subfolders and notes', () async {
      final db = await _openTestDatabase();
      final folders = FoldersRepo(db);
      final parent = await folders.create('Parent');
      final child = await folders.create('Child', parentFolderId: parent.id);
      final note = await NotesRepo(db).create(child.id, 'Note', 'body');

      await folders.delete(parent.id);
      expect(await folders.listChildren(null), isEmpty);
      expect(() => folders.get(child.id), throwsStateError);
      expect(() => NotesRepo(db).get(note.id), throwsStateError);
    });
  });

  group('NotesRepo basics', () {
    test('create stores every field and sets created/updated to the same instant', () async {
      final db = await _openTestDatabase();
      final folder = await FoldersRepo(db).create('F');
      final note = await NotesRepo(db).create(
        folder.id,
        'Title',
        'Body',
        sourceFilename: 'lecture.pdf',
        sortOrder: 3,
        now: DateTime.utc(2026, 2, 1),
      );

      expect(note.folderId, folder.id);
      expect(note.title, 'Title');
      expect(note.body, 'Body');
      expect(note.sourceFilename, 'lecture.pdf');
      expect(note.sortOrder, 3);
      expect(note.createdAt, DateTime.utc(2026, 2, 1));
      expect(note.updatedAt, note.createdAt);
    });

    test('update changes title/body and bumps updated_at only', () async {
      final db = await _openTestDatabase();
      final folder = await FoldersRepo(db).create('F');
      final notes = NotesRepo(db);
      final note = await notes.create(folder.id, 'Old', 'old', now: DateTime.utc(2026, 1, 1));

      final updated = await notes.update(note.id, title: 'New', body: 'new', now: DateTime.utc(2026, 1, 5));
      expect(updated.title, 'New');
      expect(updated.body, 'new');
      expect(updated.createdAt, DateTime.utc(2026, 1, 1));
      expect(updated.updatedAt, DateTime.utc(2026, 1, 5));
    });

    test('get/update throw StateError for a missing id', () async {
      final db = await _openTestDatabase();
      expect(() => NotesRepo(db).get(1), throwsStateError);
      expect(() => NotesRepo(db).update(1, title: 'x'), throwsStateError);
    });

    test('delete removes the note and cascades to its questions', () async {
      final db = await _openTestDatabase();
      final folder = await FoldersRepo(db).create('F');
      final notes = NotesRepo(db);
      final note = await notes.create(folder.id, 'N', 'b');
      final question = await QuestionsRepo(db).create(note.id, questionTypeShortAnswer, 'Q', 'A');

      await notes.delete(note.id);
      expect(await notes.listByFolder(folder.id), isEmpty);
      expect(() => QuestionsRepo(db).get(question.id), throwsStateError);
    });
  });

  group('QuestionsRepo', () {
    late Database db;
    late int noteId;
    late QuestionsRepo questions;

    setUp(() async {
      db = await _openTestDatabase();
      final folder = await FoldersRepo(db).create('F');
      noteId = (await NotesRepo(db).create(folder.id, 'N', 'b')).id;
      questions = QuestionsRepo(db);
    });

    test('new questions start at interval 0, first due one day after creation', () async {
      final q = await questions.create(noteId, questionTypeShortAnswer, 'Q', 'A', now: DateTime.utc(2026, 1, 1));
      expect(q.intervalIndex, 0);
      expect(q.nextDueAt, DateTime.utc(2026, 1, 2));
      expect(q.createdAt, DateTime.utc(2026, 1, 1));
      expect(q.lastAskedAt, isNull);
      expect(q.active, isTrue);
      expect(q.isManuallyEdited, isFalse);
      expect(q.choices, isEmpty);
    });

    test('multiple-choice questions keep their choices in order', () async {
      final q = await questions.create(
        noteId,
        questionTypeMultipleChoice,
        'Pick',
        'B',
        choices: [('A', false), ('B', true)],
      );
      expect(q.choices.map((c) => (c.choiceText, c.isCorrect, c.sortOrder)), [('A', false, 0), ('B', true, 1)]);
      expect(q.choices.first.questionId, q.id);
    });

    test('get throws StateError for a missing id', () async {
      expect(() => questions.get(999), throwsStateError);
    });

    test('listByNote returns only that note\'s questions, in creation order', () async {
      final folder = await FoldersRepo(db).create('Other');
      final otherNote = await NotesRepo(db).create(folder.id, 'Other', '');
      await questions.create(noteId, questionTypeShortAnswer, 'First', 'A');
      await questions.create(otherNote.id, questionTypeShortAnswer, 'Elsewhere', 'A');
      await questions.create(noteId, questionTypeShortAnswer, 'Second', 'A');

      expect((await questions.listByNote(noteId)).map((q) => q.prompt), ['First', 'Second']);
    });

    test('listDue returns active questions due by now, soonest first', () async {
      await questions.create(noteId, questionTypeShortAnswer, 'Later', 'A', now: DateTime.utc(2026, 1, 3));
      await questions.create(noteId, questionTypeShortAnswer, 'Earlier', 'A', now: DateTime.utc(2026, 1, 1));
      await questions.create(noteId, questionTypeShortAnswer, 'Not yet', 'A', now: DateTime.utc(2026, 1, 9));
      final inactive = await questions.create(noteId, questionTypeShortAnswer, 'Off', 'A', now: DateTime.utc(2026, 1, 1));
      await db.update('questions', {'active': 0}, where: 'id = ?', whereArgs: [inactive.id]);

      final due = await questions.listDue(DateTime.utc(2026, 1, 5));
      expect(due.map((q) => q.prompt), ['Earlier', 'Later']);
    });

    test('updateContent without choices leaves existing choices alone', () async {
      final q = await questions.create(noteId, questionTypeMultipleChoice, 'P', 'A', choices: [('A', true)]);
      final updated = await questions.updateContent(q.id, prompt: 'P2', expectedAnswer: 'A');
      expect(updated.choices.single.choiceText, 'A');
    });

    test('updateScheduling stores the new interval, last-asked and due times', () async {
      final q = await questions.create(noteId, questionTypeShortAnswer, 'Q', 'A');
      final updated = await questions.updateScheduling(
        q.id,
        intervalIndex: 3,
        lastAskedAt: DateTime.utc(2026, 4, 1),
        nextDueAt: DateTime.utc(2026, 4, 6),
      );
      expect(updated.intervalIndex, 3);
      expect(updated.lastAskedAt, DateTime.utc(2026, 4, 1));
      expect(updated.nextDueAt, DateTime.utc(2026, 4, 6));
    });

    test('the schema rejects an interval index outside the 7-step sequence', () async {
      final q = await questions.create(noteId, questionTypeShortAnswer, 'Q', 'A');
      expect(
        () => questions.updateScheduling(q.id, intervalIndex: 7, lastAskedAt: utcNow(), nextDueAt: utcNow()),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('ReviewsRepo defaults', () {
    test('record() stamps askedAt with the current time when not given', () async {
      final db = await _openTestDatabase();
      final folder = await FoldersRepo(db).create('F');
      final note = await NotesRepo(db).create(folder.id, 'N', 'b');
      final question = await QuestionsRepo(db).create(note.id, questionTypeMultipleChoice, 'Q', 'A');

      final before = utcNow();
      final review = await ReviewsRepo(db).record(question.id, 'A', true, 0, 1, gradingMethodMcqExact);
      expect(review.askedAt.isBefore(before), isFalse);
      expect(review.givenAnswer, 'A');
      expect(review.gradingMethod, gradingMethodMcqExact);
      expect(review.intervalIndexBefore, 0);
    });
  });
}
