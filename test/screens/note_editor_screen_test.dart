import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quillfin/ai/base.dart';
import 'package:quillfin/core/models.dart';
import 'package:quillfin/screens/notes/note_editor_screen.dart';
import 'package:quillfin/screens/notes/note_questions_screen.dart';
import 'package:quillfin/settings/app_settings.dart';
import 'package:quillfin/storage/folders_repo.dart';
import 'package:quillfin/storage/notes_repo.dart';
import 'package:quillfin/storage/questions_repo.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/test_env.dart';

/// Returns [questions] once [gate] completes (immediately if no gate), or
/// throws [error] if set.
class FakeProvider extends AIProvider {
  final List<GeneratedQuestion> questions;
  final AIProviderError? error;
  final Completer<void>? gate;

  FakeProvider({this.questions = const [], this.error, this.gate}) : super(apiKey: 'k', model: 'm');

  @override
  Future<List<GeneratedQuestion>> generateQuestions(
    String noteText, {
    int numQuestions = 5,
    String questionFormat = questionTypeShortAnswer,
    List<LinkedNoteContext>? linkedNotesContext,
  }) async {
    await gate?.future;
    if (error != null) throw error!;
    return questions;
  }
}

PlatformFile file(String name, String content) {
  final bytes = Uint8List.fromList(utf8.encode(content));
  return PlatformFile(name: name, size: bytes.length, bytes: bytes);
}

