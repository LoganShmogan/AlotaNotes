/// Non-secret application settings (AI provider choice, model, question
/// format). API keys are NOT stored here -- see auth/secure key storage in
/// the Account screen. Direct port of the Python desktop app's
/// `settings/app_settings.py`, stored as a JSON string in
/// `shared_preferences` instead of a keyring (nothing here is secret) --
/// which, unlike a file on disk, also works in the web build.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';

const defaultProvider = 'openai';
const defaultModel = 'gpt-4o-mini';
const defaultQuestionFormat = questionTypeShortAnswer;

class AppSettings {
  final String provider;
  final String model;
  final String? baseUrl;
  final String defaultQuestionFormat;

  const AppSettings({
    this.provider = defaultProvider,
    this.model = defaultModel,
    this.baseUrl,
    this.defaultQuestionFormat = questionTypeShortAnswer,
  });

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'model': model,
        'base_url': baseUrl,
        'default_question_format': defaultQuestionFormat,
      };
}

class AppSettingsStore {
  static const _key = 'app_settings';

  const AppSettingsStore();

  Future<AppSettings> load() async {
    final raw = await SharedPreferencesAsync().getString(_key);
    if (raw == null) return const AppSettings();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return AppSettings(
      provider: data['provider'] as String? ?? defaultProvider,
      model: data['model'] as String? ?? defaultModel,
      baseUrl: data['base_url'] as String?,
      defaultQuestionFormat: data['default_question_format'] as String? ?? defaultQuestionFormat,
    );
  }

  Future<void> save(AppSettings settings) async {
    await SharedPreferencesAsync().setString(_key, jsonEncode(settings.toJson()));
  }
}
