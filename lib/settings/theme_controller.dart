import 'package:flutter/material.dart';

import 'app_settings.dart';

/// The app's light/dark/system choice, saved in [AppSettings.themeMode].
/// [QuillFinApp] rebuilds its `MaterialApp` whenever this changes; screens
/// reach it through [ThemeControllerScope].
class ThemeController extends ValueNotifier<ThemeMode> {
  final AppSettingsStore store;
  ThemeController({this.store = const AppSettingsStore()}) : super(ThemeMode.system);

  static ThemeMode parse(String value) => switch (value) {
        themeModeLight => ThemeMode.light,
        themeModeDark => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String encode(ThemeMode mode) => switch (mode) {
        ThemeMode.light => themeModeLight,
        ThemeMode.dark => themeModeDark,
        ThemeMode.system => themeModeSystem,
      };

  Future<void> load() async => value = parse((await store.load()).themeMode);

  Future<void> set(ThemeMode mode) async {
    value = mode;
    await store.save((await store.load()).copyWith(themeMode: encode(mode)));
  }
}

class ThemeControllerScope extends InheritedNotifier<ThemeController> {
  const ThemeControllerScope({super.key, required ThemeController controller, required super.child})
      : super(notifier: controller);

  static ThemeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeControllerScope>()?.notifier;
}
