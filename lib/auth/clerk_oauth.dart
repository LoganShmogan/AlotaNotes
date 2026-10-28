/// Clerk sign-in as an OAuth 2.0 public client: authorization code with
/// PKCE through the system browser, then refresh tokens to keep the ID
/// token current. The ID token is what Convex accepts from this app (its
/// audience is the OAuth client id, see backend/convex/auth.config.ts).
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../config/cloud_config.dart';
import 'auth_service.dart';
import 'browser_auth.dart';

class ClerkTokens {
  final String idToken;
  final String? refreshToken;
  const ClerkTokens({required this.idToken, this.refreshToken});

  Map<String, dynamic> get claims => decodeJwtPayload(idToken);

  /// When the ID token expires (its `exp` claim).
  DateTime get expiresAt => DateTime.fromMillisecondsSinceEpoch((claims['exp'] as num).toInt() * 1000, isUtc: true);

  AppUser get user {
    final c = claims;
    final email = c['email'] as String?;
    final fullName = [c['given_name'], c['family_name']].whereType<String>().join(' ');
    final name = (c['name'] as String?) ?? (fullName.isEmpty ? null : fullName);
    return AppUser(id: c['sub'] as String, displayName: name ?? email ?? 'QuillFin account', email: email);
  }
}

/// The payload of a JWT, unverified: the server verifies the signature.
Map<String, dynamic> decodeJwtPayload(String token) {
  final parts = token.split('.');
  if (parts.length != 3) throw const FormatException('Not a JWT');
  return jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
}

/// The PKCE S256 challenge for [verifier] (RFC 7636).
String codeChallenge(String verifier) => base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

class ClerkOAuth {
  final CloudConfig config;
  final BrowserAuth browser;
  final http.Client httpClient;
  final Random _random;

  ClerkOAuth({required this.config, required this.browser, http.Client? httpClient, Random? random})
      : httpClient = httpClient ?? http.Client(),
        _random = random ?? Random.secure();

  static const scopes = 'openid profile email';

  String _randomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return List.generate(length, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  Future<ClerkTokens> signIn() async {
    final verifier = _randomString(64);
    final state = _randomString(24);
    final authorizeUrl = config.clerkBase.resolve('/oauth/authorize').replace(queryParameters: {
      'response_type': 'code',
      'client_id': config.clerkClientId,
      'redirect_uri': browser.redirectUri.toString(),
      'scope': scopes,
      'state': state,
      'code_challenge': codeChallenge(verifier),
      'code_challenge_method': 'S256',
    });
    final redirect = await browser.authorize(authorizeUrl);
    final params = redirect.queryParameters;
    if (params['state'] != state) throw const AuthException('Sign-in failed: the response did not match the request.');
    final error = params['error'];
    if (error != null) {
      if (error == 'access_denied') throw const AuthCancelled();
      throw AuthException('Sign-in failed: ${params['error_description'] ?? error}');
    }
    final code = params['code'];
    if (code == null) throw const AuthException('Sign-in failed: no authorization code came back.');
    return _token({
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': browser.redirectUri.toString(),
      'client_id': config.clerkClientId,
      'code_verifier': verifier,
    });
  }

  /// A fresh ID token. Throws [SessionExpired] if Clerk refuses the refresh
  /// token (signed out elsewhere, or revoked).
  Future<ClerkTokens> refresh(String refreshToken) async {
    final tokens = await _token({
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': config.clerkClientId,
    }, refreshing: true);
    // Clerk may or may not rotate the refresh token.
    return ClerkTokens(idToken: tokens.idToken, refreshToken: tokens.refreshToken ?? refreshToken);
  }

  Future<ClerkTokens> _token(Map<String, String> form, {bool refreshing = false}) async {
    http.Response response;
    try {
      response = await httpClient.post(config.clerkBase.resolve('/oauth/token'), body: form);
    } catch (e) {
      throw AuthException("Couldn't reach the sign-in service: $e");
    }
    if (response.statusCode == 400 || response.statusCode == 401) {
      if (refreshing) throw const SessionExpired();
      throw AuthException('Sign-in failed (HTTP ${response.statusCode}).');
    }
    if (response.statusCode != 200) throw AuthException('The sign-in service had a problem (HTTP ${response.statusCode}).');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final idToken = body['id_token'] as String?;
    if (idToken == null) throw const AuthException('Sign-in failed: no ID token came back.');
    return ClerkTokens(idToken: idToken, refreshToken: body['refresh_token'] as String?);
  }
}
