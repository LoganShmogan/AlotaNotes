// Writes the reviews the Flutter app's scheduler produces for a fixed set of
// rating sequences, so the backend's TypeScript port can check it schedules
// identically (backend/tests/scheduling.test.ts):
//
//   dart run tool/fsrs_parity_fixture.dart > backend/tests/fixtures/fsrs_parity.json
import 'dart:convert';
import 'dart:io';

import 'package:quillfin/core/models.dart';
import 'package:quillfin/core/scheduling.dart';

void main() {
  final start = DateTime.utc(2026, 1, 1, 9);
  // Each step: the rating, and how long after the previous due date the
  // review happens (negative = early, as when reviewed ahead of time).
  // [sameDay] instead means one hour after the previous review.
  const sameDay = 999999;
  const sequences = <String, List<(int, int)>>{
    'good all the way': [(3, 0), (3, 0), (3, 0), (3, 0), (3, 0), (3, 0)],
    'easy first': [(4, 0), (3, 0), (4, 0)],
    'again then good': [(1, 0), (1, 0), (3, 0), (3, 0), (3, 0)],
    'hard steps': [(2, 0), (2, 0), (3, 0), (2, 0), (3, 0)],
    'lapse and relearn': [(3, 0), (3, 0), (3, 0), (1, 0), (2, 0), (3, 0), (3, 0)],
    'late reviews': [(3, 0), (3, 0), (3, 2880), (3, 14400), (1, 43200), (3, 0)],
    'early same-day reviews': [(3, 0), (3, -5), (3, 0), (3, -600), (4, -60)],
    'mixed': [(3, 0), (4, 0), (2, 1440), (1, 0), (1, 0), (3, 0), (4, 300), (2, 0)],
    'learning step reviewed days late': [(3, 0), (3, 2880), (3, 0)],
    'relearning reviewed days late': [(3, 0), (3, 0), (3, 0), (1, 0), (2, 4320), (3, 0)],
    'again on a late learning step': [(2, 0), (1, 1440), (4, 0)],
    'review card reviewed again the same day': [(4, 0), (3, sameDay), (1, sameDay), (3, 0)],
  };
  final retentions = [0.9, 0.8, 0.95];

  final cases = [];
  for (final retention in retentions) {
    final scheduler = buildScheduler(desiredRetention: retention);
    for (final MapEntry(key: name, value: steps) in sequences.entries) {
      var card = newCard(start);
      final reviews = [];
      for (final (rating, offsetMinutes) in steps) {
        final at = offsetMinutes == sameDay
            ? card.lastReview!.add(const Duration(hours: 1))
            : card.due.add(Duration(minutes: offsetMinutes));
        card = reviewCard(card, ReviewRating.fromValue(rating), at, scheduler: scheduler);
        reviews.add({
          'rating': rating,
          'at': at.millisecondsSinceEpoch,
          'state': card.state,
          'step': card.step,
          'stability': card.stability,
          'difficulty': card.difficulty,
          'due': card.due.millisecondsSinceEpoch,
          'retrievabilityAfterADay': retrievability(card, card.lastReview!.add(const Duration(days: 1))),
        });
      }
      cases.add({'name': name, 'retention': retention, 'start': start.millisecondsSinceEpoch, 'reviews': reviews});
    }
  }
  final intervals = [
    for (final ms in [1000, 59000, 90000, 600000, 3599000, 3600000, 5400000, 86399000, 86400000, 129600000, 2591999000, 2592000000, 31535999000, 31536000000, 47304000000, 315360000000, 400000000000])
      {'ms': ms, 'label': formatInterval(Duration(milliseconds: ms))},
  ];
  stdout.writeln(const JsonEncoder.withIndent(' ').convert({'cases': cases, 'intervals': intervals}));
}
