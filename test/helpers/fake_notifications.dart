// In-memory stand-ins for the notification plugin's platform side. The
// plugin picks its platform implementation by `defaultTargetPlatform` and
// the type of `FlutterLocalNotificationsPlatform.instance`, so a test sets
// both (see `useFakeNotifications`).
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:timezone/timezone.dart' as tz;

class FakeAndroidNotifications extends AndroidFlutterLocalNotificationsPlugin with MockPlatformInterfaceMixin {
  bool? permission = true;
  Object? failWith;
  int initializeCalls = 0;
  int cancelAllCalls = 0;
  final scheduled = <({int id, String? title, String? body, DateTime at, AndroidScheduleMode mode})>[];
  final shown = <({int id, String? title, String? body})>[];

  @override
  Future<bool> initialize({
    required AndroidInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback? onDidReceiveBackgroundNotificationResponse,
  }) async {
    initializeCalls++;
    return true;
  }

  @override
  Future<bool?> requestNotificationsPermission() async => permission;

  @override
  Future<void> cancelAll() async {
    if (failWith != null) throw failWith!;
    cancelAllCalls++;
    scheduled.clear();
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required tz.TZDateTime scheduledDate,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
    AndroidNotificationDetails? notificationDetails,
    AndroidScheduleMode scheduleMode = AndroidScheduleMode.exact,
  }) async {
    scheduled.add((id: id, title: title, body: body, at: DateTime.fromMillisecondsSinceEpoch(scheduledDate.millisecondsSinceEpoch), mode: scheduleMode));
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    AndroidNotificationDetails? notificationDetails,
    String? payload,
  }) async {
    shown.add((id: id, title: title, body: body));
  }
}

class FakeIOSNotifications extends IOSFlutterLocalNotificationsPlugin with MockPlatformInterfaceMixin {
  bool? permission = true;

  @override
  Future<bool?> initialize({
    required DarwinInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback? onDidReceiveBackgroundNotificationResponse,
  }) async =>
      true;

  @override
  Future<bool?> requestPermissions({
    bool sound = false,
    bool alert = false,
    bool badge = false,
    bool provisional = false,
    bool critical = false,
    bool carPlay = false,
    bool providesAppNotificationSettings = false,
  }) async =>
      permission;
}

class FakeMacOSNotifications extends MacOSFlutterLocalNotificationsPlugin with MockPlatformInterfaceMixin {
  bool? permission = true;

  @override
  Future<bool?> initialize({
    required DarwinInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async =>
      true;

  @override
  Future<bool?> requestPermissions({
    bool sound = false,
    bool alert = false,
    bool badge = false,
    bool provisional = false,
    bool critical = false,
    bool providesAppNotificationSettings = false,
  }) async =>
      permission;
}

/// Installs [fake] as the plugin's platform side and, in plain (non-widget)
/// tests, pretends to run on [platform] until the test ends. Widget tests
/// must leave [platform] null and use a `TargetPlatformVariant` instead:
/// they fail if the override is still set when the test body returns.
T useFakeNotifications<T extends FlutterLocalNotificationsPlatform>(T fake, [TargetPlatform? platform]) {
  FlutterLocalNotificationsPlatform.instance = fake;
  if (platform != null) {
    debugDefaultTargetPlatformOverride = platform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  }
  return fake;
}
