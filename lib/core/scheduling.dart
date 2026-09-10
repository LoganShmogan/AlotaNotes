/// Spaced-repetition interval scheduling.
///
/// Direct port of the Python desktop app's `core/scheduling.py`, same shape
/// (pure functions, no I/O), new numbers agreed for this rewrite: a shorter
/// sequence that always loops back to the very start, rather than settling
/// into a permanent steady-state loop partway through.
///
/// A brand-new question is NOT due immediately (unlike the old desktop app)
/// -- its first review is 1 day after the note was saved.
library;

/// Days to wait at each step. Index 0 is the first review after a note is
/// saved; reaching the last index and answering correctly loops back to 0.
const List<int> intervalSequenceDays = [1, 2, 3, 5, 7, 14, 30];

int get maxIndex => intervalSequenceDays.length - 1;

/// Incorrect -> back to 0. Correct at the last index -> loop to 0.
/// Otherwise -> advance one step.
int nextIntervalIndex(int currentIndex, bool wasCorrect) {
  if (!wasCorrect) return 0;
  if (currentIndex >= maxIndex) return 0;
  return currentIndex + 1;
}

int intervalDaysForIndex(int index) => intervalSequenceDays[index];

DateTime computeNextDueAt(DateTime answeredAt, int newIndex) {
  return answeredAt.add(Duration(days: intervalDaysForIndex(newIndex)));
}

class ReviewOutcome {
  final int newIndex;
  final DateTime nextDueAt;
  const ReviewOutcome({required this.newIndex, required this.nextDueAt});
}

ReviewOutcome applyReview(int currentIndex, bool wasCorrect, DateTime answeredAt) {
  final newIndex = nextIntervalIndex(currentIndex, wasCorrect);
  return ReviewOutcome(newIndex: newIndex, nextDueAt: computeNextDueAt(answeredAt, newIndex));
}

bool isDue(DateTime nextDueAt, DateTime now) => !nextDueAt.isAfter(now);
