// Real in-memory SQLite and real tester.tap() interaction; see
// notes_home_screen_test.dart for why every body runs in tester.runAsync().
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizapp/screens/notes/bulk_import_staging_screen.dart';
import 'package:quizapp/storage/folders_repo.dart';
import 'package:quizapp/storage/notes_repo.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/test_env.dart';

PlatformFile textFile(String name, String content) {
  final bytes = Uint8List.fromList(utf8.encode(content));
  return PlatformFile(name: name, size: bytes.length, bytes: bytes);
}

void main() {
  setUpTestEnv();

  late Database db;
  late int folderId;

  Future<void> setUpDb() async {
    db = await openTestDatabase();
    folderId = (await FoldersRepo(db).create('Imports')).id;
  }

  Widget screen(List<PlatformFile> files) =>
      BulkImportStagingScreen(db: db, folderId: folderId, pickedFiles: files);

  List<String> stagedTitles(WidgetTester tester) => tester
      .widgetList<TextField>(find.byType(TextField))
      .map((field) => field.controller!.text)
      .toList();

  testWidgets('stages only files that came with bytes', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      await tester.pumpWidget(MaterialApp(
        home: screen([
          textFile('a.txt', 'A'),
          PlatformFile(name: 'no-bytes.txt', size: 0),
          textFile('b.md', 'B'),
        ]),
      ));

      expect(find.text('Review Import (2)'), findsOneWidget);
      expect(stagedTitles(tester), ['a.txt', 'b.md']);
      expect(find.text('Import 2 note(s)'), findsOneWidget);
    });
  });

  testWidgets('with nothing importable, shows an empty state and disables Import', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      await tester.pumpWidget(MaterialApp(home: screen([PlatformFile(name: 'x.txt', size: 0)])));

      expect(find.text('Nothing to import.'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
    });
  });

  testWidgets('the close button removes an item from the staging list', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      await tester.pumpWidget(MaterialApp(home: screen([textFile('a.txt', 'A'), textFile('b.txt', 'B')])));

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();

      expect(stagedTitles(tester), ['b.txt']);
      expect(find.text('Review Import (1)'), findsOneWidget);
    });
  });

  testWidgets('reordering moves items both down and up', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      await tester.pumpWidget(MaterialApp(
        home: screen([textFile('a.txt', 'A'), textFile('b.txt', 'B'), textFile('c.txt', 'C')]),
      ));
      // ignore: deprecated_member_use
      final onReorder = tester.widget<ReorderableListView>(find.byType(ReorderableListView)).onReorder!;

      // Moving down: newIndex counts the slot before removal, so 0 -> 2 lands at index 1.
      onReorder(0, 2);
      await tester.pump();
      expect(stagedTitles(tester), ['b.txt', 'a.txt', 'c.txt']);

      onReorder(2, 0);
      await tester.pump();
      expect(stagedTitles(tester), ['c.txt', 'b.txt', 'a.txt']);
    });
  });

  testWidgets('Import creates notes in staged order with edited titles, then pops the count', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      final result = PopResult<int>();
      await tester.pumpWidget(hostFor(screen([textFile('a.txt', 'Alpha body'), textFile('b.md', 'Beta body')]), result));
      await tester.tap(find.text('open'));
      await settleNavigation(tester);

      await tester.enterText(find.byType(TextField).first, '  Renamed  ');
      await tester.enterText(find.byType(TextField).last, '   '); // blank falls back to the file name
      await tester.tap(find.text('Import 2 note(s)'));
      await pumpUntil(tester, () => result.popped);

      expect(result.value, 2);
      final notes = await NotesRepo(db).listByFolder(folderId);
      expect(notes.map((n) => (n.title, n.body, n.sourceFilename, n.sortOrder)), [
        ('Renamed', 'Alpha body', 'a.txt', 0),
        ('b.md', 'Beta body', 'b.md', 1),
      ]);
    });
  });

  testWidgets('a failing file is marked and the screen stays open', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      final result = PopResult<int>();
      await tester.pumpWidget(hostFor(screen([textFile('good.txt', 'ok'), textFile('bad.exe', '??')]), result));
      await tester.tap(find.text('open'));
      await settleNavigation(tester);

      await tester.tap(find.text('Import 2 note(s)'));
      await pumpUntil(tester, () => find.textContaining('Imported 1 of 2').evaluate().isNotEmpty);

      expect(result.popped, isFalse);
      final error = tester.widget<Text>(find.textContaining("Unsupported file type '.exe'"));
      expect(error.style?.color, Colors.redAccent);
      expect((await NotesRepo(db).listByFolder(folderId)).single.title, 'good.txt');
    });
  });
}
