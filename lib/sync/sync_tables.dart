/// How each local table maps onto its server table (backend/convex/
/// validators.ts): column names become camelCase keys, 0/1 flags become
/// booleans, and the parent foreign key becomes the parent row's `uid`.
library;

enum FieldKind { text, integer, real, boolean }

class SyncField {
  final String column;
  final String key;
  final FieldKind kind;
  const SyncField(this.column, this.key, [this.kind = FieldKind.text]);

  Object? toRemote(Object? value) => switch (kind) {
        _ when value == null => null,
        FieldKind.boolean => value == 1,
        FieldKind.real => (value as num).toDouble(),
        _ => value,
      };

  Object? toLocal(Object? value) => switch (kind) {
        _ when value == null => null,
        FieldKind.boolean => value == true ? 1 : 0,
        FieldKind.integer => (value as num).toInt(),
        FieldKind.real => (value as num).toDouble(),
        FieldKind.text => value,
      };
}

class SyncTable {
  /// The SQLite table, e.g. `question_choices`.
  final String local;

  /// The Convex table and push/pull key, e.g. `questionChoices`.
  final String remote;

  /// The foreign key column, the table it points at, and the key its uid
  /// travels under. Null for top-level tables.
  final (String column, String table, String key)? parent;

  /// True when the parent column may be null (only a top-level folder).
  final bool parentOptional;

  final List<SyncField> fields;

  const SyncTable({
    required this.local,
    required this.remote,
    this.parent,
    this.parentOptional = false,
    required this.fields,
  });
}

const _srsFields = [
  SyncField('fsrs_state', 'fsrsState', FieldKind.integer),
  SyncField('fsrs_step', 'fsrsStep', FieldKind.integer),
  SyncField('fsrs_stability', 'fsrsStability', FieldKind.real),
  SyncField('fsrs_difficulty', 'fsrsDifficulty', FieldKind.real),
  SyncField('last_reviewed_at', 'lastReviewedAt'),
];

/// Parents before children, the order rows are applied in.
const syncTables = [
  SyncTable(
    local: 'folders',
    remote: 'folders',
    parent: ('parent_folder_id', 'folders', 'parentFolderUid'),
    parentOptional: true,
    fields: [SyncField('name', 'name'), SyncField('created_at', 'createdAt')],
  ),
  SyncTable(
    local: 'notes',
    remote: 'notes',
    parent: ('folder_id', 'folders', 'folderUid'),
    fields: [
      SyncField('title', 'title'),
      SyncField('body', 'body'),
      SyncField('source_filename', 'sourceFilename'),
      SyncField('sort_order', 'sortOrder', FieldKind.integer),
      SyncField('created_at', 'createdAt'),
      SyncField('updated_at', 'updatedAt'),
    ],
  ),
  SyncTable(
    local: 'questions',
    remote: 'questions',
    parent: ('note_id', 'notes', 'noteUid'),
    fields: [
      SyncField('question_type', 'questionType'),
      SyncField('prompt', 'prompt'),
      SyncField('expected_answer', 'expectedAnswer'),
      ..._srsFields,
      SyncField('next_due_at', 'nextDueAt'),
      SyncField('created_at', 'createdAt'),
      SyncField('active', 'active', FieldKind.boolean),
      SyncField('is_manually_edited', 'isManuallyEdited', FieldKind.boolean),
    ],
  ),
  SyncTable(
    local: 'question_choices',
    remote: 'questionChoices',
    parent: ('question_id', 'questions', 'questionUid'),
    fields: [
      SyncField('choice_text', 'choiceText'),
      SyncField('is_correct', 'isCorrect', FieldKind.boolean),
      SyncField('sort_order', 'sortOrder', FieldKind.integer),
    ],
  ),
  SyncTable(
    local: 'question_history',
    remote: 'questionHistory',
    parent: ('question_id', 'questions', 'questionUid'),
    fields: [
      SyncField('asked_at', 'askedAt'),
      SyncField('given_answer', 'givenAnswer'),
      SyncField('is_correct', 'isCorrect', FieldKind.boolean),
      SyncField('rating', 'rating', FieldKind.integer),
      SyncField('grading_method', 'gradingMethod'),
      SyncField('next_due_after', 'nextDueAfter'),
      SyncField('stability_after', 'stabilityAfter', FieldKind.real),
    ],
  ),
  SyncTable(
    local: 'problems',
    remote: 'problems',
    fields: [
      SyncField('title', 'title'),
      SyncField('url', 'url'),
      SyncField('platform', 'platform'),
      SyncField('difficulty', 'difficulty'),
      SyncField('tags', 'tags'),
      SyncField('solution', 'solution'),
      SyncField('notes', 'notes'),
      ..._srsFields,
      SyncField('next_due_at', 'nextDueAt'),
      SyncField('created_at', 'createdAt'),
      SyncField('updated_at', 'updatedAt'),
    ],
  ),
  SyncTable(
    local: 'problem_attempts',
    remote: 'problemAttempts',
    parent: ('problem_id', 'problems', 'problemUid'),
    fields: [
      SyncField('attempted_at', 'attemptedAt'),
      SyncField('solved', 'solved', FieldKind.boolean),
      SyncField('duration_minutes', 'durationMinutes', FieldKind.integer),
      SyncField('rating', 'rating', FieldKind.integer),
      SyncField('notes', 'notes'),
      SyncField('next_due_after', 'nextDueAfter'),
      SyncField('stability_after', 'stabilityAfter', FieldKind.real),
    ],
  ),
];

SyncTable syncTableByLocal(String local) => syncTables.firstWhere((t) => t.local == local);
