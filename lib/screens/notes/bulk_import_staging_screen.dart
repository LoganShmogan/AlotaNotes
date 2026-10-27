import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/text_extraction.dart';
import '../../storage/notes_repo.dart';

/// Preview-then-confirm screen for bulk file import. Nothing lands in the
/// real notebook until "Import" is tapped -- the user can rename or drag
/// items into a different order first (see Docs/flutter_rewrite_plan.md's
/// import-staging spec).
///
/// Honest platform caveat: standard mobile file pickers return a flat list
/// of individually-picked files, not an enumerated folder tree -- there's
/// no reliable cross-platform "pick a whole folder with subfolders" API the
/// way a desktop file dialog has. So this stages a flat, reorderable list
/// into one destination folder, rather than reconstructing the source's
/// original folder structure. Revisit if/when a real need for nested
/// source-structure import shows up.
class BulkImportStagingScreen extends StatefulWidget {
  final Database db;
  final int folderId;
  final List<PlatformFile> pickedFiles;

  const BulkImportStagingScreen({
    super.key,
    required this.db,
    required this.folderId,
    required this.pickedFiles,
  });

  @override
  State<BulkImportStagingScreen> createState() => _BulkImportStagingScreenState();
}

class _StagedItem {
  final PlatformFile file;
  final TextEditingController titleController;
  String? error;

  _StagedItem(this.file) : titleController = TextEditingController(text: file.name);
}

class _BulkImportStagingScreenState extends State<BulkImportStagingScreen> {
  late final NotesRepo _notesRepo = NotesRepo(widget.db);
  late List<_StagedItem> _items;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _items = widget.pickedFiles.where((f) => f.bytes != null).map(_StagedItem.new).toList();
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.titleController.dispose();
    }
    super.dispose();
  }

  void _remove(int index) {
    setState(() {
      _items[index].titleController.dispose();
      _items.removeAt(index);
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
  }

  Future<void> _confirmImport() async {
    setState(() => _importing = true);
    var successCount = 0;
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      try {
        final body = extractText(item.file.name, item.file.bytes!);
        await _notesRepo.create(
          widget.folderId,
          item.titleController.text.trim().isEmpty ? item.file.name : item.titleController.text.trim(),
          body,
          sourceFilename: item.file.name,
          sortOrder: i,
        );
        successCount++;
      } catch (e) {
        setState(() => item.error = e.toString());
      }
    }
    setState(() => _importing = false);
    if (!mounted) return;
    if (_items.every((i) => i.error == null)) {
      Navigator.of(context).pop(successCount);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $successCount of ${_items.length}; failed items are marked below.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Review Import (${_items.length})'),
      ),
      body: _items.isEmpty
          ? const Center(child: Text('Nothing to import.'))
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _items.length,
              // ignore: deprecated_member_use
              onReorder: _reorder,
              itemBuilder: (context, index) {
                final item = _items[index];
                return Card(
                  key: ObjectKey(item),
                  child: ListTile(
                    leading: const Icon(Icons.drag_handle),
                    title: TextField(
                      controller: item.titleController,
                      decoration: const InputDecoration(border: InputBorder.none),
                    ),
                    subtitle: Text(
                      item.error ?? item.file.name,
                      style: item.error != null ? TextStyle(color: Theme.of(context).colorScheme.error) : null,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _importing ? null : () => _remove(index),
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: (_importing || _items.isEmpty) ? null : _confirmImport,
            child: _importing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Import ${_items.length} note(s)'),
          ),
        ),
      ),
    );
  }
}
