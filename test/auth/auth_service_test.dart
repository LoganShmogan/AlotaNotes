import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:quillfin/auth/auth_service.dart';
import 'package:quillfin/auth/clerk_oauth.dart';

import '../helpers/fake_auth.dart';
import '../helpers/fake_convex.dart';
import '../helpers/test_env.dart';

void main() {
  setUpTestEnv();

  group('device-only', () {
    test('no one is signed in at first, and a build without config has no accounts', () async {
      final auth = localAuth();
      expect(await auth.currentUser(), isNull);
      expect(auth.cloudAvailable, isFalse);
      expect(auth.convexClient(), isNull);
      expect(await auth.idToken(), isNull);
      await expectLater(auth.signIn(), throwsA(isA<AuthException>()));
      auth.cancelSignIn(); // nothing to cancel
    });

    test('continuing on this device survives a restart, and signing out ends it', () async {
      await localAuth().continueOnDevice();
      final later = localAuth();
      final user = await later.currentUser();
      expect((user?.isLocal, user?.displayName), (true, 'This device'));
      expect(await later.idToken(), isNull);

      await later.signOut();
      expect(await localAuth().currentUser(), isNull);
    });
  });

  group('QuillFin account', () {
    late FakeConvex server;
    setUp(() => server = FakeConvex());

    test('signing in stores the tokens and reads the user from the ID token', () async {
      final browser = FakeBrowserAuth()..approveWith('code-1');
      final idToken = idTokenFor('user_alice', email: 'alice@example.com', name: 'Alice');
      final clerk = MockClient((request) async {
        expect(request.url.toString(), 'https://clerk.quillfin.test/oauth/token');
        expect(request.bodyFields['code'], 'code-1');
        return http.Response(jsonEncode({'id_token': idToken, 'refresh_token': 'r1'}), 200);
      });
      final auth = cloudAuth(server, browser: browser, httpClient: clerk);
      expect(auth.cloudAvailable, isTrue);

      final user = await auth.signIn();
      expect((user.id, user.displayName, user.email, user.isLocal), ('user_alice', 'Alice', 'alice@example.com', false));
      expect(await auth.idToken(), idToken);

      final stored = jsonDecode((await const FlutterSecureStorage().read(key: QuillFinAuthService.storageKey))!);
      expect(stored, {'mode': 'clerk', 'idToken': idToken, 'refreshToken': 'r1'});
      expect((await cloudAuth(server).currentUser())?.id, 'user_alice');
    });

    test('an ID token about to expire is refreshed once, however many ask', () async {
      var refreshes = 0;
      final fresh = idTokenFor('user_alice');
      final clerk = MockClient((request) async {
        refreshes++;
        expect(request.bodyFields, {'grant_type': 'refresh_token', 'refresh_token': 'r1', 'client_id': 'client_123'});
        return http.Response(jsonEncode({'id_token': fresh}), 200);
      });
      await const FlutterSecureStorage().write(
        key: QuillFinAuthService.storageKey,
        value: jsonEncode({'mode': 'clerk', 'idToken': idTokenFor('user_alice', expiresIn: const Duration(seconds: 30)), 'refreshToken': 'r1'}),
      );
      final auth = cloudAuth(server, httpClient: clerk);

      final tokens = await Future.wait([auth.idToken(), auth.idToken(), auth.idToken()]);
      expect(tokens, everyElement(fresh));
      expect(refreshes, 1);
      // Clerk didn't rotate it, so the old refresh token is kept.
      final stored = jsonDecode((await const FlutterSecureStorage().read(key: QuillFinAuthService.storageKey))!);
      expect(stored['refreshToken'], 'r1');
    });

    test('a refused refresh leaves the user signed in on this device, with no token', () async {
      final clerk = MockClient((_) async => http.Response('{"error":"invalid_grant"}', 400));
      await const FlutterSecureStorage().write(
        key: QuillFinAuthService.storageKey,
        value: jsonEncode({'mode': 'clerk', 'idToken': idTokenFor('user_alice', expiresIn: Duration.zero), 'refreshToken': 'r1'}),
      );
      final auth = cloudAuth(server, httpClient: clerk);
      expect(await auth.idToken(), isNull);
      expect((await auth.currentUser())?.id, 'user_alice');
    });

    test('an expired token without a refresh token gives no token', () async {
      await const FlutterSecureStorage().write(
        key: QuillFinAuthService.storageKey,
        value: jsonEncode({'mode': 'clerk', 'idToken': idTokenFor('user_alice', expiresIn: Duration.zero)}),
      );
      expect(await cloudAuth(server).idToken(), isNull);
    });

    test('convexClient signs calls with the current ID token', () async {
      final auth = await signedInToCloud(server);
      final client = auth.convexClient()!;
      expect(client.deploymentUrl.toString(), 'https://quillfin-test.convex.cloud');
      expect(await client.query('billing:me'), containsPair('plan', 'free'));
    });

    test('cancelSignIn stops a sign-in waiting on the browser', () async {
      final browser = FakeBrowserAuth()..hang();
      final auth = cloudAuth(server, browser: browser);
      final signingIn = auth.signIn();
      await Future<void>.delayed(Duration.zero);
      auth.cancelSignIn();
      await expectLater(signingIn, throwsA(isA<AuthCancelled>()));
      expect(await auth.currentUser(), isNull);
    });
  });

  group('ClerkTokens.user', () {
    test('falls back from name to given and family name, then email, then a default', () {
      AppUser user(Map<String, Object?> claims) => ClerkTokens(idToken: jwt({'sub': 'u', 'exp': 0, ...claims})).user;
      expect(user({'given_name': 'Ada', 'family_name': 'Lovelace'}).displayName, 'Ada Lovelace');
      expect(user({'email': 'ada@example.com'}).displayName, 'ada@example.com');
      expect(user({}).displayName, 'QuillFin account');
    });

    test('a token that is not a JWT is rejected', () {
      expect(() => decodeJwtPayload('not-a-jwt'), throwsFormatException);
    });
  });
}
