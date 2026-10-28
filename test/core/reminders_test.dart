import 'package:flutter_test/flutter_test.dart';
import 'package:quillfin/core/reminders.dart';

void main() {
  group('nextReminderTime', () {
    test('later today if the time has not passed yet', () {
      expect(nextReminderTime(DateTime(2026, 3, 10, 8), 19, 30), DateTime(2026, 3, 10, 19, 30));
    });

    test('tomorrow once it has passed, or exactly now', () {
      expect(nextReminderTime(DateTime(2026, 3, 10, 20), 19, 30), DateTime(2026, 3, 11, 19, 30));
      expect(nextReminderTime(DateTime(2026, 3, 10, 19, 30), 19, 30), DateTime(2026, 3, 11, 19, 30));
    });

    test('rolls over month ends', () {
      expect(nextReminderTime(DateTime(2026, 3, 31, 23), 7, 0), DateTime(2026, 4, 1, 7));
    });
  });

  group('planReminders', () {
    final now = DateTime(2026, 3, 10, 12);

    test('one reminder per day with items due by then, counting cumulatively', () {
      final plan = planReminders(
        now: now,
        hour: 19,
        minute: 0,
        dueTimes: [
          DateTime(2026, 3, 9), // already overdue
          DateTime(2026, 3, 10, 18),
          DateTime(2026, 3, 12, 9),
          DateTime(2026, 3, 30), // beyond the plan
        ],
      );
      expect(plan.map((r) => (r.at, r.dueCount)), [
        (DateTime(2026, 3, 10, 19), 2),
        (DateTime(2026, 3, 11, 19), 2),
        (DateTime(2026, 3, 12, 19), 3),
        (DateTime(2026, 3, 13, 19), 3),
        (DateTime(2026, 3, 14, 19), 3),
        (DateTime(2026, 3, 15, 19), 3),
        (DateTime(2026, 3, 16, 19), 3),
      ]);
    });

    test('skips days with nothing due, and an empty queue plans nothing', () {
      final plan = planReminders(now: now, hour: 19, minute: 0, dueTimes: [DateTime(2026, 3, 15, 8)], days: 7);
      expect(plan.map((r) => r.at.day), [15, 16]);
      expect(planReminders(now: now, hour: 19, minute: 0, dueTimes: []), isEmpty);
    });

    test('an item due exactly at reminder time counts', () {
      final plan = planReminders(now: now, hour: 19, minute: 0, dueTimes: [DateTime(2026, 3, 10, 19)], days: 1);
      expect(plan.single.dueCount, 1);
    });
  });

  test('reminderBody pluralises', () {
    expect(reminderBody(1), '1 item is ready to review.');
    expect(reminderBody(4), '4 items are ready to review.');
  });

  test('dayKey is zero-padded yyyy-mm-dd', () {
    expect(dayKey(DateTime(2026, 3, 5, 23)), '2026-03-05');
  });

  group('shouldShowNow', () {
    bool check({required DateTime now, int due = 2, String? last}) =>
        shouldShowNow(now: now, hour: 19, minute: 0, dueCount: due, lastShownDay: last);

    test('not before the reminder time', () => expect(check(now: DateTime(2026, 3, 10, 18, 59)), isFalse));
    test('at or after it', () {
      expect(check(now: DateTime(2026, 3, 10, 19)), isTrue);
      expect(check(now: DateTime(2026, 3, 10, 23)), isTrue);
    });
    test('not with nothing due', () => expect(check(now: DateTime(2026, 3, 10, 20), due: 0), isFalse));
    test('not twice in a day', () {
      expect(check(now: DateTime(2026, 3, 10, 20), last: '2026-03-10'), isFalse);
      expect(check(now: DateTime(2026, 3, 10, 20), last: '2026-03-09'), isTrue);
    });
  });
}
