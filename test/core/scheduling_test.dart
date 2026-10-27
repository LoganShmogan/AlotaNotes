import 'package:flutter_test/flutter_test.dart';
import 'package:quizapp/core/models.dart';
import 'package:quizapp/core/scheduling.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1);

  test('a new card is in learning, step 0, due straight away', () {
    final card = newCard(t0);
    expect((card.state, card.step, card.stability, card.difficulty, card.lastReview), (srsStateLearning, 0, null, null, null));
    expect(card.due, t0);
  });

  group('reviewCard on a new card follows the learning steps', () {
    final cases = [
      // (rating, expected state, expected time until due)
      (ReviewRating.again, srsStateLearning, const Duration(minutes: 1)),
      (ReviewRating.hard, srsStateLearning, const Duration(minutes: 5, seconds: 30)),
      (ReviewRating.good, srsStateLearning, const Duration(minutes: 10)),
      (ReviewRating.easy, srsStateReview, const Duration(days: 16)), // skips learning entirely
    ];
    for (final (rating, state, wait) in cases) {
      test(rating.name, () {
        final after = reviewCard(newCard(t0), rating, t0);
        expect(after.state, state);
        expect(after.due.difference(t0), wait);
        expect(after.lastReview, t0);
        expect(after.stability, isNotNull);
        expect(after.difficulty, isNotNull);
      });
    }
  });

  test('graduating to review, then lapsing into relearning', () {
    var card = reviewCard(newCard(t0), ReviewRating.good, t0);
    card = reviewCard(card, ReviewRating.good, card.due);
    expect((card.state, card.step), (srsStateReview, null));
    expect(card.due.difference(card.lastReview!), const Duration(days: 4));

    final lapsed = reviewCard(card, ReviewRating.again, card.due);
    expect((lapsed.state, lapsed.step), (srsStateRelearning, 0));
    expect(lapsed.due.difference(card.due), const Duration(minutes: 10));
  });

  test('harder ratings always come back sooner', () {
    var card = reviewCard(newCard(t0), ReviewRating.good, t0);
    card = reviewCard(card, ReviewRating.good, card.due);
    final preview = previewNextDue(card, card.due);
    final order = ReviewRating.values.map((r) => preview[r]!).toList();
    for (var i = 1; i < order.length; i++) {
      expect(order[i].isAfter(order[i - 1]), isTrue);
    }
    // The preview is exactly what reviewing does (no fuzzing).
    expect(preview[ReviewRating.good], reviewCard(card, ReviewRating.good, card.due).due);
  });

  test('a higher target retention schedules reviews sooner', () {
    var card = reviewCard(newCard(t0), ReviewRating.good, t0);
    card = reviewCard(card, ReviewRating.good, card.due);
    final normal = reviewCard(card, ReviewRating.good, card.due).due;
    final strict = reviewCard(card, ReviewRating.good, card.due, scheduler: buildScheduler(desiredRetention: 0.97)).due;
    expect(strict.isBefore(normal), isTrue);
  });

  test('retrievability counts partial days: recall drops within the first day', () {
    final card = reviewCard(newCard(t0), ReviewRating.again, t0); // stability ~0.2 days
    expect(retrievability(card, t0), closeTo(1, 1e-9));
    expect(retrievability(card, t0.add(const Duration(hours: 20))), lessThan(0.8));
    // At t = stability, recall is 90% by definition.
    final atS = t0.add(Duration(seconds: (card.stability! * Duration.secondsPerDay).round()));
    expect(retrievability(card, atS), closeTo(0.9, 1e-3));
  });

  test('retrievability: 0 before any review, then decays over time', () {
    expect(retrievability(newCard(t0), t0), 0);
    final card = reviewCard(newCard(t0), ReviewRating.easy, t0);
    final soon = retrievability(card, t0.add(const Duration(days: 1)));
    final later = retrievability(card, t0.add(const Duration(days: 30)));
    expect(soon, greaterThan(later));
    expect(soon, lessThanOrEqualTo(1));
    expect(later, greaterThan(0));
  });

  test('suggestedRating: right -> Good, wrong -> Again', () {
    expect(suggestedRating(true), ReviewRating.good);
    expect(suggestedRating(false), ReviewRating.again);
  });

  test('ReviewRating round-trips through its stored value', () {
    for (final r in ReviewRating.values) {
      expect(ReviewRating.fromValue(r.value), r);
    }
    expect(ReviewRating.values.map((r) => r.value), [1, 2, 3, 4]);
  });

  test('isDue', () {
    final now = DateTime.utc(2026, 1, 5);
    expect(isDue(DateTime.utc(2026, 1, 5), now), isTrue);
    expect(isDue(DateTime.utc(2026, 1, 4), now), isTrue);
    expect(isDue(DateTime.utc(2026, 1, 6), now), isFalse);
  });

  group('formatInterval', () {
    final cases = [
      (const Duration(seconds: 20), '1m'),
      (const Duration(minutes: 9, seconds: 59), '10m'), // rounds, doesn't truncate
      (const Duration(minutes: 59, seconds: 40), '1h'),
      (const Duration(hours: 3, minutes: 20), '3h'),
      (const Duration(hours: 23, minutes: 40), '1d'),
      (const Duration(days: 4, hours: 2), '4d'),
      (const Duration(days: 75), '3mo'),
      (const Duration(days: 547), '1.5y'),
      (const Duration(days: 4000), '11y'),
    ];
    for (final (d, label) in cases) {
      test(label, () => expect(formatInterval(d), label));
    }
  });

  group('cardFromLegacy', () {
    test('a never-answered question becomes a brand-new card, keeping its due date', () {
      final card = cardFromLegacy(intervalIndex: 0, nextDueAt: t0);
      expect((card.state, card.step, card.stability, card.due), (srsStateLearning, 0, null, t0));
    });

    test('an answered one becomes a review card whose stability is its earned interval', () {
      final asked = DateTime.utc(2025, 12, 27);
      final card = cardFromLegacy(intervalIndex: 3, nextDueAt: t0, lastAskedAt: asked);
      expect((card.state, card.stability, card.difficulty, card.due, card.lastReview), (srsStateReview, 5.0, 5.0, t0, asked));
      // And FSRS can carry on from it.
      expect(reviewCard(card, ReviewRating.good, t0).due.isAfter(t0.add(const Duration(days: 5))), isTrue);
    });

    test('legacy ladder is the old 1,2,3,5,7,14,30', () {
      expect(legacyIntervalDays, [1, 2, 3, 5, 7, 14, 30]);
    });
  });
}
