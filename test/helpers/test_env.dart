// Shared setup for tests that touch the database, platform plugins, or
// real async widget flows. See Docs/testing.md for why each piece exists.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:quillfin/storage/db.dart';

/// A fresh, isolated in-memory database with the app's schema applied.
/// `singleInstance: false` stops sqflite handing every test the same
/// cached `:memory:` connection.
Future<Database> openTestDatabase() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await db.execute('PRAGMA foreign_keys = ON');
  for (final statement in schemaStatements) {
    await db.execute(statement);
  }
  return db;
}

/// Returns [result] from every `pickFiles` call (null = user cancelled) and
/// counts the calls.
class FakeFilePicker extends FilePicker with MockPlatformInterfaceMixin {
  FilePickerResult? result;
  int calls = 0;

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
  }) async {
    calls++;
    return result;
  }
}

class FakeSharePlatform extends SharePlatform with MockPlatformInterfaceMixin {
  final List<XFile> sharedFiles = [];
  List<String>? lastFileNameOverrides;

  @override
  Future<ShareResult> shareXFiles(
    List<XFile> files, {
    String? subject,
    String? text,
    Rect? sharePositionOrigin,
    List<String>? fileNameOverrides,
  }) async {
    sharedFiles.addAll(files);
    lastFileNameOverrides = fileNameOverrides;
    return const ShareResult('', ShareResultStatus.success);
  }
}

class FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String documentsPath;
  FakePathProvider(this.documentsPath);

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

/// Installed fakes for the current test, recreated by [setUpTestEnv].
late FakeFilePicker filePicker;
late FakeSharePlatform sharePlatform;
late Directory documentsDir;

/// Call from `main()` once per test file. Points every plugin at an
/// in-memory fake, so tests never hit real platform channels.
void setUpTestEnv() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    filePicker = FakeFilePicker();
    FilePicker.platform = filePicker;
    sharePlatform = FakeSharePlatform();
    SharePlatform.instance = sharePlatform;
    documentsDir = Directory.systemTemp.createTempSync('quizapp_test_');
    PathProviderPlatform.instance = FakePathProvider(documentsDir.path);
  });
  tearDown(() {
    if (documentsDir.existsSync()) documentsDir.deleteSync(recursive: true);
  });
}

/// `pumpAndSettle()` never returns while an indeterminate spinner is on
/// screen, so poll with real delays until none are left. Must run inside
/// `tester.runAsync()`.
Future<void> waitForLoad(WidgetTester tester) async {
  await pumpUntil(tester, () => find.byType(CircularProgressIndicator).evaluate().isEmpty);
}

/// Polls with real delays until [condition] holds. Must run inside
/// `tester.runAsync()`, since the work being waited on is real I/O. Each
/// pump also advances the fake clock by one frame, so route and dialog
/// transitions make progress while waiting.
Future<void> pumpUntil(WidgetTester tester, bool Function() condition, {int maxTries = 200}) async {
  for (var i = 0; i < maxTries; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TestFailure('Condition not met after $maxTries tries');
}

/// Waits for page transitions to finish, then for any loading spinner on
/// the new page to go away. Real delays between frames let DB work that
/// runs before or after a push/pop (create-then-open, refresh-on-return)
/// actually complete.
Future<void> settleNavigation(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await waitForLoad(tester);
}

/// What a page pushed by [hostFor] popped with.
class PopResult<T> {
  bool popped = false;
  T? value;
}

/// A blank host page with an "open" button that pushes [page], so tests can
/// check what the page pops with (recorded in [result]).
Widget hostFor<T>(Widget page, PopResult<T> result) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              result.value = await Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));
              result.popped = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}
