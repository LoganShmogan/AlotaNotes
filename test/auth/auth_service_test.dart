import 'package:flutter_test/flutter_test.dart';
import 'package:quizapp/auth/auth_service.dart';

void main() {
  test('no one is signed in initially', () async {
    expect(await HardcodedAuthService().currentUser(), isNull);
  });

  test('admin/1234 signs in and becomes the current user', () async {
    final auth = HardcodedAuthService();
    final user = await auth.login('admin', '1234');
    expect(user.username, 'admin');
    expect((await auth.currentUser())?.username, 'admin');
  });

  for (final (username, password) in [('admin', 'wrong'), ('root', '1234'), ('', '')]) {
    test('rejects "$username"/"$password"', () async {
      final auth = HardcodedAuthService();
      await expectLater(
        auth.login(username, password),
        throwsA(isA<AuthException>().having((e) => e.toString(), 'message', 'Incorrect username or password.')),
      );
      expect(await auth.currentUser(), isNull);
    });
  }

  test('logout clears the current user', () async {
    final auth = HardcodedAuthService();
    await auth.login('admin', '1234');
    await auth.logout();
    expect(await auth.currentUser(), isNull);
  });
}
