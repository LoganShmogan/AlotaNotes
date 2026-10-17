// Widget test for the FAB -> dialog -> folder-creation flow.
//
// This exists because manually driving the same flow via `adb shell input
// tap` against a headless/software-rendered (swiftshader) Android emulator
// turned out to be unreliable for `Positioned`/FAB-style bottom-anchored
// widgets specifically -- extensive isolation testing (sync-only handlers,
// no BuildContext dependency, plain ElevatedButton in place of
// FloatingActionButton, `top:`-anchored vs `bottom:`-anchored Positioned
// widgets at identical screen coordinates) showed the *paint* position and
// the *hit-test* position diverging for anything bottom-anchored, while
// identical top-anchored widgets worked every time. That's a property of
// synthetic zero-duration ADB taps racing this Stack's gesture arena on
// this specific emulator configuration, not of the app code.
//
// `flutter_test` sidesteps all of that: `tester.tap()` drives the widget
// tree directly at the framework level, with no real touch/display/OS
// input pipeline involved, so it's both deterministic and the right tool
// for verifying this logic (same reasoning as Docs/beginners_guide.md
// section 12 on the old desktop app's testing philosophy).
//
// Every test body runs inside `tester.runAsync()`: `sqflite_common_ffi`
// does genuine async I/O (a real native/isolate round-trip per query), and
// Flutter's default test zone (`FakeAsync`) doesn't drive that kind of
// real Future to completion on its own -- without `runAsync`, `pumpWidget`
// and the widget's own internal DB calls race each other and Flutter
// throws a "Guarded function conflict". This is a documented
// `sqflite_common_ffi` + `flutter_test` interaction, not a bug in the app.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:quizapp/screens/notes/folder_detail_screen.dart';
import 'package:quizapp/screens/notes/notes_home_screen.dart';
import 'package:quizapp/storage/db.dart';
import 'package:quizapp/storage/folders_repo.dart';

/// `pumpAndSettle()` refuses to work while a `CircularProgressIndicator` is
/// on screen (it's an infinite animation, so "settled" never becomes true) --
/// this polls for the loading spinner to disappear instead, using real
/// delays since this always runs inside `tester.runAsync()`.
Future<void> _waitForLoad(WidgetTester tester) async {
  await tester.pump();
  while (find.byType(CircularProgressIndicator).evaluate().isNotEmpty) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump();
  }
}

/// Same reasoning as `_waitForLoad`: saving a folder triggers a real DB
/// write plus a real DB re-read before the list updates, so poll for the
/// expected outcome with real delays instead of a single `pumpAndSettle()`.
Future<void> _pumpUntil(WidgetTester tester, bool Function() condition, {int maxTries = 100}) async {
  for (var i = 0; i < maxTries; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TestFailure('Condition not met after $maxTries tries');
}

Future<Database> _openTestDatabase() async {
  // `singleInstance: false` is required here -- sqflite caches connections
  // by path, and `:memory:` is just a normal path to it, so without this
  // every test in this file would share (and collide on) the same
  // in-memory database instead of getting its own.
  final db = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await db.execute('PRAGMA foreign_keys = ON');
  for (final statement in schemaStatements) {
    await db.execute(statement);
  }
  return db;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('empty state shows the create-a-subject prompt', (tester) async {
    await tester.runAsync(() async {
      final db = await _openTestDatabase();
      await tester.pumpWidget(MaterialApp(home: NotesHomeScreen(db: db)));
      await _waitForLoad(tester);

      expect(find.text('No subjects yet. Tap + to create one.'), findsOneWidget);
    });
  });

  testWidgets('tapping the FAB opens the new-folder dialog', (tester) async {
    await tester.runAsync(() async {
      final db = await _openTestDatabase();
      await tester.pumpWidget(MaterialApp(home: NotesHomeScreen(db: db)));
      await _waitForLoad(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('New Subject Folder'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  testWidgets('creating a folder through the dialog adds it to the list', (tester) async {
    await tester.runAsync(() async {
      final db = await _openTestDatabase();
      await tester.pumpWidget(MaterialApp(home: NotesHomeScreen(db: db)));
      await _waitForLoad(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Physics');
      await tester.tap(find.text('Save'));
      // Don't wait on find.text('Physics') directly -- it also matches the
      // still-open dialog's TextField content before the real DB write and
      // list refresh have actually happened. The empty-state message going
      // away is driven by real `_folders` state, so it's the real signal.
      await _pumpUntil(tester, () => find.text('No subjects yet. Tap + to create one.').evaluate().isEmpty);
      await tester.pumpAndSettle(); // let the dialog's closing transition finish

      expect(find.text('Physics'), findsOneWidget);
      expect(find.text('No subjects yet. Tap + to create one.'), findsNothing);
    });
  });

  testWidgets('cancelling the dialog does not create a folder', (tester) async {
    await tester.runAsync(() async {
      final db = await _openTestDatabase();
      await tester.pumpWidget(MaterialApp(home: NotesHomeScreen(db: db)));
      await _waitForLoad(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Should not be saved');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('No subjects yet. Tap + to create one.'), findsOneWidget);
    });
  });

  testWidgets('tapping a folder opens it, and returning refreshes the list', (tester) async {
    await tester.runAsync(() async {
      final db = await _openTestDatabase();
      final folder = await FoldersRepo(db).create('Physics');
      await tester.pumpWidget(MaterialApp(home: NotesHomeScreen(db: db)));
      await _waitForLoad(tester);

      await tester.tap(find.text('Physics'));
      await _pumpUntil(tester, () => find.byType(FolderDetailScreen).evaluate().isNotEmpty);
      await _pumpUntil(tester, () => find.text('Empty. Use + to add a folder or note.').evaluate().isNotEmpty);

      await FoldersRepo(db).delete(folder.id);
      await tester.pageBack();
      await _pumpUntil(tester, () => find.text('No subjects yet. Tap + to create one.').evaluate().isNotEmpty);
    });
  });
}
