/// Study reminders as system notifications, planned by core/reminders.dart.
///
/// Delivery depends on what the platform can do (see [reminderDeliveryFor]):
/// - Android/iOS/macOS schedule each reminder with the OS, so it arrives
///   even when the app is closed.
/// - Linux has no scheduling API, and Windows can't cancel a scheduled
///   notification unless the app is MSIX-packaged (so re-planning would
///   pile up duplicates). Both show the reminder themselves while the app is
///   open: at launch if today's time has passed, or when it comes round.
/// - Web gets no notifications; the Today tab's due count is the reminder.
///
/// Delivery has only been verified in tests against a fake plugin, not on
/// real devices -- see Docs/future_work.md.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/reminders.dart';
import '../settings/app_settings.dart';
import '../storage/db.dart';

enum ReminderDelivery { scheduled, whileOpen, none }

ReminderDelivery reminderDeliveryFor({bool isWeb = kIsWeb, TargetPlatform? platform}) {
  if (isWeb) return ReminderDelivery.none;
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.macOS => ReminderDelivery.scheduled,
    TargetPlatform.linux || TargetPlatform.windows => ReminderDelivery.whileOpen,
    TargetPlatform.fuchsia => ReminderDelivery.none,
  };
}

// Scheduled reminders use ids 100..106; the while-open one uses 1.
const _scheduledIdBase = 100;
const _whileOpenId = 1;
const _lastShownKey = 'reminder_last_shown_day';

const _details = NotificationDetails(
  android: AndroidNotificationDetails(
    'study_reminders',
    'Study reminders',
    channelDescription: 'A daily nudge when quiz questions or problems are due',
  ),
  iOS: DarwinNotificationDetails(),
  macOS: DarwinNotificationDetails(),
);

class ReminderService {
  final FlutterLocalNotificationsPlugin _plugin;
  final ReminderDelivery delivery;
  final AppSettingsStore settingsStore;
  final DateTime Function() _clock;
  Future<void>? _initialized;
  Timer? _timer;

  ReminderService({
    FlutterLocalNotificationsPlugin? plugin,
    ReminderDelivery? delivery,
    this.settingsStore = const AppSettingsStore(),
    DateTime Function()? clock,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        delivery = delivery ?? reminderDeliveryFor(),
        _clock = clock ?? DateTime.now;

  bool get supported => delivery != ReminderDelivery.none;

  Future<void> _init() => _initialized ??= _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          linux: LinuxInitializationSettings(defaultActionName: 'Open'),
          windows: WindowsInitializationSettings(
            appName: 'Quiz App AI',
            appUserModelId: 'SavePoint.QuizAppAI',
            guid: '6f0f3c1e-4b9e-4a57-9a43-2f1d7c6b8e21',
          ),
        ),
      );

  /// Asks the OS for permission to notify (Android 13+, iOS, macOS).
  /// Desktop platforms don't ask, so they always report true.
  Future<bool> requestPermission() async {
    if (!supported) return false;
    await _init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    final macos = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
    if (macos != null) return await macos.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    return true;
  }

  /// Everything that will come due, now or later: active questions and
  /// problems that have been attempted at least once.
  Future<List<DateTime>> _dueTimes(Database db) async {
    final rows = await db.rawQuery('''
      SELECT next_due_at FROM questions WHERE active = 1
      UNION ALL
      SELECT next_due_at FROM problems WHERE next_due_at IS NOT NULL
    ''');
    return [for (final row in rows) isoToDt(row['next_due_at'] as String).toLocal()];
  }

  /// Re-plans reminders from the current settings and what's due. Call on
  /// launch, after any review, and whenever reminder settings change.
  Future<void> sync(Database db) async {
    if (!supported) return;
    _timer?.cancel();
    final settings = await settingsStore.load();
    await _init();
    if (delivery == ReminderDelivery.scheduled) await _plugin.cancelAll();
    if (!settings.remindersEnabled) return;

    final now = _clock();
    final dueTimes = await _dueTimes(db);
    if (delivery == ReminderDelivery.scheduled) {
      final plan = planReminders(
        now: now,
        hour: settings.reminderHour,
        minute: settings.reminderMinute,
        dueTimes: dueTimes,
      );
      for (var i = 0; i < plan.length; i++) {
        await _plugin.zonedSchedule(
          id: _scheduledIdBase + i,
          title: reminderTitle,
          body: reminderBody(plan[i].dueCount),
          scheduledDate: tz.TZDateTime.from(plan[i].at, tz.UTC),
          notificationDetails: _details,
          // Inexact: no exact-alarm permission needed, and a study nudge
          // arriving a few minutes late is fine.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
      return;
    }

    final prefs = SharedPreferencesAsync();
    final dueNow = dueTimes.where((due) => !due.isAfter(now)).length;
    if (shouldShowNow(
      now: now,
      hour: settings.reminderHour,
      minute: settings.reminderMinute,
      dueCount: dueNow,
      lastShownDay: await prefs.getString(_lastShownKey),
    )) {
      await _plugin.show(id: _whileOpenId, title: reminderTitle, body: reminderBody(dueNow));
      await prefs.setString(_lastShownKey, dayKey(now));
    }
    // Check again when the next reminder time comes round, if still open.
    final next = nextReminderTime(now, settings.reminderHour, settings.reminderMinute);
    _timer = Timer(next.difference(now), () => sync(db));
  }

  /// [sync], but a notification failure is logged rather than thrown: a
  /// missed reminder shouldn't break the review that triggered it.
  Future<void> trySync(Database db) async {
    try {
      await sync(db);
    } catch (e) {
      debugPrint('Reminder sync failed: $e');
    }
  }

  void dispose() => _timer?.cancel();
}
