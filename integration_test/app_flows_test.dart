// End-to-end run of the real app on a real device (built for and run on
// Linux desktop; see Docs/testing.md). Unlike test/, nothing here fakes
// SQLite, shared_preferences, secure storage or HTTP: the app opens a real
// database file, saves settings and the API key through the real platform
// plugins, and generates questions over real HTTP.
//
// Only three things are swapped out, each for a reason:
// - path_provider points at a temp dir, so the app's database never lands
//   in (or clobbers) your real one.
// - The file picker and share sheet are native OS dialogs a test can't
//   click through, so they're faked at their platform interface.
// - The AI provider is a local HTTP server speaking the OpenAI Chat
//   Completions format, so no real API key or network is needed.
//
// The settings and API key this test writes go to the real per-user stores;
// whatever was there before is put back afterwards.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:quillfin/main.dart' as app;
import 'package:quillfin/storage/db.dart';

const _apiKeyStorageKey = 'ai_api_key';
const _settingsKey = 'app_settings';
const _fakeApiKey = 'integration-test-key';

class _TempPathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String documentsPath;
  _TempPathProvider(this.documentsPath);

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

class _FakeFilePicker extends FilePicker with MockPlatformInterfaceMixin {
  FilePickerResult? result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      result;
}

class _FakeSharePlatform extends SharePlatform with MockPlatformInterfaceMixin {
  final List<XFile> sharedFiles = [];

  @override
  Future<ShareResult> shareXFiles(
    List<XFile> files, {
    String? subject,
    String? text,
    Rect? sharePositionOrigin,
    List<String>? fileNameOverrides,
  }) async {
    sharedFiles.addAll(files);
    return const ShareResult('', ShareResultStatus.success);
  }
}

/// A local stand-in for an OpenAI-compatible endpoint. Records every
/// request and answers with one short-answer and one multiple-choice
/// question.
class _FakeAiServer {
  late final HttpServer _server;
  final List<({String? auth, Map<String, dynamic> body})> requests = [];

  String get baseUrl => 'http://${_server.address.host}:${_server.port}/v1';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      final body = jsonDecode(await utf8.decodeStream(request)) as Map<String, dynamic>;
      requests.add((auth: request.headers.value('authorization'), body: body));
      final content = jsonEncode({
        'questions': [
          {'prompt': 'What is the capital of France?', 'expected_answer': 'Paris'},
          {
            'prompt': 'Which planet is largest?',
            'expected_answer': 'Jupiter',
            'choices': ['Mars', 'Jupiter', 'Venus'],
            'correct_choice_index': 1,
          },
        ],
      });
      request.response
        ..statusCode = request.uri.path == '/v1/chat/completions' ? 200 : 404
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': content},
            },
          ],
        }));
      await request.response.close();
    });
  }

  Future<void> stop() => _server.close(force: true);
}

/// Pumps frames with real delays until [condition] holds. `pumpAndSettle`
/// can't be used while an indeterminate spinner is on screen.
Future<void> pumpUntil(WidgetTester tester, bool Function() condition, {String? reason}) async {
  for (var i = 0; i < 300; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TestFailure('Timed out waiting for: ${reason ?? 'condition'}');
}

Future<void> waitFor(WidgetTester tester, Finder finder) =>
    pumpUntil(tester, () => finder.evaluate().isNotEmpty, reason: finder.toString());

Future<void> waitForGone(WidgetTester tester, Finder finder) =>
    pumpUntil(tester, () => finder.evaluate().isEmpty, reason: 'gone: ${finder.toString()}');

/// Taps [finder] and lets the resulting frame(s) run.
Future<void> tap(WidgetTester tester, Finder finder) async {
  await waitFor(tester, finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 16));
}

Future<void> enterText(WidgetTester tester, Finder field, String text) async {
  await waitFor(tester, field);
  await tester.enterText(field, text);
  await tester.pump();
}

Finder field(String label) => find.widgetWithText(TextField, label);

Finder navTab(String label) => find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Future<void> goBack(WidgetTester tester) async {
  await tap(tester, find.byTooltip('Back'));
  await tester.pumpAndSettle();
}

