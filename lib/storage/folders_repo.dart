import 'package:sqflite/sqflite.dart';

import '../core/models.dart';
import 'db.dart';

class FoldersRepo {
  final Database _db;
  const FoldersRepo(this._db);

  Folder _rowToFolder(Map<String, Object?> row) => Folder(
        id: row['id'] as int,
        parentFolderId: row['parent_folder_id'] as int?,
        name: row['name'] as String,
        createdAt: isoToDt(row['created_at'] as String),
      );

  Future<Folder> create(String name, {int? parentFolderId, DateTime? now}) async {
    final createdAt = now ?? utcNow();
    final id = await _db.insert('folders', {
      'parent_folder_id': parentFolderId,
      'name': name,
      'created_at': dtToIso(createdAt),
    });
    return get(id);
  }

  Future<Folder> get(int id) async {
    final rows = await _db.query('folders', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) {
      throw StateError('No folder with id $id');
    }
    return _rowToFolder(rows.first);
  }

  Future<List<Folder>> listChildren(int? parentFolderId) async {
    final rows = await _db.query(
      'folders',
      where: parentFolderId == null ? 'parent_folder_id IS NULL' : 'parent_folder_id = ?',
      whereArgs: parentFolderId == null ? null : [parentFolderId],
      orderBy: 'name',
    );
    return rows.map(_rowToFolder).toList();
  }

  Future<void> delete(int id) async {
    await _db.delete('folders', where: 'id = ?', whereArgs: [id]);
  }
}
