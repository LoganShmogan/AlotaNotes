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

/// How well a review went, in FSRS's four grades. `value` is what's stored
/// in the database and matches FSRS's own numbering.
enum ReviewRating {
  again(1, 'Again'),
  hard(2, 'Hard'),
  good(3, 'Good'),
  easy(4, 'Easy');

  final int value;
  final String label;
  const ReviewRating(this.value, this.label);

  static ReviewRating fromValue(int value) => values.firstWhere((r) => r.value == value);
}

/// FSRS learning states, numbered like the fsrs package's `State`.
const srsStateLearning = 1;
const srsStateReview = 2;
const srsStateRelearning = 3;

/// One reviewable item's FSRS memory state: how well it is remembered
/// ([stability], in days, and [difficulty], 1-10) and when it's next due.
/// Both quiz questions and tracked problems carry one. See
/// Docs/scheduling_algorithm.md.
class SrsCard {
  final int state;
  final int? step;
  final double? stability;
  final double? difficulty;
  final DateTime due;
  final DateTime? lastReview;

  const SrsCard({
    required this.state,
    required this.due,
    this.step,
    this.stability,
    this.difficulty,
    this.lastReview,
  });
}

class Question {
  final int id;
  final int noteId;
  final String questionType;
  final String prompt;
  final String expectedAnswer;
  final SrsCard card;
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
    required this.card,
    required this.createdAt,
    required this.active,
    this.isManuallyEdited = false,
    this.choices = const [],
  });

  DateTime get nextDueAt => card.due;
  DateTime? get lastAskedAt => card.lastReview;
}

/// One append-only row in the review history audit log. See db.dart's
/// `question_history` table comment for why this exists separately from
/// `Question.card`.
class ReviewRecord {
  final int id;
  final int questionId;
  final DateTime askedAt;
  final String givenAnswer;
  final bool isCorrect;
  final ReviewRating rating;
  final String gradingMethod;
  final DateTime nextDueAfter;
  final double? stabilityAfter;

  const ReviewRecord({
    required this.id,
    required this.questionId,
    required this.askedAt,
    required this.givenAnswer,
    required this.isCorrect,
    required this.rating,
    required this.gradingMethod,
    required this.nextDueAfter,
    this.stabilityAfter,
  });
}

const problemDifficultyEasy = 'easy';
const problemDifficultyMedium = 'medium';
const problemDifficultyHard = 'hard';
const problemDifficulties = [problemDifficultyEasy, problemDifficultyMedium, problemDifficultyHard];

enum ProblemStatus { todo, attempted, solved }

/// A tracked practice problem (LeetCode-style): what it is, your solution,
/// and its own FSRS schedule for re-solving it. [card] stays null until the
/// first attempt is logged -- a problem you haven't tried yet isn't "due".
class Problem {
  final int id;
  final String title;
  final String? url;
  final String platform;
  final String difficulty;
  final List<String> tags;
  final String solution;
  final String notes;
  final SrsCard? card;
  final int attemptCount;
  final bool lastAttemptSolved;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Problem({
    required this.id,
    required this.title,
    required this.difficulty,
    required this.createdAt,
    required this.updatedAt,
    this.url,
    this.platform = '',
    this.tags = const [],
    this.solution = '',
    this.notes = '',
    this.card,
    this.attemptCount = 0,
    this.lastAttemptSolved = false,
  });

  ProblemStatus get status {
    if (attemptCount == 0) return ProblemStatus.todo;
    return lastAttemptSolved ? ProblemStatus.solved : ProblemStatus.attempted;
  }
}

/// One logged go at a problem. Append-only, like [ReviewRecord].
class ProblemAttempt {
  final int id;
  final int problemId;
  final DateTime attemptedAt;
  final bool solved;
  final int? durationMinutes;
  final ReviewRating rating;
  final String notes;
  final DateTime nextDueAfter;
  final double? stabilityAfter;

  const ProblemAttempt({
    required this.id,
    required this.problemId,
    required this.attemptedAt,
    required this.solved,
    required this.rating,
    required this.nextDueAfter,
    this.durationMinutes,
    this.notes = '',
    this.stabilityAfter,
  });
}
