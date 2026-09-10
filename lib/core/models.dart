/// Plain immutable data classes shared across storage and screens.
///
/// Same reasoning as the Python desktop app's `core/models.dart` equivalent:
/// these are snapshots of a database row at read time, not live handles --
/// nothing outside the repos layer should hold one and expect edits on it to
/// reach the database. Dart doesn't have Python's `@dataclass(frozen=True)`,
/// so immutability here just means "every field is `final`, no setters."
library;

const questionTypeShortAnswer = 'short_answer';
const questionTypeMultipleChoice = 'multiple_choice';

const gradingMethodExactMatch = 'exact_match';
const gradingMethodKeywordMatch = 'keyword_match';
const gradingMethodMcqExact = 'mcq_exact';

class Folder {
  final int id;
  final int? parentFolderId;
  final String name;
  final DateTime createdAt;

  const Folder({
    required this.id,
    required this.name,
    required this.createdAt,
    this.parentFolderId,
  });
}

class Note {
  final int id;
  final int folderId;
  final String title;
  final String body;
  final String? sourceFilename;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Note({
    required this.id,
    required this.folderId,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.sourceFilename,
    this.sortOrder = 0,
  });
}

class Choice {
  final int id;
  final int questionId;
  final String choiceText;
  final bool isCorrect;
  final int sortOrder;

  const Choice({
    required this.id,
    required this.questionId,
    required this.choiceText,
    required this.isCorrect,
    required this.sortOrder,
  });
}

class Question {
  final int id;
  final int noteId;
  final String questionType;
  final String prompt;
  final String expectedAnswer;
  final int intervalIndex;
  final DateTime? lastAskedAt;
  final DateTime nextDueAt;
  final DateTime createdAt;
  final bool active;
  final bool isManuallyEdited;
  final List<Choice> choices;

  const Question({
    required this.id,
    required this.noteId,
    required this.questionType,
    required this.prompt,
    required this.expectedAnswer,
    required this.intervalIndex,
    required this.nextDueAt,
    required this.createdAt,
    required this.active,
    this.lastAskedAt,
    this.isManuallyEdited = false,
    this.choices = const [],
  });
}

/// One append-only row in the review history audit log. See db.dart's
/// `question_history` table comment for why this exists separately from
/// `Question.intervalIndex`.
class ReviewRecord {
  final int id;
  final int questionId;
  final DateTime askedAt;
  final String givenAnswer;
  final bool isCorrect;
  final int intervalIndexBefore;
  final int intervalIndexAfter;
  final String gradingMethod;

  const ReviewRecord({
    required this.id,
    required this.questionId,
    required this.askedAt,
    required this.givenAnswer,
    required this.isCorrect,
    required this.intervalIndexBefore,
    required this.intervalIndexAfter,
    required this.gradingMethod,
  });
}
