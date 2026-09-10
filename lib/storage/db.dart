/// SQLite connection factory and schema, mirroring the Python desktop app's
/// `storage/db.dart` equivalent: no ORM, a thin factory, timestamps always
/// computed by the caller and stored as ISO-8601 UTC text (never a SQL-side
/// default), so behavior is deterministic and easy to test.
library;

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

String dtToIso(DateTime value) => value.toUtc().toIso8601String();

DateTime isoToDt(String value) => DateTime.parse(value).toUtc();

DateTime utcNow() => DateTime.now().toUtc();

/// Opens (creating if needed) the app's real on-device database. Tests
/// should not use this -- pass an already-open `Database` (e.g. via
/// `sqflite_common_ffi`'s `databaseFactoryFfi.openDatabase(inMemoryDatabasePath)`)
/// into the repos directly instead, the same "inject the connection" pattern
/// the Python app's repos use.
Future<Database> openAppDatabase() async {
  final directory = await getApplicationDocumentsDirectory();
  final dbPath = join(directory.path, 'quizapp.db');
  return openDatabase(
    dbPath,
    version: 1,
    onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    onCreate: (db, version) async {
      for (final statement in schemaStatements) {
        await db.execute(statement);
      }
    },
  );
}

const List<String> schemaStatements = [
  '''
  CREATE TABLE folders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    parent_folder_id INTEGER REFERENCES folders(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    created_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    source_filename TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE questions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    question_type TEXT NOT NULL CHECK (question_type IN ('short_answer', 'multiple_choice')),
    prompt TEXT NOT NULL,
    expected_answer TEXT NOT NULL,
    interval_index INTEGER NOT NULL DEFAULT 0 CHECK (interval_index BETWEEN 0 AND 6),
    last_asked_at TEXT,
    next_due_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
    is_manually_edited INTEGER NOT NULL DEFAULT 0 CHECK (is_manually_edited IN (0, 1))
  )
  ''',
  '''
  CREATE TABLE question_choices (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    question_id INTEGER NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
    choice_text TEXT NOT NULL,
    is_correct INTEGER NOT NULL DEFAULT 0 CHECK (is_correct IN (0, 1)),
    sort_order INTEGER NOT NULL DEFAULT 0
  )
  ''',
  // Append-only audit trail of every answer ever given -- interval_index
  // alone can't reconstruct history since it's overwritten on every review.
  // Same reasoning as the Python desktop app's question_history table (see
  // Docs/beginners_guide.md section 10 there).
  '''
  CREATE TABLE question_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    question_id INTEGER NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
    asked_at TEXT NOT NULL,
    given_answer TEXT NOT NULL,
    is_correct INTEGER NOT NULL CHECK (is_correct IN (0, 1)),
    interval_index_before INTEGER NOT NULL,
    interval_index_after INTEGER NOT NULL,
    grading_method TEXT NOT NULL CHECK (grading_method IN ('exact_match', 'keyword_match', 'mcq_exact'))
  )
  ''',
  'CREATE INDEX idx_notes_folder_id ON notes(folder_id)',
  'CREATE INDEX idx_questions_note_id ON questions(note_id)',
  'CREATE INDEX idx_questions_next_due_at ON questions(next_due_at)',
  'CREATE INDEX idx_question_choices_question_id ON question_choices(question_id)',
  'CREATE INDEX idx_question_history_question_id ON question_history(question_id)',
];
