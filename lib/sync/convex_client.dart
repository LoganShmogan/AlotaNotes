/// A minimal client for Convex's HTTP API (`POST /api/query`, `/api/mutation`,
/// `/api/action`). Sync is request/response by nature, so the app doesn't
/// need Convex's WebSocket protocol (see Docs/quillfin_plan.md §2).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A failed call. [code] is the backend's ConvexError code (e.g.
/// `NOTE_TOO_LARGE`, `AI_LIMIT_REACHED`, see Docs/backend.md), or one of
/// [networkError], [unauthenticated] and [serverError].
class ConvexException implements Exception {
  static const networkError = 'NETWORK';
  static const unauthenticated = 'UNAUTHENTICATED';
  static const serverError = 'SERVER_ERROR';

  final String code;
  final String message;
  final Map<String, dynamic> data;
  const ConvexException(this.code, this.message, [this.data = const {}]);

  @override
  String toString() => message;
}

/// Returns a current ID token, or null when signed out.
typedef TokenProvider = Future<String?> Function();

class ConvexClient {
  final Uri deploymentUrl;
  final TokenProvider token;
  final http.Client httpClient;
  final Duration timeout;

  ConvexClient({
    required this.deploymentUrl,
    required this.token,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
  }) : httpClient = httpClient ?? http.Client();

  Future<dynamic> query(String path, [Map<String, dynamic> args = const {}]) => _call('query', path, args);

  Future<dynamic> mutation(String path, [Map<String, dynamic> args = const {}]) => _call('mutation', path, args);

  Future<dynamic> action(String path, [Map<String, dynamic> args = const {}]) => _call('action', path, args);

  Future<dynamic> _call(String kind, String path, Map<String, dynamic> args) async {
    String? bearer;
    try {
      bearer = await token();
    } catch (e) {
      // Refreshing the sign-in needs the network too.
      throw ConvexException(ConvexException.networkError, "Couldn't refresh your sign-in: $e");
    }
    if (bearer == null) {
      throw const ConvexException(ConvexException.unauthenticated, 'Your session has expired. Sign in again to sync.');
    }
    http.Response response;
    try {
      response = await httpClient
          .post(
            deploymentUrl.resolve('/api/$kind'),
            headers: {'content-type': 'application/json', 'authorization': 'Bearer $bearer'},
            body: jsonEncode({'path': path, 'args': args, 'format': 'json'}),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const ConvexException(ConvexException.networkError, "QuillFin's server didn't respond.");
    } catch (e) {
      throw ConvexException(ConvexException.networkError, "Couldn't reach QuillFin's server: $e");
    }

    Map<String, dynamic>? body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      body = null;
    }
    if (response.statusCode == 200 && body?['status'] == 'success') return body!['value'];

    final errorData = body?['errorData'];
    if (errorData is Map && errorData['code'] is String) {
      final data = Map<String, dynamic>.from(errorData);
      throw ConvexException(data['code'] as String, (data['message'] as String?) ?? data['code'] as String, data);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const ConvexException(ConvexException.unauthenticated, 'Your session has expired. Sign in again.');
    }
    // Uncaught server errors carry only a generic message; don't show it.
    throw ConvexException(
      ConvexException.serverError,
      "QuillFin's server had a problem (HTTP ${response.statusCode}). Try again shortly.",
    );
  }
}
