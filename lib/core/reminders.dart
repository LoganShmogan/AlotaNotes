/// When to remind the user to study, and what to say. Pure, like
/// scheduling.dart: every time is passed in, in local time.
///
/// Reminders fire at one chosen time of day. Rather than one repeating
/// "time to study!" alarm, each of the next few days gets its own one-shot
/// reminder carrying how many items will be due by then, assuming nothing
/// is reviewed in between, and days with nothing due get none. Re-planning
/// after every review (ReminderService.sync) keeps the counts honest.
library;

class PlannedReminder {
  final DateTime at;
  final int dueCount;
  const PlannedReminder(this.at, this.dueCount);
}

/// How many days ahead to plan. Opening the app at least once a week keeps
/// reminders flowing.
const reminderPlanDays = 7;

/// Today's reminder time, or tomorrow's if today's has already passed.
DateTime nextReminderTime(DateTime now, int hour, int minute) {
  final today = DateTime(now.year, now.month, now.day, hour, minute);
  return today.isAfter(now) ? today : DateTime(now.year, now.month, now.day + 1, hour, minute);
}

List<PlannedReminder> planReminders({
  required DateTime now,
  required int hour,
  required int minute,
  required List<DateTime> dueTimes,
  int days = reminderPlanDays,
}) {
  final first = nextReminderTime(now, hour, minute);
  final plan = <PlannedReminder>[];
  for (var i = 0; i < days; i++) {
    // Built from date parts, not `add(Duration(days: i))`, so a DST change
    // doesn't shift the hour.
    final at = DateTime(first.year, first.month, first.day + i, hour, minute);
    final count = dueTimes.where((due) => !due.isAfter(at)).length;
    if (count > 0) plan.add(PlannedReminder(at, count));
  }
  return plan;
}

const reminderTitle = 'Time to study';

String reminderBody(int dueCount) =>
    dueCount == 1 ? '1 item is ready to review.' : '$dueCount items are ready to review.';

/// Calendar-day key (yyyy-mm-dd) for remembering that today's reminder was
/// already shown.
String dayKey(DateTime local) =>
    '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';

/// For platforms that can't schedule a notification ahead of time: should
/// today's reminder be shown now? Yes once today's reminder time has passed,
/// if something is due and it hasn't been shown today already.
bool shouldShowNow({
  required DateTime now,
  required int hour,
  required int minute,
  required int dueCount,
  String? lastShownDay,
}) {
  final todayAt = DateTime(now.year, now.month, now.day, hour, minute);
  return dueCount > 0 && !now.isBefore(todayAt) && lastShownDay != dayKey(now);
}
