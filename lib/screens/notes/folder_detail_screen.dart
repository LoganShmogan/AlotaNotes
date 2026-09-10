import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/models.dart';
import '../../core/text_extraction.dart';
import '../../storage/folders_repo.dart';
import '../../storage/notes_repo.dart';
import 'bulk_import_staging_screen.dart';
import 'dialogs.dart';
import 'note_editor_screen.dart';

/// One folder's contents: its subfolders and its notes.
class FolderDetailScreen extends StatefulWidget {
  final Database db;
  final Folder folder;
  const FolderDetailScreen({super.key, required this.db, required this.folder});

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> {
  late final FoldersRepo _foldersRepo = FoldersRepo(widget.db);
  late final NotesRepo _notesRepo = NotesRepo(widget.db);
  List<Folder> _subfolders = [];
  List<Note> _notes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final subfolders = await _foldersRepo.listChildren(widget.folder.id);
    final notes = await _notesRepo.listByFolder(widget.folder.id);
    if (!mounted) return;
    setState(() {
      _subfolders = subfolders;
      _notes = notes;
      _loading = false;
    });
  }

  Future<void> _createSubfolder() async {
    final name = await promptForName(context, title: 'New Folder');
    if (name == null || name.trim().isEmpty) return;
    await _foldersRepo.create(name.trim(), parentFolderId: widget.folder.id);
    await _refresh();
  }

  Future<void> _createNote() async {
    final note = await _notesRepo.create(widget.folder.id, 'Untitled note', '');
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(db: widget.db, noteId: note.id)),
    );
    await _refresh();
  }

  Future<void> _bulkImport() async {
    // allowMultiple defaults to true on pickFiles() -- deprecated as an
    // explicit param in favor of using pickFile() for the single-file case
    // instead, not because multi-select itself is going away.
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedExtensions.map((e) => e.substring(1)).toList(),
    );
    if (files.isEmpty) return;
    if (!mounted) return;
    final imported = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => BulkImportStagingScreen(db: widget.db, folderId: widget.folder.id, pickedFiles: files),
      ),
    );
    if (imported != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported $imported note(s).')));
    }
    await _refresh();
  }

  void _openFolder(Folder folder) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => FolderDetailScreen(db: widget.db, folder: folder)))
        .then((_) => _refresh());
  }

  void _openNote(Note note) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => NoteEditorScreen(db: widget.db, noteId: note.id)))
        .then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.folder.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_subfolders.isEmpty && _notes.isEmpty)
              ? const Center(child: Text('Empty. Use + to add a folder or note.'))
              : ListView(
                  children: [
                    for (final folder in _subfolders)
                      ListTile(
                        leading: const Icon(Icons.folder),
                        title: Text(folder.name),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openFolder(folder),
                      ),
                    for (final note in _notes)
                      ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(note.title),
                        subtitle: Text(
                          note.body.isEmpty ? '(empty)' : note.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _openNote(note),
                      ),
                  ],
                ),
      floatingActionButton: PopupMenuButton<String>(
        icon: const Icon(Icons.add),
        onSelected: (choice) {
          if (choice == 'folder') _createSubfolder();
          if (choice == 'note') _createNote();
          if (choice == 'bulk_import') _bulkImport();
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'folder', child: Text('New folder')),
          PopupMenuItem(value: 'note', child: Text('New note')),
          PopupMenuItem(value: 'bulk_import', child: Text('Bulk import files...')),
        ],
      ),
    );
  }
}
