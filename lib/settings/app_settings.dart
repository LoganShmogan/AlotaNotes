/// Non-secret application settings (AI provider choice, model, question
/// format, FSRS target retention, study reminders). API keys are NOT stored here -- see auth/secure key storage in
/// the Account screen. Direct port of the Python desktop app's
/// `settings/app_settings.py`, stored as a JSON string in
/// `shared_preferences` instead of a keyring (nothing here is secret) --
/// which, unlike a file on disk, also works in the web build.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import '../core/scheduling.dart';

const defaultProvider = 'openai';
const defaultModel = 'gpt-4o-mini';
const defaultQuestionFormat = questionTypeShortAnswer;
const defaultReminderHour = 19;

class AppSettings {
  final String provider;
  final String model;
  final String? baseUrl;
  final String defaultQuestionFormat;
  final double desiredRetention;
  final bool remindersEnabled;
  final int reminderHour;
  final int reminderMinute;

  const AppSettings({
    this.provider = defaultProvider,
    this.model = defaultModel,
    this.baseUrl,
    this.defaultQuestionFormat = questionTypeShortAnswer,
    this.desiredRetention = defaultDesiredRetention,
    this.remindersEnabled = false,
    this.reminderHour = defaultReminderHour,
    this.reminderMinute = 0,
  });

  /// A null argument keeps the current value; [clearBaseUrl] is the only way
  /// to set [baseUrl] back to null.
  AppSettings copyWith({
    String? provider,
    String? model,
    String? baseUrl,
    bool clearBaseUrl = false,
    String? defaultQuestionFormat,
    double? desiredRetention,
    bool? remindersEnabled,
    int? reminderHour,
    int? reminderMinute,
  }) =>
      AppSettings(
        provider: provider ?? this.provider,
        model: model ?? this.model,
        baseUrl: clearBaseUrl ? null : baseUrl ?? this.baseUrl,
        defaultQuestionFormat: defaultQuestionFormat ?? this.defaultQuestionFormat,
        desiredRetention: desiredRetention ?? this.desiredRetention,
        remindersEnabled: remindersEnabled ?? this.remindersEnabled,
        reminderHour: reminderHour ?? this.reminderHour,
        reminderMinute: reminderMinute ?? this.reminderMinute,
      );

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'model': model,
        'base_url': baseUrl,
        'default_question_format': defaultQuestionFormat,
        'desired_retention': desiredRetention,
        'reminders_enabled': remindersEnabled,
        'reminder_hour': reminderHour,
        'reminder_minute': reminderMinute,
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
      desiredRetention: (data['desired_retention'] as num?)?.toDouble() ?? defaultDesiredRetention,
      remindersEnabled: data['reminders_enabled'] as bool? ?? false,
      reminderHour: data['reminder_hour'] as int? ?? defaultReminderHour,
      reminderMinute: data['reminder_minute'] as int? ?? 0,
    );
  }

  Future<void> save(AppSettings settings) async {
    await SharedPreferencesAsync().setString(_key, jsonEncode(settings.toJson()));
  }
}
