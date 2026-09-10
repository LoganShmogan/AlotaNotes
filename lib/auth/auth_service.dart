/// Authentication abstraction. `HardcodedAuthService` is a deliberate,
/// temporary stand-in (single hardcoded admin/1234 "account") for local-only
/// use on one device. When a real auth/accounts system (e.g. Clerk) is
/// wired in later, it becomes a new `AuthService` implementation -- no
/// screen or other code should need to change, same reasoning as the
/// Python desktop app's swappable `ApiKeyStore` (see its
/// `Docs/future_work.md`).
library;

class AppUser {
  final String username;
  const AppUser(this.username);
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

abstract class AuthService {
  Future<AppUser?> currentUser();
  Future<AppUser> login(String username, String password);
  Future<void> logout();
}

class HardcodedAuthService implements AuthService {
  static const _validUsername = 'admin';
  static const _validPassword = '1234';

  AppUser? _current;

  @override
  Future<AppUser?> currentUser() async => _current;

  @override
  Future<AppUser> login(String username, String password) async {
    if (username != _validUsername || password != _validPassword) {
      throw const AuthException('Incorrect username or password.');
    }
    _current = const AppUser(_validUsername);
    return _current!;
  }

  @override
  Future<void> logout() async {
    _current = null;
  }
}
