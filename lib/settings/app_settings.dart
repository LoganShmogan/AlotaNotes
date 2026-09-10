/// Non-secret application settings (AI provider choice, model, question
/// format). API keys are NOT stored here -- see auth/secure key storage in
/// the Account screen. Direct port of the Python desktop app's
/// `settings/app_settings.py`, using a plain JSON file instead of a keyring
/// (nothing here is secret).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  final Future<File> Function()? _fileProvider;

  // Can't use an initializing formal (`this._fileProvider`) here -- that
  // would make the named constructor parameter private too, so tests
  // outside this file couldn't pass `fileProvider:` at all.
  // ignore: prefer_initializing_formals
  const AppSettingsStore({Future<File> Function()? fileProvider}) : _fileProvider = fileProvider;

  Future<File> _file() async {
    if (_fileProvider != null) return _fileProvider();
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, 'settings.json'));
  }

  Future<AppSettings> load() async {
    final file = await _file();
    if (!await file.exists()) return const AppSettings();
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return AppSettings(
      provider: data['provider'] as String? ?? defaultProvider,
      model: data['model'] as String? ?? defaultModel,
      baseUrl: data['base_url'] as String?,
      defaultQuestionFormat: data['default_question_format'] as String? ?? defaultQuestionFormat,
    );
  }

  Future<void> save(AppSettings settings) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings.toJson()));
  }
}
