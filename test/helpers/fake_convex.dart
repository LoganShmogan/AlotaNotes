// An in-memory stand-in for the Convex backend (backend/convex/), behind
// Convex's HTTP API, so sync and billing can be tested end to end across
// several "devices" without a server. It follows the real functions' rules:
// last-writer-wins on updatedAt, tombstones, and a per-user seq for pull.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeConvex {
  /// Bearer token -> user id. Calls with any other token are unauthenticated.
  final Map<String, String> tokens = {'token-alice': 'user_alice', 'token-bob': 'user_bob'};

  final Map<String, Map<String, Map<String, Map<String, dynamic>>>> _rows = {};
  final Map<String, int> _seq = {};

  /// Every call made, as `kind:path`.
  final List<String> calls = [];

  /// Makes the next call to [path] fail with this ConvexError data.
  final Map<String, Map<String, dynamic>> failNext = {};

  /// Makes every call fail as if the network were down.
  bool offline = false;

  /// What `billing:me` returns, per user.
  final Map<String, Map<String, dynamic>> billing = {};

  /// Handlers for any other function, e.g. `ai:generateQuestions`.
  final Map<String, dynamic Function(String user, Map<String, dynamic> args)> handlers = {};

  late final http.Client httpClient = MockClient((request) async {
    if (offline) throw http.ClientException('Network is unreachable');
    final kind = request.url.path.split('/').last;
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final path = body['path'] as String;
    final args = Map<String, dynamic>.from(body['args'] as Map);
    calls.add('$kind:$path');
    final user = tokens[request.headers['authorization']?.replaceFirst('Bearer ', '')];
    if (user == null) return _error({'code': 'UNAUTHENTICATED', 'message': 'Sign in to continue.'});
    final failure = failNext.remove(path);
    if (failure != null) return _error(failure);
    return _success(_handle(user, path, args));
  });

  http.Response _success(Object? value) =>
      http.Response(jsonEncode({'status': 'success', 'value': value, 'logLines': []}), 200);

  http.Response _error(Map<String, dynamic> data) => http.Response(
        jsonEncode({'status': 'error', 'errorMessage': data['message'], 'errorData': data, 'logLines': []}),
        400,
      );

  Object? _handle(String user, String path, Map<String, dynamic> args) {
    switch (path) {
      case 'users:ensure':
        return null;
      case 'sync:push':
        return _push(user, Map<String, dynamic>.from(args['changes'] as Map));
      case 'sync:pull':
        return _pull(user, (args['since'] as num).toInt(), (args['limit'] as num?)?.toInt() ?? 200);
      case 'billing:me':
        return billing[user] ?? freePlan();
    }
    final handler = handlers[path];
    if (handler == null) throw StateError('FakeConvex has no handler for $path');
    return handler(user, args);
  }

  Map<String, int> _push(String user, Map<String, dynamic> changes) {
    var applied = 0, skipped = 0;
    final tables = _rows.putIfAbsent(user, () => {});
    for (final MapEntry(key: table, value: rows) in changes.entries) {
      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final existing = tables[table]?[row['uid']];
        if (existing != null && (row['updatedAt'] as num) <= (existing['updatedAt'] as num)) {
          skipped++;
          continue;
        }
        final deleted = row['deletedAt'] != null;
        _seq[user] = (_seq[user] ?? 0) + 1;
        (tables[table] ??= {})[row['uid'] as String] = {
          'uid': row['uid'],
          'updatedAt': row['updatedAt'],
          'deletedAt': row['deletedAt'],
          'data': deleted ? null : row['data'],
          'seq': _seq[user],
        };
        applied++;
      }
    }
    return {'applied': applied, 'skipped': skipped};
  }

  Map<String, dynamic> _pull(String user, int since, int limit) {
    final all = <(String, Map<String, dynamic>)>[
      for (final MapEntry(key: table, value: rows) in (_rows[user] ?? {}).entries)
        for (final row in rows.values)
          if ((row['seq'] as int) > since) (table, row),
    ]..sort((a, b) => (a.$2['seq'] as int).compareTo(b.$2['seq'] as int));
    final page = all.take(limit).toList();
    final changes = <String, List<Map<String, dynamic>>>{};
    for (final (table, row) in page) {
      (changes[table] ??= []).add({
        'uid': row['uid'],
        'updatedAt': row['updatedAt'],
        'deletedAt': row['deletedAt'],
        'data': row['data'],
      });
    }
    return {'changes': changes, 'cursor': page.isEmpty ? since : page.last.$2['seq'], 'hasMore': all.length > limit};
  }

  /// The server's rows for [user] in [table], keyed by uid.
  Map<String, Map<String, dynamic>> rows(String user, String table) => _rows[user]?[table] ?? {};

  static Map<String, dynamic> freePlan({int used = 0}) => {
        'plan': 'free',
        'planName': 'Free',
        'aiNotes': {'period': '2026-10', 'used': used, 'limit': 20},
        'subscription': null,
        'upgradeAvailable': true,
      };

  static Map<String, dynamic> proPlan({bool cancelAtPeriodEnd = false}) => {
        'plan': 'pro',
        'planName': 'Pro',
        'aiNotes': {'period': '2026-10', 'used': 3, 'limit': 500},
        'subscription': {
          'status': 'active',
          'interval': 'year',
          'currentPeriodEnd': DateTime.utc(2027, 10, 28).millisecondsSinceEpoch,
          'cancelAtPeriodEnd': cancelAtPeriodEnd,
        },
        'upgradeAvailable': true,
      };
}
