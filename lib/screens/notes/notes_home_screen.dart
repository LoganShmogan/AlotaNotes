import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/models.dart';
import '../../storage/folders_repo.dart';
import '../../layout/breakpoints.dart';
import '../../theme/widgets.dart';
import 'dialogs.dart';
import 'folder_detail_screen.dart';

/// Root of the Notes tab: top-level subject folders.
class NotesHomeScreen extends StatefulWidget {
  final Database db;

  /// Fires when folders may have changed elsewhere (a sync pull).
  final Listenable? refresh;
  const NotesHomeScreen({super.key, required this.db, this.refresh});

  @override
  State<NotesHomeScreen> createState() => _NotesHomeScreenState();
}

class _NotesHomeScreenState extends State<NotesHomeScreen> {
  late final FoldersRepo _foldersRepo = FoldersRepo(widget.db);
  List<Folder> _folders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.refresh?.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final folders = await _foldersRepo.listChildren(null);
    if (!mounted) return;
    setState(() {
      _folders = folders;
      _loading = false;
    });
  }

  Future<void> _createFolder() async {
    final name = await promptForName(context, title: 'New Subject Folder');
    if (name == null || name.trim().isEmpty) return;
    await _foldersRepo.create(name.trim());
    await _refresh();
  }

  void _openFolder(Folder folder) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => FolderDetailScreen(db: widget.db, folder: folder),
          ),
        )
        .then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notes')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _folders.isEmpty
          ? const EmptyState(icon: Icons.folder_outlined, message: 'No subjects yet. Tap + to create one.')
          : LayoutBuilder(
              builder: (context, constraints) {
                // Centred at reading width on wide windows.
                final inset = centeredInset(constraints.maxWidth, context.windowSize.gutter);
                return ListView.builder(
                  padding: EdgeInsets.fromLTRB(inset, 12, inset, 96),
                  itemCount: _folders.length,
                  itemBuilder: (context, index) {
                    final folder = _folders[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.folder),
                        title: Text(folder.name),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openFolder(folder),
                      ),
                    );
                  },
                );
              },
            ),
      // No hero: see ProblemsScreen's FAB.
      floatingActionButton: FloatingActionButton(heroTag: null, onPressed: _createFolder, child: const Icon(Icons.add)),
    );
  }
}
