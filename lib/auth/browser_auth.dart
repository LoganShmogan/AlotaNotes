/// The browser half of OAuth sign-in: open Clerk's sign-in page in the
/// system browser (never an embedded web view, per RFC 8252) and wait for
/// Clerk to redirect back with the authorization code.
///
/// - Android and iOS: Clerk redirects to `com.savepoint.quillfin://callback`,
///   which the OS hands back to the app (registered in AndroidManifest.xml
///   and Info.plist, received with app_links).
/// - Windows, Linux and macOS: Clerk redirects to a loopback address the app
///   is listening on for the length of the sign-in.
library;

import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_service.dart';

typedef UrlOpener = Future<bool> Function(Uri url);

Future<bool> _openInBrowser(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);

const signInTimeout = Duration(minutes: 5);

abstract class BrowserAuth {
  /// Where Clerk sends the browser back to; must be registered in Clerk.
  Uri get redirectUri;

  /// Opens [authorizeUrl] and completes with the redirect, query included.
  Future<Uri> authorize(Uri authorizeUrl);

  /// Stops waiting; a pending [authorize] fails with [AuthCancelled].
  void cancel();
}

/// The browser for this platform.
BrowserAuth platformBrowserAuth() {
  final mobile = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  if (!kIsWeb && mobile) {
    return DeepLinkBrowserAuth(links: AppLinks().uriLinkStream);
  }
  return LoopbackBrowserAuth();
}

class DeepLinkBrowserAuth implements BrowserAuth {
  final Stream<Uri> links;
  final UrlOpener openUrl;
  final Duration timeout;
  Completer<Uri>? _pending;

  DeepLinkBrowserAuth({required this.links, this.openUrl = _openInBrowser, this.timeout = signInTimeout});

  @override
  final redirectUri = Uri.parse('com.savepoint.quillfin://callback');

  @override
  Future<Uri> authorize(Uri authorizeUrl) async {
    final pending = _pending = Completer<Uri>();
    final subscription = links.listen((uri) {
      if (uri.scheme == redirectUri.scheme && uri.host == redirectUri.host && !pending.isCompleted) {
        pending.complete(uri);
      }
    });
    try {
      if (!await openUrl(authorizeUrl)) throw const AuthException("Couldn't open the browser to sign in.");
      return await pending.future.timeout(timeout, onTimeout: () => throw const AuthException('Sign-in timed out.'));
    } finally {
      await subscription.cancel();
      _pending = null;
    }
  }

  @override
  void cancel() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.completeError(const AuthCancelled());
  }
}

class LoopbackBrowserAuth implements BrowserAuth {
  /// Fixed, because Clerk matches redirect URIs exactly.
  static const defaultPort = 47615;

  final int port;
  final UrlOpener openUrl;
  final Duration timeout;
  HttpServer? _server;
  Completer<Uri>? _pending;

  LoopbackBrowserAuth({this.port = defaultPort, this.openUrl = _openInBrowser, this.timeout = signInTimeout});

  @override
  Uri get redirectUri => Uri.parse('http://127.0.0.1:$port/callback');

  @override
  Future<Uri> authorize(Uri authorizeUrl) async {
    final HttpServer server;
    try {
      server = _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException {
      throw AuthException('Port $port is in use, so sign-in can\'t finish. Close whatever is using it and try again.');
    }
    final pending = _pending = Completer<Uri>();
    server.listen((request) async {
      if (request.uri.path != redirectUri.path) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.html;
      request.response.write(_signedInPage);
      await request.response.close();
      if (!pending.isCompleted) pending.complete(redirectUri.replace(query: request.uri.query));
    });
    try {
      if (!await openUrl(authorizeUrl)) throw const AuthException("Couldn't open the browser to sign in.");
      return await pending.future.timeout(timeout, onTimeout: () => throw const AuthException('Sign-in timed out.'));
    } finally {
      await server.close(force: true);
      _server = null;
      _pending = null;
    }
  }

  @override
  void cancel() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.completeError(const AuthCancelled());
  }

  @visibleForTesting
  bool get listening => _server != null;
}

const _signedInPage = '''
<!doctype html><meta charset="utf-8"><title>QuillFin</title>
<body style="font-family:system-ui,sans-serif;display:grid;place-items:center;height:90vh;color:#12212E;background:#F7F6F2">
<div style="text-align:center"><h1 style="font-weight:600">You're signed in to QuillFin</h1>
<p>You can close this tab and go back to the app.</p></div>''';