void main() {
  setUpTestEnv();

  late Database db;
  late NotesRepo notes;

  Future<int> createNote({String title = 'Waves', String body = 'Light is a wave.'}) async {
    db = await openTestDatabase();
    notes = NotesRepo(db);
    final folder = await FoldersRepo(db).create('Physics');
    return (await notes.create(folder.id, title, body)).id;
  }

  Future<void> show(WidgetTester tester, int noteId, {ProviderBuilder? providerBuilder}) async {
    await tester.pumpWidget(MaterialApp(
      home: providerBuilder == null
          ? NoteEditorScreen(db: db, noteId: noteId)
          : NoteEditorScreen(db: db, noteId: noteId, providerBuilder: providerBuilder),
    ));
    await waitForLoad(tester);
  }

  TextField field(WidgetTester tester, String label) => tester.widget<TextField>(
        find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label),
      );

  Future<void> expectSnackBar(WidgetTester tester, String text) =>
      pumpUntil(tester, () => find.text(text).evaluate().isNotEmpty);

  testWidgets('loads the note into the title and body fields', (tester) async {
    await tester.runAsync(() async {
      final id = await createNote();
      await show(tester, id);

      expect(field(tester, 'Title').controller!.text, 'Waves');
      expect(field(tester, 'Body').controller!.text, 'Light is a wave.');
    });
  });

  testWidgets('save writes the trimmed title and the body', (tester) async {
    await tester.runAsync(() async {
      final id = await createNote();
      await show(tester, id);

      await tester.enterText(find.widgetWithText(TextField, 'Waves'), '  Optics  ');
      await tester.enterText(find.widgetWithText(TextField, 'Light is a wave.'), 'Light bends.');
      await tester.tap(find.byIcon(Icons.save));
      await expectSnackBar(tester, 'Saved.');

      final saved = await notes.get(id);
      expect(saved.title, 'Optics');
      expect(saved.body, 'Light bends.');
    });
  });

  group('import file', () {
    Future<void> tapImport(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.file_upload_outlined));
      await tester.pump();
    }

    testWidgets('cancelled picker, or a file without bytes, changes nothing', (tester) async {
      await tester.runAsync(() async {
        final id = await createNote();
        await show(tester, id);

        filePicker.result = null;
        await tapImport(tester);
        filePicker.result = FilePickerResult([PlatformFile(name: 'x.txt', size: 0)]);
        await tapImport(tester);

        expect(filePicker.calls, 2);
        expect(field(tester, 'Body').controller!.text, 'Light is a wave.');
      });
    });

    testWidgets('replaces the body and keeps an existing title', (tester) async {
      await tester.runAsync(() async {
        final id = await createNote();
        await show(tester, id);

        filePicker.result = FilePickerResult([file('lecture.md', '# Imported')]);
        await tapImport(tester);
        await expectSnackBar(tester, 'Imported.');

        expect(field(tester, 'Body').controller!.text, '# Imported');
        expect(field(tester, 'Title').controller!.text, 'Waves');
      });
    });

    testWidgets('fills a blank title with the file name', (tester) async {
      await tester.runAsync(() async {
        final id = await createNote(title: '');
        await show(tester, id);

        filePicker.result = FilePickerResult([file('lecture.txt', 'text')]);
        await tapImport(tester);
        await expectSnackBar(tester, 'Imported.');

        expect(field(tester, 'Title').controller!.text, 'lecture.txt');
      });
    });

    testWidgets('reports an unsupported file type', (tester) async {
      await tester.runAsync(() async {
        final id = await createNote();
        await show(tester, id);

        filePicker.result = FilePickerResult([file('virus.exe', 'MZ')]);
        await tapImport(tester);
        await pumpUntil(tester, () => find.textContaining('Unsupported file: ').evaluate().isNotEmpty);
        expect(field(tester, 'Body').controller!.text, 'Light is a wave.');
      });
    });

    testWidgets('reports a file that fails to parse', (tester) async {
      await tester.runAsync(() async {
        final id = await createNote();
        await show(tester, id);

        filePicker.result = FilePickerResult([file('broken.docx', 'not a zip')]);
        await tapImport(tester);
        await pumpUntil(tester, () => find.textContaining('Import failed: ').evaluate().isNotEmpty);
      });
    });
  });

  group('generate questions', () {
    Future<void> saveKey(String key) => const FlutterSecureStorage().write(key: 'ai_api_key', value: key);

    testWidgets('without an API key, asks the user to add one', (tester) async {
      await tester.runAsync(() async {
        final id = await createNote();
        await show(tester, id);

        await tester.tap(find.text('Generate'));
        await expectSnackBar(
          tester,
          'Question generation failed: No API key configured. Add one in the Account tab.',
        );
      });
    });

    testWidgets('an empty saved key counts as no key', (tester) async {
      await tester.runAsync(() async {
        final id = await createNote();
        await saveKey('');
        await show(tester, id);

        await tester.tap(find.text('Generate'));
        await pumpUntil(tester, () => find.textContaining('No API key configured').evaluate().isNotEmpty);
      });
    });

    testWidgets('builds the provider from saved settings and stores what it returns', (tester) async {
      await tester.runAsync(() async {
        final id = await createNote();
        await saveKey('sk-test');
        await const AppSettingsStore().save(const AppSettings(
          provider: 'anthropic',
          model: 'claude-haiku-5-5',
          baseUrl: 'https://proxy.example.com',
          defaultQuestionFormat: questionTypeMultipleChoice,
        ));
        final gate = Completer<void>();
        final calls = <(String, String, String, String?)>[];
        await show(tester, id, providerBuilder: (name, key, model, baseUrl) {
          calls.add((name, key, model, baseUrl));
          return FakeProvider(gate: gate, questions: const [
            GeneratedQuestion(questionType: questionTypeShortAnswer, prompt: 'Q1', expectedAnswer: 'A1'),
            GeneratedQuestion(questionType: questionTypeShortAnswer, prompt: 'Q2', expectedAnswer: 'A2'),
          ]);
        });

        await tester.tap(find.text('Generate'));
        // While the provider is working, the button shows a spinner and is disabled.
        await pumpUntil(tester, () => find.byType(CircularProgressIndicator).evaluate().isNotEmpty);
        expect(tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);

        gate.complete();
        await expectSnackBar(tester, 'Generated 2 question(s).');
        expect(calls, [('anthropic', 'sk-test', 'claude-haiku-5-5', 'https://proxy.example.com')]);
        expect((await QuestionsRepo(db).listByNote(id)).map((q) => q.prompt), ['Q1', 'Q2']);
        expect(tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNotNull);
      });
    });

    testWidgets('provider errors are shown to the user', (tester) async {
      await tester.runAsync(() async {
        final id = await createNote();
        await saveKey('sk-test');
        await show(tester, id, providerBuilder: (_, _, _, _) => FakeProvider(error: const AIProviderError('HTTP 401')));

        await tester.tap(find.text('Generate'));
        await expectSnackBar(tester, 'Question generation failed: HTTP 401');
      });
    });
  });

  testWidgets('the questions button opens this note\'s questions', (tester) async {
    await tester.runAsync(() async {
      final id = await createNote();
      await show(tester, id);

      await tester.tap(find.byIcon(Icons.quiz_outlined));
      await settleNavigation(tester);

      expect(find.byType(NoteQuestionsScreen), findsOneWidget);
      expect(find.text('No questions generated yet.'), findsOneWidget);
    });
  });
}
