import 'package:sqflite/sqflite.dart';

import '../core/models.dart';
import 'db.dart';

class NotesRepo {
  final Database _db;
  const NotesRepo(this._db);

  Note _rowToNote(Map<String, Object?> row) => Note(
        id: row['id'] as int,
        folderId: row['folder_id'] as int,
        title: row['title'] as String,
        body: row['body'] as String,
        sourceFilename: row['source_filename'] as String?,
        sortOrder: row['sort_order'] as int,
        createdAt: isoToDt(row['created_at'] as String),
        updatedAt: isoToDt(row['updated_at'] as String),
      );

  Future<Note> create(
    int folderId,
    String title,
    String body, {
    String? sourceFilename,
    int sortOrder = 0,
    DateTime? now,
  }) async {
    final createdAt = now ?? utcNow();
    final iso = dtToIso(createdAt);
    final id = await _db.insert('notes', {
      'folder_id': folderId,
      'title': title,
      'body': body,
      'source_filename': sourceFilename,
      'sort_order': sortOrder,
      'created_at': iso,
      'updated_at': iso,
    });
    return get(id);
  }

  Future<Note> get(int id) async {
    final rows = await _db.query('notes', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) {
      throw StateError('No note with id $id');
    }
    return _rowToNote(rows.first);
  }

  /// Ordered by the user's own chosen order first (set at import time, or
  /// via drag-to-reorder), falling back to title for notes with the same
  /// (default 0) sort_order -- e.g. ones created individually rather than
  /// through bulk import.
  Future<List<Note>> listByFolder(int folderId) async {
    final rows = await _db.query(
      'notes',
      where: 'folder_id = ?',
      whereArgs: [folderId],
      orderBy: 'sort_order, title',
    );
    return rows.map(_rowToNote).toList();
  }

  Future<Note> update(
    int id, {
    String? title,
    String? body,
    int? sortOrder,
    DateTime? now,
  }) async {
    final existing = await get(id);
    final updatedAt = now ?? utcNow();
    await _db.update(
      'notes',
      {
        'title': title ?? existing.title,
        'body': body ?? existing.body,
        'sort_order': sortOrder ?? existing.sortOrder,
        'updated_at': dtToIso(updatedAt),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return get(id);
  }

  Future<void> delete(int id) async {
    await _db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }
}
