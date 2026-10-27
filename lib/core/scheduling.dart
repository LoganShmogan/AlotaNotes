/// Spaced-repetition scheduling with FSRS (Free Spaced Repetition
/// Scheduler), the forgetting-curve model Anki uses.
///
/// A thin, pure wrapper around the `fsrs` package (the open-spaced-repetition
/// project's own Dart port) so the rest of the app only ever sees
/// [SrsCard]/[ReviewRating] and never the package's mutable `Card`. Same
/// shape as before: pure functions, no I/O, every timestamp passed in.
///
/// Fuzzing is off: the interval shown on a rating button is exactly the
/// interval that rating will schedule. See Docs/scheduling_algorithm.md.
library;

import 'dart:math' as math;

import 'package:fsrs/fsrs.dart' as fsrs;

import 'models.dart';

/// Target probability of still remembering an item when it comes due.
/// Higher means more frequent reviews.
const defaultDesiredRetention = 0.9;
const minDesiredRetention = 0.75;
const maxDesiredRetention = 0.97;

fsrs.Scheduler buildScheduler({double desiredRetention = defaultDesiredRetention}) =>
    fsrs.Scheduler(desiredRetention: desiredRetention, enableFuzzing: false);

/// A never-reviewed card, due straight away -- FSRS's learning steps (1 min,
/// then 10 min) handle the first same-session repetitions.
SrsCard newCard(DateTime now) => SrsCard(state: srsStateLearning, step: 0, due: now);

fsrs.Card _toFsrs(SrsCard card) => fsrs.Card(
      cardId: 0,
      state: fsrs.State.fromValue(card.state),
      step: card.step,
      stability: card.stability,
      difficulty: card.difficulty,
      due: card.due.toUtc(),
      lastReview: card.lastReview?.toUtc(),
    );

SrsCard _fromFsrs(fsrs.Card card) => SrsCard(
      state: card.state.value,
      step: card.step,
      stability: card.stability,
      difficulty: card.difficulty,
      due: card.due,
      lastReview: card.lastReview,
    );

/// The card's state after a review with [rating] at [reviewedAt].
SrsCard reviewCard(SrsCard card, ReviewRating rating, DateTime reviewedAt, {fsrs.Scheduler? scheduler}) {
  final result = (scheduler ?? buildScheduler()).reviewCard(
    _toFsrs(card),
    fsrs.Rating.fromValue(rating.value),
    reviewDateTime: reviewedAt.toUtc(),
  );
  return _fromFsrs(result.card);
}

/// When each rating would make the card due next, for labelling the rating
/// buttons ("Good · 3d").
Map<ReviewRating, DateTime> previewNextDue(SrsCard card, DateTime reviewedAt, {fsrs.Scheduler? scheduler}) {
  final s = scheduler ?? buildScheduler();
  return {for (final r in ReviewRating.values) r: reviewCard(card, r, reviewedAt, scheduler: s).due};
}

/// Probability (0-1) of recalling the card right now, from the FSRS
/// forgetting curve R = (1 + factor * t / S) ^ decay. 0 for a card that has
/// never been reviewed.
///
/// Computed here rather than with the package's `getCardRetrievability`,
/// which rounds elapsed time down to whole days: anything reviewed earlier
/// today would always read 100%, even right after forgetting it.
double retrievability(SrsCard card, DateTime now, {fsrs.Scheduler? scheduler}) {
  final lastReview = card.lastReview;
  if (lastReview == null || card.stability == null) return 0;
  final decay = -(scheduler ?? buildScheduler()).parameters[20];
  final factor = math.pow(0.9, 1 / decay) - 1;
  final elapsedDays = math.max(0, now.difference(lastReview).inSeconds) / Duration.secondsPerDay;
  return math.pow(1 + factor * elapsedDays / card.stability!, decay).toDouble();
}

/// Auto-grading only knows right or wrong; the user can then nudge it to
/// Hard or Easy before it's saved.
ReviewRating suggestedRating(bool wasCorrect) => wasCorrect ? ReviewRating.good : ReviewRating.again;

bool isDue(DateTime due, DateTime now) => !due.isAfter(now);

/// Compact interval label, rounded to the nearest unit: 1m, 10m, 3h, 4d,
/// 2mo, 1.5y. Rounding (not truncating) keeps "due in 10m" from reading
/// "9m" a moment after it was scheduled.
String formatInterval(Duration d) {
  final minutes = (d.inSeconds / 60).round();
  if (minutes < 60) return '${math.max(1, minutes)}m';
  final hours = (d.inMinutes / 60).round();
  if (hours < 24) return '${hours}h';
  final days = (d.inHours / 24).round();
  if (days < 30) return '${days}d';
  if (days < 365) return '${(days / 30).round()}mo';
  final years = days / 365;
  return '${years.toStringAsFixed(years < 10 ? 1 : 0)}y';
}

/// The fixed-interval ladder the app used before FSRS, kept only so
/// [cardFromLegacy] can migrate old databases.
const legacyIntervalDays = [1, 2, 3, 5, 7, 14, 30];

/// Best-effort FSRS state for a question scheduled by the old ladder: never
/// answered -> brand new; otherwise a Review card whose stability is the
/// interval it had earned, at medium difficulty. Its due date is kept.
SrsCard cardFromLegacy({required int intervalIndex, required DateTime nextDueAt, DateTime? lastAskedAt}) {
  if (lastAskedAt == null) return SrsCard(state: srsStateLearning, step: 0, due: nextDueAt);
  return SrsCard(
    state: srsStateReview,
    stability: legacyIntervalDays[intervalIndex].toDouble(),
    difficulty: 5,
    due: nextDueAt,
    lastReview: lastAskedAt,
  );
}
