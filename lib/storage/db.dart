/// SQLite connection factory and schema, mirroring the Python desktop app's
/// `storage/db.dart` equivalent: no ORM, a thin factory, timestamps always
/// computed by the caller and stored as ISO-8601 UTC text (never a SQL-side
/// default), so behavior is deterministic and easy to test.
library;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import '../core/models.dart';
import '../core/scheduling.dart';

String dtToIso(DateTime value) => value.toUtc().toIso8601String();

DateTime isoToDt(String value) => DateTime.parse(value).toUtc();

DateTime utcNow() => DateTime.now().toUtc();

/// Bumped whenever [schemaStatements] changes; [migrateSchema] upgrades
/// older databases in place.
const schemaVersion = 2;

/// The FSRS columns shared by `questions` and `problems`. [card] null (a
/// problem never attempted) clears them all.
Map<String, Object?> srsCardToRow(SrsCard? card) => {
  'fsrs_state': card?.state,
  'fsrs_step': card?.step,
  'fsrs_stability': card?.stability,
  'fsrs_difficulty': card?.difficulty,
  'next_due_at': card == null ? null : dtToIso(card.due),
  'last_reviewed_at': card?.lastReview == null ? null : dtToIso(card!.lastReview!),
};

SrsCard? srsCardFromRow(Map<String, Object?> row) {
  if (row['fsrs_state'] == null) return null;
  return SrsCard(
    state: row['fsrs_state'] as int,
    step: row['fsrs_step'] as int?,
    stability: (row['fsrs_stability'] as num?)?.toDouble(),
    difficulty: (row['fsrs_difficulty'] as num?)?.toDouble(),
    due: isoToDt(row['next_due_at'] as String),
    lastReview: row['last_reviewed_at'] == null ? null : isoToDt(row['last_reviewed_at'] as String),
  );
}

/// Opens (creating if needed) the app's real on-device database. Tests
/// should not use this -- pass an already-open `Database` (e.g. via
/// `sqflite_common_ffi`'s `databaseFactoryFfi.openDatabase(inMemoryDatabasePath)`)
/// into the repos directly instead, the same "inject the connection" pattern
/// the Python app's repos use.
///
/// Plain `sqflite` only covers Android/iOS/macOS. The web build stores the
/// database in the browser's IndexedDB (via `sqflite_common_ffi_web`, whose
/// `web/sqlite3.wasm` + `web/sqflite_sw.js` come from
/// `dart run sqflite_common_ffi_web:setup`), and Windows/Linux use the FFI
/// build of SQLite.
Future<Database> openAppDatabase() async {
  // No filesystem in a browser: the web factory takes a bare name.
  final dbPath = kIsWeb ? 'quizapp.db' : join((await getApplicationDocumentsDirectory()).path, 'quizapp.db');
  return appDatabaseFactory().openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: schemaVersion,
      onCreate: (db, version) async {
        for (final statement in schemaStatements) {
          await db.execute(statement);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) => migrateSchema(db, oldVersion),
      // Not onConfigure: the v1 -> v2 migration has to run with them off.
      onOpen: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    ),
  );
}

/// Picks the SQLite backend for a platform. Split out of `openAppDatabase`
/// so every branch can be unit-tested from the VM: `kIsWeb` is a
/// compile-time constant, so the web branch is otherwise unreachable there.
DatabaseFactory appDatabaseFactory({bool isWeb = kIsWeb, TargetPlatform? platform}) {
  if (isWeb) return databaseFactoryFfiWeb;
  final target = platform ?? defaultTargetPlatform;
  if (target == TargetPlatform.windows || target == TargetPlatform.linux) {
    sqfliteFfiInit();
    return databaseFactoryFfi;
  }
  return databaseFactorySqflitePlugin;
}

// The FSRS columns, inlined into both card tables below.
const _srsColumns = '''
    fsrs_state INTEGER CHECK (fsrs_state IN (1, 2, 3)),
    fsrs_step INTEGER,
    fsrs_stability REAL,
    fsrs_difficulty REAL,
    last_reviewed_at TEXT,
''';

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
  ..._v2CardTables,
  '''
  CREATE TABLE question_choices (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    question_id INTEGER NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
    choice_text TEXT NOT NULL,
    is_correct INTEGER NOT NULL DEFAULT 0 CHECK (is_correct IN (0, 1)),
    sort_order INTEGER NOT NULL DEFAULT 0
  )
  ''',
  ..._v2HistoryTables,
  'CREATE INDEX idx_notes_folder_id ON notes(folder_id)',
  'CREATE INDEX idx_question_choices_question_id ON question_choices(question_id)',
  ..._v2Indexes,
];

