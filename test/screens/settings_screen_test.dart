import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizapp/core/models.dart';
import 'package:quizapp/screens/settings/settings_screen.dart';
import 'package:quizapp/settings/app_settings.dart';
import 'package:quizapp/storage/folders_repo.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/test_env.dart';

void main() {
  setUpTestEnv();
  const store = AppSettingsStore();
  late Database db;

  Future<void> show(WidgetTester tester) async {
    db = await openTestDatabase();
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(db: db)));
    await waitForLoad(tester);
  }

  String? selectedFormat(WidgetTester tester) =>
      // ignore: deprecated_member_use
      tester.widget<RadioListTile<String>>(find.byType(RadioListTile<String>).first).groupValue;

  testWidgets('defaults to short answer and shows reminders as coming soon', (tester) async {
    await tester.runAsync(() async {
      await show(tester);

      expect(selectedFormat(tester), questionTypeShortAnswer);
      expect(find.text('Quiz reminders'), findsOneWidget);
      expect(find.text('Coming soon — needs a real device to verify'), findsOneWidget);
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
