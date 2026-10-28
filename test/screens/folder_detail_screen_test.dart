import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quillfin/core/models.dart';
import 'package:quillfin/screens/notes/bulk_import_staging_screen.dart';
import 'package:quillfin/screens/notes/folder_detail_screen.dart';
import 'package:quillfin/screens/notes/note_editor_screen.dart';
import 'package:quillfin/storage/folders_repo.dart';
import 'package:quillfin/storage/notes_repo.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/test_env.dart';

void main() {
  setUpTestEnv();

  late Database db;
  late Folder folder;

  Future<void> setUpDb() async {
    db = await openTestDatabase();
    folder = await FoldersRepo(db).create('Physics');
  }

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: FolderDetailScreen(db: db, folder: folder)));
    await waitForLoad(tester);
  }

  Future<void> chooseFromAddMenu(WidgetTester tester, String item) async {
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the folder name and an empty state', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      await show(tester);

      expect(find.text('Physics'), findsOneWidget);
      expect(find.text('Empty. Use + to add a folder or note.'), findsOneWidget);
    });
  });

  testWidgets('lists subfolders first, then notes with a one-line preview', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      await FoldersRepo(db).create('Optics', parentFolderId: folder.id);
      await NotesRepo(db).create(folder.id, 'Blank', '');
      await NotesRepo(db).create(folder.id, 'Waves', 'Light is a wave.');
      await show(tester);

      final titles = tester.widgetList<ListTile>(find.byType(ListTile)).map((t) => (t.title as Text).data).toList();
      expect(titles, ['Optics', 'Blank', 'Waves']);
      expect(find.text('(empty)'), findsOneWidget);
      expect(find.text('Light is a wave.'), findsOneWidget);
    });
  });

  testWidgets('"New folder" creates a trimmed subfolder', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      await show(tester);

      await chooseFromAddMenu(tester, 'New folder');
      await tester.enterText(find.byType(TextField), '  Optics  ');
      await tester.tap(find.text('Save'));
      await pumpUntil(tester, () => find.text('Optics').evaluate().length == 1 && find.byType(AlertDialog).evaluate().isEmpty);

      expect((await FoldersRepo(db).listChildren(folder.id)).single.name, 'Optics');
    });
  });

  testWidgets('cancelling or entering a blank name creates nothing', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      await show(tester);

      await chooseFromAddMenu(tester, 'New folder');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await chooseFromAddMenu(tester, 'New folder');
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(await FoldersRepo(db).listChildren(folder.id), isEmpty);
      expect(find.text('Empty. Use + to add a folder or note.'), findsOneWidget);
    });
  });

  testWidgets('"New note" opens the editor on a new note, which is listed on return', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      await show(tester);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New note'));
      await settleNavigation(tester);

      expect(find.byType(NoteEditorScreen), findsOneWidget);
      expect(find.text('Untitled note'), findsOneWidget);

      await tester.pageBack();
      await settleNavigation(tester);
      expect(find.byType(NoteEditorScreen), findsNothing);
      expect(find.text('Untitled note'), findsOneWidget);
    });
  });

  testWidgets('bulk import does nothing when the picker is cancelled or returns no files', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      await show(tester);

      filePicker.result = null;
      await chooseFromAddMenu(tester, 'Bulk import files...');
      filePicker.result = FilePickerResult(const []);
      await chooseFromAddMenu(tester, 'Bulk import files...');

      expect(filePicker.calls, 2);
      expect(find.byType(BulkImportStagingScreen), findsNothing);
    });
  });

  testWidgets('bulk import stages picked files, imports them, and reports the count', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      await show(tester);
      final bytes = Uint8List.fromList(utf8.encode('Imported body'));
      filePicker.result = FilePickerResult([PlatformFile(name: 'lecture.txt', size: bytes.length, bytes: bytes)]);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bulk import files...'));
      await settleNavigation(tester);
      expect(find.byType(BulkImportStagingScreen), findsOneWidget);

      await tester.tap(find.text('Import 1 note(s)'));
      await pumpUntil(tester, () => find.text('Imported 1 note(s).').evaluate().isNotEmpty);
      await pumpUntil(tester, () => find.text('Imported body').evaluate().isNotEmpty);
    });
  });

  testWidgets('backing out of bulk import shows no snackbar', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      await show(tester);
      final bytes = Uint8List.fromList(utf8.encode('x'));
      filePicker.result = FilePickerResult([PlatformFile(name: 'a.txt', size: 1, bytes: bytes)]);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bulk import files...'));
      await settleNavigation(tester);
      await tester.pageBack();
      await settleNavigation(tester);

      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Empty. Use + to add a folder or note.'), findsOneWidget);
    });
  });

  testWidgets('tapping a subfolder opens it, and returning refreshes the list', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      final child = await FoldersRepo(db).create('Optics', parentFolderId: folder.id);
      await show(tester);

      await tester.tap(find.text('Optics'));
      await settleNavigation(tester);
      expect(find.text('Empty. Use + to add a folder or note.'), findsOneWidget);

      // Rename-by-recreate behind the screen's back, then check the refresh on return.
      await FoldersRepo(db).delete(child.id);
      await tester.pageBack();
      await settleNavigation(tester);
      expect(find.text('Optics'), findsNothing);
    });
  });

  testWidgets('tapping a note opens it in the editor', (tester) async {
    await tester.runAsync(() async {
      await setUpDb();
      final note = await NotesRepo(db).create(folder.id, 'Waves', 'Light is a wave.');
      await show(tester);

      await tester.tap(find.text('Waves'));
      await settleNavigation(tester);
      expect(find.byType(NoteEditorScreen), findsOneWidget);

      await NotesRepo(db).update(note.id, title: 'Particles');
      await tester.pageBack();
      await settleNavigation(tester);
      expect(find.text('Particles'), findsOneWidget);
    });
  });
}
