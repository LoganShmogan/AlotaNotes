import 'package:flutter_test/flutter_test.dart';
import 'package:quizapp/core/models.dart';
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
  });

  test('save then load round-trips every field', () async {
    await store.save(const AppSettings(
      provider: 'anthropic',
      model: 'claude-haiku-5-5',
      baseUrl: 'https://proxy.example.com',
      defaultQuestionFormat: questionTypeMultipleChoice,
    ));

    final settings = await store.load();
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
    });
  });
}
