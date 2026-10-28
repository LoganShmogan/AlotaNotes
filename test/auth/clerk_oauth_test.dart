import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:quillfin/auth/auth_service.dart';
import 'package:quillfin/auth/browser_auth.dart';
import 'package:quillfin/auth/clerk_oauth.dart';

import '../helpers/fake_auth.dart';
import '../helpers/fake_url_launcher.dart';

void main() {
  group('ClerkOAuth.signIn', () {
    late FakeBrowserAuth browser;
    late List<http.Request> tokenRequests;
    late http.Response Function() tokenResponse;

    ClerkOAuth clerk() => ClerkOAuth(
          config: testCloudConfig,
          browser: browser,
          random: Random(1),
          httpClient: MockClient((request) async {
            tokenRequests.add(request);
            return tokenResponse();
          }),
        );

    setUp(() {
      browser = FakeBrowserAuth()..approveWith('code-1');
      tokenRequests = [];
      tokenResponse = () => http.Response(jsonEncode({'id_token': idTokenFor('u1'), 'refresh_token': 'r1'}), 200);
    });

    test('sends a PKCE S256 request and exchanges the code with the verifier', () async {
      final tokens = await clerk().signIn();
      expect(tokens.refreshToken, 'r1');

      final query = browser.lastAuthorizeUrl!.queryParameters;
      expect(browser.lastAuthorizeUrl!.replace(query: '').toString(), 'https://clerk.quillfin.test/oauth/authorize?');
      expect(query['response_type'], 'code');
      expect(query['client_id'], 'client_123');
      expect(query['redirect_uri'], 'http://127.0.0.1:47615/callback');
      expect(query['scope'], 'openid profile email');
      expect(query['code_challenge_method'], 'S256');

      final form = tokenRequests.single.bodyFields;
      expect(form['grant_type'], 'authorization_code');
      expect(form['code'], 'code-1');
      expect(form['redirect_uri'], 'http://127.0.0.1:47615/callback');
      expect(codeChallenge(form['code_verifier']!), query['code_challenge']);
      expect(form['code_verifier'], hasLength(64));
    });

    test('the RFC 7636 example challenge matches', () {
      expect(codeChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'), 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    });

    test('rejects a response for a different request', () async {
      browser.respond = (_) => browser.redirectUri.replace(queryParameters: {'code': 'c', 'state': 'forged'});
      await expectLater(clerk().signIn(), throwsA(isA<AuthException>().having((e) => e.message, 'message', contains('did not match'))));
      expect(tokenRequests, isEmpty);
    });

    test('treats a denied consent as a cancel, and reports other errors', () async {
      browser.respond = (url) =>
          browser.redirectUri.replace(queryParameters: {'error': 'access_denied', 'state': url.queryParameters['state']});
      await expectLater(clerk().signIn(), throwsA(isA<AuthCancelled>()));

      browser.respond = (url) => browser.redirectUri.replace(queryParameters: {
            'error': 'server_error',
            'error_description': 'Clerk is down',
            'state': url.queryParameters['state'],
          });
      await expectLater(clerk().signIn(), throwsA(isA<AuthException>().having((e) => e.message, 'm', contains('Clerk is down'))));

      browser.respond = (url) => browser.redirectUri.replace(queryParameters: {'state': url.queryParameters['state']});
      await expectLater(clerk().signIn(), throwsA(isA<AuthException>().having((e) => e.message, 'm', contains('no authorization code'))));
    });

    test('reports token endpoint failures', () async {
      for (final (response, message) in [
        (http.Response('{}', 400), 'Sign-in failed (HTTP 400)'),
        (http.Response('{}', 503), 'HTTP 503'),
        (http.Response('{}', 200), 'no ID token'),
      ]) {
        tokenResponse = () => response;
        await expectLater(clerk().signIn(), throwsA(isA<AuthException>().having((e) => e.message, 'm', contains(message))));
      }
    });

    test('reports an unreachable sign-in service', () async {
      final offline = ClerkOAuth(
        config: testCloudConfig,
        browser: browser,
        httpClient: MockClient((_) => throw http.ClientException('offline')),
      );
      await expectLater(offline.signIn(), throwsA(isA<AuthException>().having((e) => e.message, 'm', contains("Couldn't reach"))));
    });

    test('a refused refresh is a SessionExpired; a rotated refresh token is kept', () async {
      tokenResponse = () => http.Response('{}', 401);
      await expectLater(clerk().refresh('r1'), throwsA(isA<SessionExpired>()));

      tokenResponse = () => http.Response(jsonEncode({'id_token': idTokenFor('u1'), 'refresh_token': 'r2'}), 200);
      expect((await clerk().refresh('r1')).refreshToken, 'r2');
    });
  });

  group('LoopbackBrowserAuth', () {
    // Port 0 asks the OS for a free port, but the redirect must name it, so
    // tests use a fixed high port of their own.
    const port = 47699;

    test('listens on loopback, opens the browser, and returns the redirect', () async {
      late Uri opened;
      final auth = LoopbackBrowserAuth(port: port, openUrl: (url) async {
        opened = url;
        // The "browser" follows Clerk's redirect back to the app.
        unawaited(Future(() async {
          final client = HttpClient();
          final notFound = await (await client.getUrl(Uri.parse('http://127.0.0.1:$port/favicon.ico'))).close();
          expect(notFound.statusCode, 404);
          await notFound.drain<void>();
          final response = await (await client.getUrl(Uri.parse('http://127.0.0.1:$port/callback?code=abc&state=s'))).close();
          expect(await response.transform(utf8.decoder).join(), contains("You're signed in"));
          client.close();
        }));
        return true;
      });
      expect(auth.redirectUri.toString(), 'http://127.0.0.1:$port/callback');

      final redirect = await auth.authorize(Uri.parse('https://clerk.quillfin.test/oauth/authorize'));
      expect(opened.host, 'clerk.quillfin.test');
      expect(redirect.toString(), 'http://127.0.0.1:$port/callback?code=abc&state=s');
      expect(auth.listening, isFalse);
    });

    test('fails clearly if the browser cannot open, the port is taken, or it times out', () async {
      await expectLater(
        LoopbackBrowserAuth(port: port, openUrl: (_) async => false).authorize(Uri.parse('https://x')),
        throwsA(isA<AuthException>().having((e) => e.message, 'm', contains("Couldn't open the browser"))),
      );

      final blocker = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await expectLater(
        LoopbackBrowserAuth(port: port, openUrl: (_) async => true).authorize(Uri.parse('https://x')),
        throwsA(isA<AuthException>().having((e) => e.message, 'm', contains('in use'))),
      );
      await blocker.close();

      await expectLater(
        LoopbackBrowserAuth(port: port, openUrl: (_) async => true, timeout: const Duration(milliseconds: 20))
            .authorize(Uri.parse('https://x')),
        throwsA(isA<AuthException>().having((e) => e.message, 'm', 'Sign-in timed out.')),
      );
    });

    test('cancel stops the wait and frees the port', () async {
      final auth = LoopbackBrowserAuth(port: port, openUrl: (_) async => true);
      auth.cancel(); // nothing pending yet
      final waiting = auth.authorize(Uri.parse('https://x'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      auth.cancel();
      await expectLater(waiting, throwsA(isA<AuthCancelled>()));
      expect(auth.listening, isFalse);
    });
  });

  group('DeepLinkBrowserAuth', () {
    test('returns the first matching link back into the app', () async {
      final links = StreamController<Uri>.broadcast();
      final auth = DeepLinkBrowserAuth(links: links.stream, openUrl: (_) async {
        Future(() {
          links.add(Uri.parse('https://example.com/other'));
          links.add(Uri.parse('com.savepoint.quillfin://callback?code=abc'));
        });
        return true;
      });
      expect(auth.redirectUri.toString(), 'com.savepoint.quillfin://callback');
      expect((await auth.authorize(Uri.parse('https://x'))).queryParameters['code'], 'abc');
      await links.close();
    });

    test('fails if the browser cannot open, times out, or is cancelled', () async {
      final links = StreamController<Uri>.broadcast();
      await expectLater(
        DeepLinkBrowserAuth(links: links.stream, openUrl: (_) async => false).authorize(Uri.parse('https://x')),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        DeepLinkBrowserAuth(links: links.stream, openUrl: (_) async => true, timeout: const Duration(milliseconds: 20))
            .authorize(Uri.parse('https://x')),
        throwsA(isA<AuthException>().having((e) => e.message, 'm', 'Sign-in timed out.')),
      );
      final auth = DeepLinkBrowserAuth(links: links.stream, openUrl: (_) async => true);
      auth.cancel();
      final waiting = auth.authorize(Uri.parse('https://x'));
      await Future<void>.delayed(Duration.zero);
      auth.cancel();
      await expectLater(waiting, throwsA(isA<AuthCancelled>()));
      await links.close();
    });
  });

  test('platformBrowserAuth uses the loopback flow on desktop and deep links on phones', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(platformBrowserAuth(), isA<LoopbackBrowserAuth>());
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(platformBrowserAuth(), isA<DeepLinkBrowserAuth>());
  });

  test('by default the system browser is opened through url_launcher', () async {
    final launcher = FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
    await expectLater(
      LoopbackBrowserAuth(port: 47698, timeout: const Duration(milliseconds: 20)).authorize(Uri.parse('https://clerk.quillfin.test/a')),
      throwsA(isA<AuthException>()),
    );
    expect(launcher.launched, ['https://clerk.quillfin.test/a']);
  });

  test('defaults: a real HTTP client, and messages as strings', () {
    expect(ClerkOAuth(config: testCloudConfig, browser: FakeBrowserAuth()).httpClient, isA<http.Client>());
    expect(const AuthException('Nope').toString(), 'Nope');
  });
}
