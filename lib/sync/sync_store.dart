/// The local half of sync: reads what needs pushing out of SQLite and
/// applies what was pulled. The triggers in storage/db.dart keep the
/// `uid`, `sync_updated_at` and `dirty` columns and the tombstones current;
/// this class only reads them and, after a push, clears them.
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'sync_tables.dart';

/// The server's limit on a note body, in UTF-8 bytes (backend/convex/plans.ts).
/// Larger notes stay on this device instead of failing every push.
const maxSyncedNoteBytes = 200 * 1024;

/// The server's limit on rows per push.
const maxRowsPerPush = 200;

/// One push's worth of changes, plus what to mark clean once it lands.
class PushBatch {
  /// Remote table name to rows, as `sync:push` takes them.
  final Map<String, List<Map<String, Object?>>> changes;
  final List<(String table, String uid, int syncUpdatedAt)> _rows;
  final List<(String table, String uid, int deletedAt)> _tombstones;

  PushBatch._(this.changes, this._rows, this._tombstones);

  int get length => _rows.length + _tombstones.length;
  bool get isEmpty => length == 0;
}

class SyncStore {
  final Database db;
  const SyncStore(this.db);

  // --- sync_state ---

  Future<Map<String, Object?>> _state() async => (await db.query('sync_state')).single;

  Future<int> cursor() async => (await _state())['cursor'] as int;

  Future<void> setCursor(int cursor) => db.update('sync_state', {'cursor': cursor});

  /// The account this device's data last synced with.
  Future<String?> userId() async => (await _state())['user_id'] as String?;

  Future<DateTime?> lastSyncedAt() async {
    final value = (await _state())['last_synced_at'] as String?;
    return value == null ? null : DateTime.parse(value);
  }

  Future<void> setLastSyncedAt(DateTime at) =>
      db.update('sync_state', {'last_synced_at': at.toUtc().toIso8601String()});

  /// Starts syncing this device's data with [userId]. If it last synced with
  /// a different account, everything local is pushed to the new one and its
  /// data is pulled from the start.
  Future<void> bindUser(String userId) async {
    final previous = await this.userId();
    if (previous == userId) return;
    await db.transaction((txn) async {
      if (previous != null) {
        for (final table in syncTables) {
          await txn.rawUpdate('UPDATE ${table.local} SET dirty = 1 WHERE dirty = 0');
        }
      }
      await txn.update('sync_state', {'user_id': userId, 'cursor': 0, 'last_synced_at': null});
    });
  }

  // --- what's left to push ---

  static const _noteSizeFilter = 'length(CAST(c.body AS BLOB)) <= $maxSyncedNoteBytes';

