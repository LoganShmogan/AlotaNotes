/// Who is using the app. Two ways in:
/// - a QuillFin account (Clerk), which syncs through Convex;
/// - "Continue on this device", which keeps everything local, as the app
///   always has. It's the only way in when the build has no cloud config.
/// The session survives restarts in secure storage.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../sync/convex_client.dart';
import 'clerk_oauth.dart';

class AppUser {
  /// The Clerk user id, or [localId] for a device-only session.
  final String id;
  final String displayName;
  final String? email;

  static const localId = 'local';

  const AppUser({required this.id, required this.displayName, this.email});

  const AppUser.local() : this(id: localId, displayName: 'This device');

  bool get isLocal => id == localId;
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

/// The user closed or cancelled the sign-in.
class AuthCancelled extends AuthException {
  const AuthCancelled() : super('Sign-in was cancelled.');
}

/// The account session can't be refreshed any more; sign in again.
class SessionExpired extends AuthException {
  const SessionExpired() : super('Your session has expired. Sign in again to keep syncing.');
}

abstract class AuthService {
  /// Whether this build can sign in to a QuillFin account.
  bool get cloudAvailable;

  Future<AppUser?> currentUser();

  /// Signs in to a QuillFin account through the browser.
  Future<AppUser> signIn();

  /// Abandons a [signIn] waiting on the browser.
  void cancelSignIn();

  /// Uses the app without an account.
  Future<AppUser> continueOnDevice();

  Future<void> signOut();

  /// A current ID token for Convex: null for a device-only session or one
  /// that has expired.
  Future<String?> idToken();

  /// A client for QuillFin's backend that signs its calls with [idToken],
  /// or null when this build has no cloud config.
  ConvexClient? convexClient();
}

class QuillFinAuthService implements AuthService {
  static const storageKey = 'quillfin_session';

  /// Refresh this long before the ID token expires.
  static const refreshMargin = Duration(seconds: 60);

  final ClerkOAuth? clerk;
  final FlutterSecureStorage storage;
  final DateTime Function() clock;

  QuillFinAuthService({this.clerk, this.storage = const FlutterSecureStorage(), DateTime Function()? clock})
      : clock = clock ?? (() => DateTime.now().toUtc());

  Map<String, dynamic>? _session;
  bool _loaded = false;
  Future<String?>? _refreshing;

  @override
  bool get cloudAvailable => clerk != null;

  Future<Map<String, dynamic>?> _load() async {
    if (!_loaded) {
      final raw = await storage.read(key: storageKey);
      _session = raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
      _loaded = true;
    }
    return _session;
  }

  Future<void> _save(Map<String, dynamic>? session) async {
    _session = session;
    _loaded = true;
    if (session == null) {
      await storage.delete(key: storageKey);
    } else {
      await storage.write(key: storageKey, value: jsonEncode(session));
    }
  }

  Future<void> _saveTokens(ClerkTokens tokens) =>
      _save({'mode': 'clerk', 'idToken': tokens.idToken, 'refreshToken': tokens.refreshToken});

  ClerkTokens _tokens(Map<String, dynamic> session) =>
      ClerkTokens(idToken: session['idToken'] as String, refreshToken: session['refreshToken'] as String?);

  @override
  Future<AppUser?> currentUser() async {
    final session = await _load();
    return switch (session?['mode']) {
      'local' => const AppUser.local(),
      'clerk' => _tokens(session!).user,
      _ => null,
    };
  }

  @override
  Future<AppUser> signIn() async {
    final clerk = this.clerk;
    if (clerk == null) throw const AuthException("This version of QuillFin can't sign in to an account.");
    final tokens = await clerk.signIn();
    await _saveTokens(tokens);
    return tokens.user;
  }

  @override
  void cancelSignIn() => clerk?.browser.cancel();

  @override
  Future<AppUser> continueOnDevice() async {
    await _save({'mode': 'local'});
    return const AppUser.local();
  }

  @override
  Future<void> signOut() => _save(null);

  @override
  Future<String?> idToken() async {
    final session = await _load();
    if (session?['mode'] != 'clerk') return null;
    final tokens = _tokens(session!);
    if (tokens.expiresAt.subtract(refreshMargin).isAfter(clock())) return tokens.idToken;
    // One refresh at a time, however many calls arrive together.
    return _refreshing ??= _refresh(tokens).whenComplete(() => _refreshing = null);
  }

  @override
  ConvexClient? convexClient() {
    final clerk = this.clerk;
    if (clerk == null) return null;
    return ConvexClient(deploymentUrl: clerk.config.convexDeployment, token: idToken, httpClient: clerk.httpClient);
  }

  Future<String?> _refresh(ClerkTokens tokens) async {
    final refreshToken = tokens.refreshToken;
    if (refreshToken == null || clerk == null) return null;
    try {
      final fresh = await clerk!.refresh(refreshToken);
      await _saveTokens(fresh);
      return fresh.idToken;
    } on SessionExpired {
      // Keep the user (and their local data) signed in on this device; sync
      // reports that they need to sign in again.
      return null;
    }
  }
}
