// Auth for tests: device-only sessions, account sessions backed by
// FakeConvex, and a scripted browser for the OAuth flow.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'package:quillfin/auth/auth_service.dart';
import 'package:quillfin/auth/browser_auth.dart';
import 'package:quillfin/auth/clerk_oauth.dart';
import 'package:quillfin/config/cloud_config.dart';

import 'fake_convex.dart';

const testCloudConfig = CloudConfig(
  clerkDomain: 'clerk.quillfin.test',
  clerkClientId: 'client_123',
  convexUrl: 'https://quillfin-test.convex.cloud',
);

/// An unsigned JWT with [claims]; the app never verifies signatures.
String jwt(Map<String, Object?> claims) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'RS256', 'typ': 'JWT'})}.${part(claims)}.sig';
}

/// An ID token for [sub] that expires [expiresIn] from now.
String idTokenFor(String sub, {Duration expiresIn = const Duration(hours: 1), String? email, String? name}) => jwt({
      'sub': sub,
      'exp': DateTime.now().add(expiresIn).millisecondsSinceEpoch ~/ 1000,
      'email': ?email,
      'name': ?name,
    });

/// A browser that, instead of opening anything, answers with [respond].
class FakeBrowserAuth implements BrowserAuth {
  Uri? lastAuthorizeUrl;
  FutureOr<Uri> Function(Uri authorizeUrl)? respond;
  Completer<Uri>? _pending;
  int cancels = 0;

  @override
  final redirectUri = Uri.parse('http://127.0.0.1:47615/callback');

  /// Answers like Clerk does after a successful sign-in.
  void approveWith(String code) {
    respond = (url) => redirectUri.replace(queryParameters: {'code': code, 'state': url.queryParameters['state']});
  }

  /// Leaves the sign-in waiting until [cancel] (or [finish]).
  void hang() => respond = (_) => (_pending = Completer<Uri>()).future;

  @override
  Future<Uri> authorize(Uri authorizeUrl) async {
    lastAuthorizeUrl = authorizeUrl;
    return respond!(authorizeUrl);
  }

  @override
  void cancel() {
    cancels++;
    if (_pending?.isCompleted == false) _pending!.completeError(const AuthCancelled());
  }
}

QuillFinAuthService localAuth() => QuillFinAuthService();

Future<QuillFinAuthService> signedInLocally() async {
  final auth = localAuth();
  await auth.continueOnDevice();
  return auth;
}

/// An auth service that can sign in (with [browser]) and whose Convex calls
/// go to [server].
QuillFinAuthService cloudAuth(FakeConvex server, {FakeBrowserAuth? browser, http.Client? httpClient}) =>
    QuillFinAuthService(
      clerk: ClerkOAuth(config: testCloudConfig, browser: browser ?? FakeBrowserAuth(), httpClient: httpClient ?? server.httpClient),
    );

/// Signed in to an account as [user], with [server] accepting the token.
Future<QuillFinAuthService> signedInToCloud(
  FakeConvex server, {
  String user = 'user_alice',
  String email = 'alice@example.com',
  String name = 'Alice',
}) async {
  final token = idTokenFor(user, email: email, name: name);
  server.tokens[token] = user;
  await const FlutterSecureStorage().write(
    key: QuillFinAuthService.storageKey,
    value: jsonEncode({'mode': 'clerk', 'idToken': token, 'refreshToken': 'refresh-1'}),
  );
  return cloudAuth(server);
}
