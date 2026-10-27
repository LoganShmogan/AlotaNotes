import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizapp/core/models.dart';
import 'package:quizapp/core/scheduling.dart';
import 'package:quizapp/screens/settings/settings_screen.dart';
import 'package:quizapp/services/reminder_service.dart';
import 'package:quizapp/settings/app_settings.dart';
import 'package:quizapp/storage/folders_repo.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/fake_notifications.dart';
import '../helpers/test_env.dart';

void main() {
  setUpTestEnv();
  const store = AppSettingsStore();
  late Database db;

  Future<void> show(WidgetTester tester, {ReminderDelivery delivery = ReminderDelivery.none}) async {
    db = await openTestDatabase();
    final reminders = ReminderService(delivery: delivery);
    addTearDown(reminders.dispose);
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(db: db, reminders: reminders)));
    await waitForLoad(tester);
  }

  SwitchListTile reminderSwitch(WidgetTester tester) => tester.widget<SwitchListTile>(find.byType(SwitchListTile));

  String? selectedFormat(WidgetTester tester) =>
      // ignore: deprecated_member_use
      tester.widget<RadioListTile<String>>(find.byType(RadioListTile<String>).first).groupValue;

  testWidgets('defaults: short answer, 90% recall, reminders unavailable where unsupported', (tester) async {
    await tester.runAsync(() async {
      await show(tester);

      expect(selectedFormat(tester), questionTypeShortAnswer);
      expect(find.text('Target recall: 90%'), findsOneWidget);
      expect(find.text('Not available here. The Today tab shows what is due.'), findsOneWidget);
      expect(reminderSwitch(tester).onChanged, isNull);
      expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Reminder time')).enabled, isFalse);
    });
  });

  testWidgets('dragging the recall slider saves the new target', (tester) async {
    await tester.runAsync(() async {
      await store.save(const AppSettings(model: 'kept'));
      await show(tester);

      await tester.drag(find.byType(Slider), const Offset(1000, 0));
      await pumpUntil(tester, () => find.text('Target recall: 97%').evaluate().isNotEmpty);
      await pumpUntil(tester, () => true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final saved = await store.load();
      expect(saved.desiredRetention, closeTo(maxDesiredRetention, 1e-9));
      expect(saved.model, 'kept');
    });
  });

  testWidgets('turning reminders on asks permission, saves, and schedules', (tester) async {
    await tester.runAsync(() async {
      final fake = useFakeNotifications(FakeAndroidNotifications());
      await show(tester, delivery: ReminderDelivery.scheduled);
      expect(find.text('A notification on days something is due, even with the app closed.'), findsOneWidget);
      // Something due, so there is something to schedule.
      await db.rawInsert("INSERT INTO problems (title, difficulty, fsrs_state, next_due_at, created_at, updated_at) "
          "VALUES ('P', 'easy', 2, '2020-01-01T00:00:00.000Z', '2020-01-01T00:00:00.000Z', '2020-01-01T00:00:00.000Z')");

      await tester.tap(find.byType(Switch));
      await pumpUntil(tester, () => reminderSwitch(tester).value);
      expect((await store.load()).remindersEnabled, isTrue);
      expect(fake.scheduled, isNotEmpty);

      await tester.tap(find.byType(Switch));
      await pumpUntil(tester, () => !reminderSwitch(tester).value);
      expect((await store.load()).remindersEnabled, isFalse);
      expect(fake.scheduled, isEmpty);
    });
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('denied notification permission leaves reminders off and says why', (tester) async {
    await tester.runAsync(() async {
      useFakeNotifications(FakeAndroidNotifications()..permission = false);
      await show(tester, delivery: ReminderDelivery.scheduled);

      await tester.tap(find.byType(Switch));
      await pumpUntil(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
      expect(find.textContaining('Notifications are blocked'), findsOneWidget);
      expect(reminderSwitch(tester).value, isFalse);
      expect((await store.load()).remindersEnabled, isFalse);
    });
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('the reminder time can be changed with the time picker', (tester) async {
    await tester.runAsync(() async {
      useFakeNotifications(FakeAndroidNotifications());
      await store.save(const AppSettings(remindersEnabled: true, reminderHour: 19));
      await show(tester, delivery: ReminderDelivery.whileOpen);
      expect(find.textContaining("this platform can't schedule"), findsOneWidget);
      expect(find.text('7:00 PM'), findsOneWidget);

      await tester.tap(find.text('Reminder time'));
      await pumpUntil(tester, () => find.text('OK').evaluate().isNotEmpty);
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pump();
      final fields = find.descendant(of: find.byType(Dialog), matching: find.byType(TextFormField));
      await tester.enterText(fields.at(0), '6');
      await tester.enterText(fields.at(1), '45');
      await tester.tap(find.text('OK'));
      await pumpUntil(tester, () => find.text('6:45 PM').evaluate().isNotEmpty);

      final saved = await store.load();
      expect((saved.reminderHour, saved.reminderMinute), (18, 45));
    });
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('cancelling the time picker changes nothing', (tester) async {
    await tester.runAsync(() async {
      await store.save(const AppSettings(remindersEnabled: true));
      await show(tester, delivery: ReminderDelivery.whileOpen);

      await tester.tap(find.text('Reminder time'));
      await pumpUntil(tester, () => find.text('Cancel').evaluate().isNotEmpty);
      await tester.tap(find.text('Cancel'));
      await pumpUntil(tester, () => find.text('Cancel').evaluate().isEmpty);
      expect((await store.load()).reminderHour, defaultReminderHour);
    });
  });

  testWidgets('shows the saved default format', (tester) async {
    await tester.runAsync(() async {
      await store.save(const AppSettings(defaultQuestionFormat: questionTypeMultipleChoice));
      await show(tester);

      expect(selectedFormat(tester), questionTypeMultipleChoice);
    });
  });

  testWidgets('changing the format saves it without touching AI settings', (tester) async {
    await tester.runAsync(() async {
      await store.save(const AppSettings(provider: 'anthropic', model: 'claude-haiku-5-5', baseUrl: 'u'));
      await show(tester);

      await tester.scrollUntilVisible(find.text('Multiple choice'), 200);
      await tester.tap(find.text('Multiple choice'));
      await pumpUntil(tester, () => selectedFormat(tester) == questionTypeMultipleChoice);
      var saved = await store.load();
      expect(saved.defaultQuestionFormat, questionTypeMultipleChoice);
      expect((saved.provider, saved.model, saved.baseUrl), ('anthropic', 'claude-haiku-5-5', 'u'));

      await tester.tap(find.text('Short answer'));
      await pumpUntil(tester, () => selectedFormat(tester) == questionTypeShortAnswer);
      saved = await store.load();
      expect(saved.defaultQuestionFormat, questionTypeShortAnswer);
    });
  });

  testWidgets('export shares one named JSON file with all the data', (tester) async {
    await tester.runAsync(() async {
      await show(tester);
      await FoldersRepo(db).create('Physics');

      await tester.scrollUntilVisible(find.text('Export all data'), 200);
      await tester.tap(find.text('Export all data'));
      await pumpUntil(tester, () => sharePlatform.sharedFiles.isNotEmpty);
      await waitForLoad(tester);

      expect(sharePlatform.lastFileNameOverrides!.single, startsWith('quizapp-export-'));
      final json = jsonDecode(utf8.decode(await sharePlatform.sharedFiles.single.readAsBytes()));
      expect((json['folders'] as List).single['name'], 'Physics');
      expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    });
  });
}
