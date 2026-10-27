import 'package:flutter_test/flutter_test.dart';
import 'package:quizapp/core/models.dart';
import 'package:quizapp/core/scheduling.dart';
import 'package:quizapp/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_env.dart';

void main() {
  setUpTestEnv();
  // Stateless (everything lives in shared_preferences), so any instance
  // sees the same data; deliberately not const, so it is built at runtime.
  final store = AppSettingsStore();

  test('load returns defaults when nothing has been saved', () async {
    final settings = await store.load();
    expect(settings.provider, defaultProvider);
    expect(settings.model, defaultModel);
    expect(settings.baseUrl, isNull);
    expect(settings.defaultQuestionFormat, questionTypeShortAnswer);
    expect(settings.desiredRetention, defaultDesiredRetention);
    expect((settings.remindersEnabled, settings.reminderHour, settings.reminderMinute), (false, defaultReminderHour, 0));
  });

  test('save then load round-trips every field', () async {
    await store.save(const AppSettings(
      provider: 'anthropic',
      model: 'claude-haiku-5-5',
      baseUrl: 'https://proxy.example.com',
      defaultQuestionFormat: questionTypeMultipleChoice,
      desiredRetention: 0.85,
      remindersEnabled: true,
      reminderHour: 7,
      reminderMinute: 45,
    ));

    final settings = await store.load();
    expect(settings.desiredRetention, 0.85);
    expect((settings.remindersEnabled, settings.reminderHour, settings.reminderMinute), (true, 7, 45));
    expect(settings.provider, 'anthropic');
    expect(settings.model, 'claude-haiku-5-5');
    expect(settings.baseUrl, 'https://proxy.example.com');
    expect(settings.defaultQuestionFormat, questionTypeMultipleChoice);
  });

  test('missing keys in stored JSON fall back to defaults', () async {
    await SharedPreferencesAsync().setString('app_settings', '{"model": "llama3"}');

    final settings = await store.load();
    expect(settings.provider, defaultProvider);
    expect(settings.model, 'llama3');
    expect(settings.defaultQuestionFormat, defaultQuestionFormat);
  });

  test('toJson uses the snake_case keys the store reads back', () {
    expect(const AppSettings(baseUrl: 'u').toJson(), {
      'provider': defaultProvider,
      'model': defaultModel,
      'base_url': 'u',
      'default_question_format': questionTypeShortAnswer,
      'desired_retention': defaultDesiredRetention,
      'reminders_enabled': false,
      'reminder_hour': defaultReminderHour,
      'reminder_minute': 0,
    });
  });

  test('copyWith changes only what is passed; clearBaseUrl drops the override', () {
    const base = AppSettings(provider: 'anthropic', baseUrl: 'u', reminderHour: 8);
    final changed = base.copyWith(model: 'm', remindersEnabled: true, desiredRetention: 0.8);
    expect((changed.provider, changed.model, changed.baseUrl, changed.reminderHour), ('anthropic', 'm', 'u', 8));
    expect((changed.remindersEnabled, changed.desiredRetention), (true, 0.8));
    expect(changed.copyWith().toJson(), changed.toJson());

    final cleared = base.copyWith(clearBaseUrl: true);
    expect(cleared.baseUrl, isNull);
    expect(base.copyWith(baseUrl: 'v', defaultQuestionFormat: questionTypeMultipleChoice, reminderMinute: 5, provider: 'openai').toJson(),
        containsPair('base_url', 'v'));
  });
}
