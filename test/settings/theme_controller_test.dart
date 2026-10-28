import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quillfin/settings/app_settings.dart';
import 'package:quillfin/settings/theme_controller.dart';

import '../helpers/test_env.dart';

void main() {
  setUpTestEnv();

  test('parse and encode round-trip, unknown values meaning system', () {
    for (final mode in ThemeMode.values) {
      expect(ThemeController.parse(ThemeController.encode(mode)), mode);
    }
    expect(ThemeController.parse('purple'), ThemeMode.system);
  });

  test('load reads the saved mode; set saves it without touching other settings', () async {
    const store = AppSettingsStore();
    await store.save(const AppSettings(model: 'kept', themeMode: themeModeDark));
    final controller = ThemeController();
    expect(controller.value, ThemeMode.system);
    await controller.load();
    expect(controller.value, ThemeMode.dark);

    await controller.set(ThemeMode.light);
    expect(controller.value, ThemeMode.light);
    final saved = await store.load();
    expect((saved.themeMode, saved.model), (themeModeLight, 'kept'));
  });
}
