/// Runs sync: push every local change, then pull everything newer than the
/// stored cursor (Docs/quillfin_plan.md §3). Runs on start, when the app
/// comes back to the foreground, shortly after local changes, every five
/// minutes while open, and on demand from Settings > Sync.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';

import 'convex_client.dart';
import 'sync_store.dart';

enum SyncPhase { idle, syncing, error }

@immutable
class SyncStatus {
  final SyncPhase phase;
  final DateTime? lastSyncedAt;

  /// Changes not yet pushed.
  final int pendingChanges;

  /// Notes too large to sync (over 200 KB), which stay on this device.
  final int oversizedNotes;

  /// What went wrong on the last run, for Settings > Sync.
  final String? error;

  /// The [ConvexException.code] of [error], if it came from the server.
  final String? errorCode;

  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.lastSyncedAt,
    this.pendingChanges = 0,
    this.oversizedNotes = 0,
    this.error,
    this.errorCode,
  });
}

class SyncService extends ValueNotifier<SyncStatus> with WidgetsBindingObserver {
  final SyncStore store;
  final ConvexClient client;

  /// The signed-in account (its Clerk user id).
  final String userId;

  /// Called after a pull changed local rows, so screens can refresh.
  final VoidCallback? onRemoteChanges;

  final Duration interval;
  final Duration changeCheckInterval;

  static const pullPageSize = 200;

  SyncService({
    required Database db,
    required this.client,
    required this.userId,
    this.onRemoteChanges,
    this.interval = const Duration(minutes: 5),
    this.changeCheckInterval = const Duration(seconds: 10),
  })  : store = SyncStore(db),
        super(const SyncStatus());

  Timer? _periodic;
  Timer? _changeCheck;
  Future<void>? _running;
  bool _again = false;
  bool _ensuredUser = false;
  bool _disposed = false;
  bool _observing = false;

  /// Starts the schedule and runs a first sync.
  void start() {
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
    _periodic = Timer.periodic(interval, (_) => syncNow());
    // sqflite has no change notifications, so look for dirty rows on a
    // short timer; the query only touches the partial `dirty` indexes.
    _changeCheck = Timer.periodic(changeCheckInterval, (_) async {
      if (_running == null && await store.pendingChanges() > 0) await syncNow();
    });
    syncNow();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) syncNow();
  }

  /// Syncs now. A call while a sync is running queues one more run after it,
  /// so a change made mid-sync is never left behind.
  Future<void> syncNow() {
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      await _syncOnce();
    } while (_again && !_disposed);
  }

  Future<void> _syncOnce() async {
    _set(SyncStatus(
      phase: SyncPhase.syncing,
      lastSyncedAt: value.lastSyncedAt,
      pendingChanges: value.pendingChanges,
      oversizedNotes: value.oversizedNotes,
    ));
    try {
      await store.bindUser(userId);
      if (!_ensuredUser) {
        await client.mutation('users:ensure');
        _ensuredUser = true;
      }
      await _push();
      final changed = await _pull();
      final now = DateTime.now().toUtc();
      await store.setLastSyncedAt(now);
      _set(SyncStatus(
        lastSyncedAt: now,
        pendingChanges: await store.pendingChanges(),
        oversizedNotes: await store.oversizedNotes(),
      ));
      if (changed > 0) onRemoteChanges?.call();
    } on ConvexException catch (e) {
      await _fail(e.message, e.code);
    } on DatabaseException catch (e) {
      // The database was closed under us (the shell was disposed).
      if (_disposed) return;
      await _fail('Sync failed: $e', null);
    }
  }

  Future<void> _push() async {
    for (var batch = await store.nextPushBatch(); !batch.isEmpty; batch = await store.nextPushBatch()) {
      await client.mutation('sync:push', {'changes': batch.changes});
      // Skipped rows lost to a newer server copy; the pull brings that down.
      await store.markPushed(batch);
    }
  }

  Future<int> _pull() async {
    var changed = 0;
    var cursor = await store.cursor();
    for (;;) {
      final page = Map<String, dynamic>.from(
        await client.query('sync:pull', {'since': cursor, 'limit': pullPageSize}) as Map,
      );
      changed += await store.applyPulled(Map<String, dynamic>.from(page['changes'] as Map));
      cursor = (page['cursor'] as num).toInt();
      await store.setCursor(cursor);
      if (page['hasMore'] != true) return changed;
    }
  }

  Future<void> _fail(String message, String? code) async {
    if (_disposed) return;
    var (lastSyncedAt, pending, oversized) = (value.lastSyncedAt, value.pendingChanges, value.oversizedNotes);
    try {
      (lastSyncedAt, pending, oversized) =
          (await store.lastSyncedAt(), await store.pendingChanges(), await store.oversizedNotes());
    } on DatabaseException {
      // The database is what failed; keep the last known counts.
    }
    _set(SyncStatus(
      phase: SyncPhase.error,
      lastSyncedAt: lastSyncedAt,
      pendingChanges: pending,
      oversizedNotes: oversized,
      error: message,
      errorCode: code,
    ));
  }

  void _set(SyncStatus status) {
    if (!_disposed) value = status;
  }

  @override
  void dispose() {
    _disposed = true;
    _periodic?.cancel();
    _changeCheck?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
