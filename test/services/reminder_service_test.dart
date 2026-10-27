import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizapp/core/models.dart';
import 'package:quizapp/services/reminder_service.dart';
import 'package:quizapp/settings/app_settings.dart';
import 'package:quizapp/storage/folders_repo.dart';
import 'package:quizapp/storage/notes_repo.dart';
import 'package:quizapp/storage/problems_repo.dart';
import 'package:quizapp/storage/questions_repo.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/fake_notifications.dart';
import '../helpers/test_env.dart';

void main() {
  setUpTestEnv();
  const store = AppSettingsStore();
  late Database db;
  // Local noon; reminders at 19:00.
  final now = DateTime(2026, 3, 10, 12);

  setUp(() async {
    db = await openTestDatabase();
  });

  Future<void> enableReminders() => store.save(const AppSettings(remindersEnabled: true, reminderHour: 19));

  Future<void> addQuestionDue(DateTime localDue) async {
    final folder = await FoldersRepo(db).create('F');
    final note = await NotesRepo(db).create(folder.id, 'N', '');
    await QuestionsRepo(db).create(note.id, questionTypeShortAnswer, 'Q', 'A', now: localDue.toUtc());
  }

  ReminderService service(ReminderDelivery delivery, {DateTime? at}) =>
      ReminderService(delivery: delivery, clock: () => at ?? now);

  group('reminderDeliveryFor', () {
    test('web never notifies', () => expect(reminderDeliveryFor(isWeb: true), ReminderDelivery.none));
    for (final (platform, delivery) in [
      (TargetPlatform.android, ReminderDelivery.scheduled),
      (TargetPlatform.iOS, ReminderDelivery.scheduled),
      (TargetPlatform.macOS, ReminderDelivery.scheduled),
      (TargetPlatform.linux, ReminderDelivery.whileOpen),
      (TargetPlatform.windows, ReminderDelivery.whileOpen),
      (TargetPlatform.fuchsia, ReminderDelivery.none),
    ]) {
      test('$platform -> $delivery', () => expect(reminderDeliveryFor(isWeb: false, platform: platform), delivery));
    }
    test('defaults to the current platform', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(reminderDeliveryFor(), ReminderDelivery.scheduled);
      expect(ReminderService().delivery, ReminderDelivery.scheduled);
    });
  });

  group('scheduled delivery', () {
    late FakeAndroidNotifications fake;
    setUp(() => fake = useFakeNotifications(FakeAndroidNotifications(), TargetPlatform.android));

    test('plans one notification per upcoming day with something due', () async {
      await enableReminders();
      await addQuestionDue(DateTime(2026, 3, 10, 9)); // due today
      await addQuestionDue(DateTime(2026, 3, 12, 9)); // due in two days
      final reminders = service(ReminderDelivery.scheduled);

      await reminders.sync(db);
      expect(fake.initializeCalls, 1);
      expect(fake.cancelAllCalls, 1);
      expect(fake.scheduled.map((n) => (n.id, n.at, n.body)).take(3), [
        (100, DateTime(2026, 3, 10, 19), '1 item is ready to review.'),
        (101, DateTime(2026, 3, 11, 19), '1 item is ready to review.'),
        (102, DateTime(2026, 3, 12, 19), '2 items are ready to review.'),
      ]);
      expect(fake.scheduled, hasLength(7));
      expect(fake.scheduled.every((n) => n.title == 'Time to study'), isTrue);
      expect(fake.scheduled.first.mode, AndroidScheduleMode.inexactAllowWhileIdle);

      // Re-syncing replaces the plan rather than adding to it, and only
      // initializes the plugin once.
      await reminders.sync(db);
      expect((fake.initializeCalls, fake.cancelAllCalls, fake.scheduled.length), (1, 2, 7));
    });

    test('counts attempted problems, not untried ones', () async {
      await enableReminders();
      final problems = ProblemsRepo(db);
      await problems.create('Untried');
      final tried = await problems.create('Tried');
      await problems.recordAttempt(tried.id,
          solved: true, rating: ReviewRating.good, after: SrsCard(state: srsStateReview, due: now.toUtc()));

      await service(ReminderDelivery.scheduled).sync(db);
      expect(fake.scheduled.first.body, '1 item is ready to review.');
    });

    test('disabled reminders cancel everything and schedule nothing', () async {
      await addQuestionDue(DateTime(2026, 3, 10, 9));
      await service(ReminderDelivery.scheduled).sync(db);
      expect(fake.cancelAllCalls, 1);
      expect(fake.scheduled, isEmpty);
    });

    test('requestPermission asks Android', () async {
      final reminders = service(ReminderDelivery.scheduled);
      expect(await reminders.requestPermission(), isTrue);
      fake.permission = false;
      expect(await reminders.requestPermission(), isFalse);
      fake.permission = null;
      expect(await reminders.requestPermission(), isFalse);
    });

    test('trySync logs a plugin failure instead of throwing', () async {
      fake.failWith = Exception('plugin exploded');
      final logged = <String?>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) => logged.add(message);
      addTearDown(() => debugPrint = original);

      await service(ReminderDelivery.scheduled).trySync(db);
      expect(logged.single, contains('plugin exploded'));
    });
  });

  test('requestPermission asks iOS and macOS', () async {
    final ios = useFakeNotifications(FakeIOSNotifications(), TargetPlatform.iOS);
    expect(await service(ReminderDelivery.scheduled).requestPermission(), isTrue);
    ios.permission = null;
    expect(await service(ReminderDelivery.scheduled).requestPermission(), isFalse);

    final mac = useFakeNotifications(FakeMacOSNotifications(), TargetPlatform.macOS);
    expect(await service(ReminderDelivery.scheduled).requestPermission(), isTrue);
    mac.permission = null;
    expect(await service(ReminderDelivery.scheduled).requestPermission(), isFalse);
  });

  group('while-open delivery', () {
    // The Android fake stands in for the desktop plugin: only `show` is used.
    late FakeAndroidNotifications fake;
    setUp(() => fake = useFakeNotifications(FakeAndroidNotifications(), TargetPlatform.android));

    test('shows once the reminder time has passed, then not again that day', () async {
      await enableReminders();
      await addQuestionDue(DateTime(2026, 3, 10, 9));
      final evening = DateTime(2026, 3, 10, 20);

      final reminders = service(ReminderDelivery.whileOpen, at: evening);
      addTearDown(reminders.dispose);
      await reminders.sync(db);
      expect(fake.shown.map((n) => (n.id, n.body)), [(1, '1 item is ready to review.')]);
      expect(fake.cancelAllCalls, 0); // never cancels: unsupported on unpackaged Windows
      expect(await SharedPreferencesAsync().getString('reminder_last_shown_day'), '2026-03-10');

      await reminders.sync(db);
      expect(fake.shown, hasLength(1));
    });

    test('waits for the reminder time, then shows when it comes round', () async {
      await enableReminders();
      await addQuestionDue(DateTime(2026, 3, 10, 9));
      var clock = DateTime(2026, 3, 10, 18, 59, 59, 900);
      final reminders = ReminderService(delivery: ReminderDelivery.whileOpen, clock: () => clock);
      addTearDown(reminders.dispose);

      await reminders.sync(db);
      expect(fake.shown, isEmpty);

      clock = DateTime(2026, 3, 10, 19);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(fake.shown, hasLength(1));
    });

    test('nothing due, nothing shown', () async {
      await enableReminders();
      final reminders = service(ReminderDelivery.whileOpen, at: DateTime(2026, 3, 10, 20));
      addTearDown(reminders.dispose);
      await reminders.sync(db);
      expect(fake.shown, isEmpty);
    });

    test('desktop platforms grant permission without asking', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(await service(ReminderDelivery.whileOpen).requestPermission(), isTrue);
    });
  });

  test('unsupported platforms do nothing and report no permission', () async {
    final reminders = service(ReminderDelivery.none);
    expect(reminders.supported, isFalse);
    expect(await reminders.requestPermission(), isFalse);
    await enableReminders();
    await reminders.sync(db); // no plugin installed: would throw if it were touched
  });
}
