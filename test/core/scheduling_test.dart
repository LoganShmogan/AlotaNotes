import 'package:flutter_test/flutter_test.dart';
import 'package:quizapp/core/scheduling.dart';

void main() {
  group('nextIntervalIndex', () {
    final cases = [
      // (currentIndex, wasCorrect, expectedNewIndex)
      (0, true, 1),
      (4, true, 5),
      (5, true, 6),
      (maxIndex, true, 0), // loops back to the very start, not a mid-sequence anchor
      (7, false, 0),
      (0, false, 0),
    ];

    for (final c in cases) {
      test('index ${c.$1}, correct=${c.$2} -> ${c.$3}', () {
        expect(nextIntervalIndex(c.$1, c.$2), c.$3);
      });
    }
  });

  test('intervalDaysForIndex matches the agreed 1,2,3,5,7,14,30 sequence', () {
    expect(intervalSequenceDays, [1, 2, 3, 5, 7, 14, 30]);
    expect(intervalDaysForIndex(0), 1);
    expect(intervalDaysForIndex(6), 30);
  });

  test('computeNextDueAt adds the right number of days', () {
    final answeredAt = DateTime.utc(2026, 1, 1);
    expect(computeNextDueAt(answeredAt, 0), DateTime.utc(2026, 1, 2));
    expect(computeNextDueAt(answeredAt, 6), DateTime.utc(2026, 1, 31));
  });

  test('applyReview bundles index + due date together', () {
    final answeredAt = DateTime.utc(2026, 1, 1);
    final outcome = applyReview(2, true, answeredAt);
    expect(outcome.newIndex, 3);
    expect(outcome.nextDueAt, DateTime.utc(2026, 1, 6)); // index 3 -> 5 days
  });

  test('applyReview resets to day 1 on a wrong answer regardless of prior index', () {
    final answeredAt = DateTime.utc(2026, 1, 1);
    final outcome = applyReview(6, false, answeredAt);
    expect(outcome.newIndex, 0);
    expect(outcome.nextDueAt, DateTime.utc(2026, 1, 2));
  });

  test('isDue', () {
    final now = DateTime.utc(2026, 1, 5);
    expect(isDue(DateTime.utc(2026, 1, 5), now), isTrue);
    expect(isDue(DateTime.utc(2026, 1, 4), now), isTrue);
    expect(isDue(DateTime.utc(2026, 1, 6), now), isFalse);
  });
}