  /// Rows and deletions waiting to be pushed, not counting notes too large
  /// to sync.
  Future<int> pendingChanges() async {
    var total = 0;
    for (final table in syncTables) {
      final sizeFilter = table.local == 'notes' ? ' AND $_noteSizeFilter' : '';
      total += Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM ${table.local} c WHERE c.dirty = 1$sizeFilter'),
      )!;
    }
    return total + Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM sync_tombstones'))!;
  }

  /// Notes over [maxSyncedNoteBytes], which stay on this device.
  Future<int> oversizedNotes() async => Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM notes c WHERE NOT ($_noteSizeFilter)'),
      )!;

  /// Up to [limit] changes: changed rows first, parents before children,
  /// then deletions.
  Future<PushBatch> nextPushBatch({int limit = maxRowsPerPush}) async {
    final changes = <String, List<Map<String, Object?>>>{};
    final rows = <(String, String, int)>[];
    final tombstones = <(String, String, int)>[];

    for (final table in syncTables) {
      final remaining = limit - rows.length;
      if (remaining <= 0) break;
      final parent = table.parent;
      final join = parent == null ? '' : ' LEFT JOIN ${parent.$2} p ON p.id = c.${parent.$1}';
      final parentUid = parent == null ? '' : ', p.uid AS parent_uid';
      final sizeFilter = table.local == 'notes' ? ' AND $_noteSizeFilter' : '';
      final found = await db.rawQuery(
        'SELECT c.*$parentUid FROM ${table.local} c$join WHERE c.dirty = 1$sizeFilter ORDER BY c.id LIMIT $remaining',
      );
      for (final row in found) {
        final data = {for (final f in table.fields) f.key: f.toRemote(row[f.column])};
        if (parent != null) data[parent.$3] = row['parent_uid'];
        (changes[table.remote] ??= []).add({
          'uid': row['uid'],
          'updatedAt': row['sync_updated_at'],
          'data': data,
        });
        rows.add((table.local, row['uid'] as String, row['sync_updated_at'] as int));
      }
    }

    final remaining = limit - rows.length;
    if (remaining > 0) {
      for (final t in await db.query('sync_tombstones', orderBy: 'deleted_at', limit: remaining)) {
        final table = syncTableByLocal(t['table_name'] as String);
        (changes[table.remote] ??= []).add({
          'uid': t['uid'],
          'updatedAt': t['deleted_at'],
          'deletedAt': t['deleted_at'],
        });
        tombstones.add((table.local, t['uid'] as String, t['deleted_at'] as int));
      }
    }
    return PushBatch._(changes, rows, tombstones);
  }

  /// Marks a pushed batch as synced. A row changed again since it was read
  /// keeps its newer `sync_updated_at`, so it stays dirty for the next push.
  Future<void> markPushed(PushBatch batch) async {
    await db.transaction((txn) async {
      for (final (table, uid, syncUpdatedAt) in batch._rows) {
        await txn.rawUpdate(
          'UPDATE $table SET dirty = 0 WHERE uid = ? AND sync_updated_at = ?',
          [uid, syncUpdatedAt],
        );
      }
      for (final (table, uid, deletedAt) in batch._tombstones) {
        await txn.delete(
          'sync_tombstones',
          where: 'table_name = ? AND uid = ? AND deleted_at = ?',
          whereArgs: [table, uid, deletedAt],
        );
      }
    });
  }

  // --- applying pulled changes ---

  /// Applies one page from `sync:pull` (remote table name to rows) and any
  /// held-back rows whose parents have now arrived. Returns how many rows
  /// changed locally.
  Future<int> applyPulled(Map<String, dynamic> changes) {
    return db.transaction((txn) async {
      await txn.update('sync_state', {'applying': 1});
      var applied = 0;
      for (final table in syncTables) {
        for (final row in (changes[table.remote] as List?) ?? const []) {
          if (await _apply(txn, table, Map<String, Object?>.from(row as Map))) applied++;
        }
      }
      applied += await _retryPending(txn);
      await txn.update('sync_state', {'applying': 0});
      return applied;
    });
  }

  Future<int> _retryPending(Transaction txn) async {
    var applied = 0;
    // Each pass can unblock the next level down (a folder, then its notes).
    for (var progress = true; progress;) {
      progress = false;
      for (final pending in await txn.query('sync_pending')) {
        final table = syncTableByLocal(pending['table_name'] as String);
        final row = jsonDecode(pending['payload'] as String) as Map<String, Object?>;
        if (await _apply(txn, table, row)) {
          applied++;
          progress = true;
        }
      }
    }
    return applied;
  }

  Future<bool> _apply(Transaction txn, SyncTable table, Map<String, Object?> row) async {
    final uid = row['uid'] as String;
    final updatedAt = (row['updatedAt'] as num).toInt();
    final deletedAt = (row['deletedAt'] as num?)?.toInt();
    final existing = (await txn.query(
      table.local,
      columns: ['id', 'dirty', 'sync_updated_at'],
      where: 'uid = ?',
      whereArgs: [uid],
    ))
        .firstOrNull;

    // A local change that's newer than the server's wins; it goes up on the
    // next push.
    if (existing != null && existing['dirty'] == 1 && (existing['sync_updated_at'] as int) > (deletedAt ?? updatedAt)) {
      await _clearPending(txn, table, uid);
      return false;
    }

    if (deletedAt != null) {
      await _clearPending(txn, table, uid);
      if (existing == null) return false;
      await txn.delete(table.local, where: 'id = ?', whereArgs: [existing['id']]);
      return true;
    }

    final data = Map<String, Object?>.from(row['data'] as Map);
    final values = {for (final f in table.fields) f.column: f.toLocal(data[f.key])};
    final parent = table.parent;
    if (parent != null) {
      final parentUid = data[parent.$3] as String?;
      int? parentId;
      if (parentUid != null) {
        parentId = (await txn.query(parent.$2, columns: ['id'], where: 'uid = ?', whereArgs: [parentUid]))
            .firstOrNull?['id'] as int?;
      }
      if (parentId == null && !(table.parentOptional && parentUid == null)) {
        // The parent hasn't arrived yet (or was deleted here): hold the row.
        await txn.insert(
          'sync_pending',
          {'table_name': table.local, 'uid': uid, 'payload': jsonEncode(row)},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return false;
      }
      values[parent.$1] = parentId;
    }
    values['sync_updated_at'] = updatedAt;
    values['dirty'] = 0;

    if (existing == null) {
      await txn.insert(table.local, {...values, 'uid': uid});
    } else {
      await txn.update(table.local, values, where: 'id = ?', whereArgs: [existing['id']]);
    }
    await _clearPending(txn, table, uid);
    return true;
  }

  Future<void> _clearPending(Transaction txn, SyncTable table, String uid) =>
      txn.delete('sync_pending', where: 'table_name = ? AND uid = ?', whereArgs: [table.local, uid]);

  /// Rows held back because their parent never arrived.
  Future<int> heldBackRows() async => Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM sync_pending'))!;

  /// Deletes every folder, note, question and problem on this device without
  /// telling the server (used after signing out), and forgets the account.
  Future<void> deleteLocalData() async {
    await db.transaction((txn) async {
      await txn.update('sync_state', {'applying': 1});
      for (final table in syncTables.reversed) {
        await txn.delete(table.local);
      }
      await txn.delete('sync_tombstones');
      await txn.delete('sync_pending');
      await txn.update('sync_state', {'applying': 0, 'cursor': 0, 'user_id': null, 'last_synced_at': null});
    });
  }
}