Future<void> dismissSnackBars(WidgetTester tester) async {
  ScaffoldMessenger.of(tester.element(find.byType(Scaffold).last)).clearSnackBars();
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory documentsDir;
  late _FakeFilePicker filePicker;
  late _FakeSharePlatform sharePlatform;
  late _FakeAiServer aiServer;
  const secureStorage = FlutterSecureStorage();
  String? savedApiKey;
  String? savedSettings;

  setUp(() async {
    documentsDir = Directory.systemTemp.createTempSync('quizapp_integration_');
    PathProviderPlatform.instance = _TempPathProvider(documentsDir.path);
    filePicker = _FakeFilePicker();
    FilePicker.platform = filePicker;
    sharePlatform = _FakeSharePlatform();
    SharePlatform.instance = sharePlatform;
    aiServer = _FakeAiServer();
    await aiServer.start();

    savedApiKey = await secureStorage.read(key: _apiKeyStorageKey);
    savedSettings = await SharedPreferencesAsync().getString(_settingsKey);
    await secureStorage.delete(key: _apiKeyStorageKey);
    await SharedPreferencesAsync().remove(_settingsKey);
  });

  tearDown(() async {
    await aiServer.stop();
    if (savedApiKey == null) {
      await secureStorage.delete(key: _apiKeyStorageKey);
    } else {
      await secureStorage.write(key: _apiKeyStorageKey, value: savedApiKey);
    }
    if (savedSettings == null) {
      await SharedPreferencesAsync().remove(_settingsKey);
    } else {
      await SharedPreferencesAsync().setString(_settingsKey, savedSettings!);
    }
    if (documentsDir.existsSync()) documentsDir.deleteSync(recursive: true);
  });

  testWidgets('a full session: sign in, write notes, generate, quiz, track a problem, import, export, sign out',
      (tester) async {
    app.main();

    // --- Sign in --------------------------------------------------------
    await waitFor(tester, find.text('Sign in'));
    await enterText(tester, field('Username'), 'admin');
    await enterText(tester, field('Password'), 'wrong');
    await tap(tester, find.text('Sign in'));
    await waitFor(tester, find.text('Incorrect username or password.'));

    await enterText(tester, field('Password'), '1234');
    await tap(tester, find.text('Sign in'));
    await waitFor(tester, find.text('All caught up')); // the Today tab

    // The real openAppDatabase() created its file under the documents dir.
    final dbFile = File(p.join(documentsDir.path, 'quillfin.db'));
    expect(dbFile.existsSync(), isTrue);

    // --- Point the AI provider at the local fake server ------------------
    await tap(tester, navTab('Account'));
    await waitFor(tester, field('API key'));
    await enterText(tester, field('Model (e.g. gpt-4o-mini)'), 'test-model');
    await enterText(tester, field('Base URL override (optional)'), aiServer.baseUrl);
    await enterText(tester, field('API key'), _fakeApiKey);
    await tap(tester, find.widgetWithText(ElevatedButton, 'Save'));
    await waitFor(tester, find.widgetWithText(ElevatedButton, 'Saved'));
    // Stored through the real plugins, not just held in the form.
    expect(await secureStorage.read(key: _apiKeyStorageKey), _fakeApiKey);
    expect(await SharedPreferencesAsync().getString(_settingsKey), contains(aiServer.baseUrl));

    // --- Create a subject and a note -------------------------------------
    await tap(tester, navTab('Notes'));
    await tap(tester, find.byType(FloatingActionButton));
    await waitFor(tester, find.text('New Subject Folder'));
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Geography');
    await tap(tester, find.text('Save'));
    await tester.pumpAndSettle();
    await tap(tester, find.text('Geography'));
    await waitFor(tester, find.text('Empty. Use + to add a folder or note.'));

    await tap(tester, find.byIcon(Icons.add));
    await tap(tester, find.text('New note'));
    await waitFor(tester, field('Body'));
    await enterText(tester, field('Title'), 'Capitals and planets');
    await enterText(tester, field('Body'), 'Paris is the capital of France. Jupiter is the largest planet.');
    await tap(tester, find.byIcon(Icons.save));
    await waitFor(tester, find.text('Saved.'));
    await dismissSnackBars(tester);

    // --- Generate questions over real HTTP --------------------------------
    await tap(tester, find.text('Generate'));
    await waitFor(tester, find.text('Generated 2 question(s).'));
    await dismissSnackBars(tester);
    expect(aiServer.requests, hasLength(1));
    expect(aiServer.requests.single.auth, 'Bearer $_fakeApiKey');
    expect(aiServer.requests.single.body['model'], 'test-model');
    expect(jsonEncode(aiServer.requests.single.body['messages']), contains('Jupiter is the largest planet.'));

    // --- Review and edit a generated question -----------------------------
    await tap(tester, find.byTooltip('View questions generated from this note'));
    await waitFor(tester, find.text('What is the capital of France?'));
    expect(find.text('Which planet is largest?'), findsOneWidget);
    await tap(tester, find.text('What is the capital of France?'));
    await waitFor(tester, field('Question prompt'));
    expect(find.text('Capitals and planets'), findsOneWidget); // "Generated from" link
    await enterText(tester, field('Question prompt'), 'Name the capital of France.');
    await tap(tester, find.byIcon(Icons.save));
    await waitFor(tester, find.text('Saved.'));
    await dismissSnackBars(tester);
    await goBack(tester);
    await waitFor(tester, find.text('Name the capital of France.'));
    expect(find.text('Short answer · edited'), findsOneWidget);
    await goBack(tester); // to the note editor
    await goBack(tester); // to the folder
    await waitFor(tester, find.text('Capitals and planets'));

    // --- Bulk import through the staging screen ---------------------------
    filePicker.result = FilePickerResult([
      PlatformFile(name: 'week1.txt', size: 5, bytes: utf8.encode('Rivers flow downhill.')),
      PlatformFile(name: 'week2.md', size: 5, bytes: utf8.encode('# Mountains\nEverest is tallest.')),
    ]);
    await tap(tester, find.byIcon(Icons.add));
    await tap(tester, find.text('Bulk import files...'));
    await waitFor(tester, find.text('Review Import (2)'));
    await tap(tester, find.text('Import 2 note(s)'));
    await waitFor(tester, find.text('Imported 2 note(s).'));
    await waitFor(tester, find.text('week2.md'));
    expect(find.text('week1.txt'), findsOneWidget);
    expect(find.text('Rivers flow downhill.'), findsOneWidget);
    await dismissSnackBars(tester);
    await goBack(tester);

    // --- Take the quiz from the Today tab ----------------------------------
    // New questions are due straight away, so Today offers both.
    final db = await databaseFactoryFfi.openDatabase(dbFile.path);
    await tap(tester, navTab('Today'));
    await tap(tester, find.text('Start quiz (2)'));
    await waitFor(tester, find.text('1 more due after this one'));

    // Both questions share a due time, so either can come first.
    for (var i = 0; i < 2; i++) {
      if (find.text('Which planet is largest?').evaluate().isNotEmpty) {
        await tap(tester, find.text('Mars')); // deliberately wrong
        await tap(tester, find.text('Submit'));
        await waitFor(tester, find.text('Incorrect. Expected: Jupiter'));
        await tap(tester, find.byKey(const ValueKey('rating-again')));
      } else {
        await enterText(tester, field('Your answer'), 'paris');
        await tap(tester, find.text('Submit'));
        await waitFor(tester, find.text('Correct!'));
        await tap(tester, find.byKey(const ValueKey('rating-easy'))); // overrides the suggested Good
      }
    }
    await waitFor(tester, find.text('Session done: 2 reviewed. Nothing else is due right now.'));

    final history = await db.query('question_history', orderBy: 'id');
    expect(history, hasLength(2));
    expect(history.map((r) => (r['is_correct'], r['rating'])), unorderedEquals([(1, 4), (0, 1)]));
    final rescheduled = await db.query('questions', where: 'next_due_at <= ?', whereArgs: [dtToIso(utcNow())]);
    expect(rescheduled, isEmpty, reason: 'answered questions should no longer be due');
    await goBack(tester);
    await waitFor(tester, find.text('All caught up'));

    // --- Track a problem and log an attempt --------------------------------
    await tap(tester, navTab('Tracker'));
    await tap(tester, find.text('Add a problem'));
    await enterText(tester, field('Problem name'), 'Two Sum');
    await tap(tester, find.widgetWithText(ChoiceChip, 'Easy'));
    await enterText(tester, field('Tags, comma separated'), 'arrays, hash map');
    await tap(tester, find.byIcon(Icons.save));
    await tap(tester, find.text('Log attempt'));
    await enterText(tester, field('Time taken (minutes, optional)'), '15');
    await tap(tester, find.text('Save attempt'));
    await waitFor(tester, find.text('Logged. Next re-solve in 10m.'));
    await dismissSnackBars(tester);
    await goBack(tester);
    await waitFor(tester, find.text('1 problems · 1 solved · 0 due'));
    final attempts = await db.query('problem_attempts');
    expect((attempts.single['solved'], attempts.single['rating'], attempts.single['duration_minutes']), (1, 3, 15));

    // --- Settings: default format and export ------------------------------
    await tap(tester, navTab('Settings'));
    await tester.scrollUntilVisible(find.text('Multiple choice'), 200);
    await tap(tester, find.text('Multiple choice'));
    await tester.pumpAndSettle();
    expect(await SharedPreferencesAsync().getString(_settingsKey), contains('"default_question_format":"multiple_choice"'));

    await tester.scrollUntilVisible(find.text('Export all data'), 200);
    await tap(tester, find.text('Export all data'));
    await pumpUntil(tester, () => sharePlatform.sharedFiles.isNotEmpty, reason: 'export shared');
    final export = jsonDecode(await sharePlatform.sharedFiles.single.readAsString()) as Map<String, dynamic>;
    expect(export['folders'], hasLength(1));
    expect(export['notes'], hasLength(3));
    expect(export['questions'], hasLength(2));
    expect(export['question_choices'], hasLength(3));
    expect(export['question_history'], hasLength(2));
    expect(export['problems'], hasLength(1));
    expect(export['problem_attempts'], hasLength(1));

    // --- Sign out, sign back in: everything is still there ----------------
    await tap(tester, navTab('Account'));
    await tap(tester, find.text('Log out'));
    await waitFor(tester, find.text('Sign in'));
    await enterText(tester, field('Username'), 'admin');
    await enterText(tester, field('Password'), '1234');
    await tap(tester, find.text('Sign in'));
    await tap(tester, navTab('Notes'));
    await waitFor(tester, find.text('Geography'));

    await tap(tester, navTab('Account'));
    await waitFor(tester, find.text('test-model'));
    expect(find.text(aiServer.baseUrl), findsOneWidget);
  });
}