// Every table/index that's new or rebuilt in schema v2, so the migration and
// a fresh install create exactly the same thing.
const _v2CardTables = [
  '''
  CREATE TABLE questions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    question_type TEXT NOT NULL CHECK (question_type IN ('short_answer', 'multiple_choice')),
    prompt TEXT NOT NULL,
    expected_answer TEXT NOT NULL,
$_srsColumns
    next_due_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
    is_manually_edited INTEGER NOT NULL DEFAULT 0 CHECK (is_manually_edited IN (0, 1))
  )
  ''',
  // A LeetCode-style practice problem. Its FSRS columns stay NULL until the
  // first attempt is logged, so an untried problem is never "due".
  '''
  CREATE TABLE problems (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    url TEXT,
    platform TEXT NOT NULL DEFAULT '',
    difficulty TEXT NOT NULL CHECK (difficulty IN ('easy', 'medium', 'hard')),
    tags TEXT NOT NULL DEFAULT '',
    solution TEXT NOT NULL DEFAULT '',
    notes TEXT NOT NULL DEFAULT '',
$_srsColumns
    next_due_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
  ''',
];

// Append-only audit trails of every review ever done -- the card columns
// alone can't reconstruct history since they're overwritten on every
// review. Same reasoning as the Python desktop app's question_history table.
const _v2HistoryTables = [
  '''
  CREATE TABLE question_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    question_id INTEGER NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
    asked_at TEXT NOT NULL,
    given_answer TEXT NOT NULL,
    is_correct INTEGER NOT NULL CHECK (is_correct IN (0, 1)),
    rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 4),
    grading_method TEXT NOT NULL CHECK (grading_method IN ('exact_match', 'keyword_match', 'mcq_exact')),
    next_due_after TEXT NOT NULL,
    stability_after REAL
  )
  ''',
  '''
  CREATE TABLE problem_attempts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    problem_id INTEGER NOT NULL REFERENCES problems(id) ON DELETE CASCADE,
    attempted_at TEXT NOT NULL,
    solved INTEGER NOT NULL CHECK (solved IN (0, 1)),
    duration_minutes INTEGER CHECK (duration_minutes IS NULL OR duration_minutes >= 0),
    rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 4),
    notes TEXT NOT NULL DEFAULT '',
    next_due_after TEXT NOT NULL,
    stability_after REAL
  )
  ''',
];

const _v2Indexes = [
  'CREATE INDEX idx_questions_note_id ON questions(note_id)',
  'CREATE INDEX idx_questions_next_due_at ON questions(next_due_at)',
  'CREATE INDEX idx_question_history_question_id ON question_history(question_id)',
  'CREATE INDEX idx_problems_next_due_at ON problems(next_due_at)',
  'CREATE INDEX idx_problem_attempts_problem_id ON problem_attempts(problem_id)',
];

/// Upgrades a database created at [oldVersion] to [schemaVersion], keeping
/// every row. Must run inside a transaction with foreign keys OFF, which is
/// how sqflite runs `onUpgrade` (`openAppDatabase` only switches them on in
/// `onOpen`, afterwards): dropping a rebuilt table with them on would
/// cascade-delete every row pointing at it.
Future<void> migrateSchema(DatabaseExecutor db, int oldVersion) async {
  if (oldVersion < 2) await _migrateV1ToV2(db);
}

/// v1 -> v2: the fixed interval ladder becomes FSRS. SQLite can't drop a
/// column with a CHECK constraint (not on every Android version), so
/// `questions` and `question_history` are rebuilt and their rows copied
/// across, keeping ids, each question getting an FSRS state derived from its
/// old interval (see `cardFromLegacy`). Old history rows get the rating
/// auto-grading would have suggested.
Future<void> _migrateV1ToV2(DatabaseExecutor db) async {
  final oldQuestions = await db.query('questions');
  final oldHistory = await db.query('question_history');
  await db.execute('DROP TABLE question_history');
  await db.execute('DROP TABLE questions');
  for (final statement in [..._v2CardTables, ..._v2HistoryTables]) {
    await db.execute(statement);
  }

  for (final row in oldQuestions) {
    final card = cardFromLegacy(
      intervalIndex: row['interval_index'] as int,
      nextDueAt: isoToDt(row['next_due_at'] as String),
      lastAskedAt: row['last_asked_at'] == null ? null : isoToDt(row['last_asked_at'] as String),
    );
    await db.insert('questions', {
      for (final key in ['id', 'note_id', 'question_type', 'prompt', 'expected_answer', 'created_at', 'active', 'is_manually_edited'])
        key: row[key],
      ...srsCardToRow(card),
    });
  }
  for (final row in oldHistory) {
    final askedAt = isoToDt(row['asked_at'] as String);
    final days = legacyIntervalDays[row['interval_index_after'] as int];
    await db.insert('question_history', {
      for (final key in ['id', 'question_id', 'asked_at', 'given_answer', 'is_correct', 'grading_method']) key: row[key],
      'rating': suggestedRating(row['is_correct'] == 1).value,
      'next_due_after': dtToIso(askedAt.add(Duration(days: days))),
    });
  }
  for (final statement in _v2Indexes) {
    await db.execute(statement);
  }
}

/// The v1 schema, kept verbatim so the migration test can build a real v1
/// database to upgrade.
@visibleForTesting
const List<String> schemaStatementsV1 = [
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
