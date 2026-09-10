import 'package:flutter/material.dart';

import 'auth/auth_service.dart';
import 'screens/login/login_screen.dart';
import 'screens/root_shell.dart';
import 'theme/theme.dart';

class QuizApp extends StatelessWidget {
  final AuthService authService;
  const QuizApp({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quiz App',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: _AuthGate(authService: authService),
    );
  }
}

/// Shows the login screen or the main app shell depending on whether a
/// (currently hardcoded, see auth/auth_service.dart) session already exists.
class _AuthGate extends StatelessWidget {
  final AuthService authService;
  const _AuthGate({required this.authService});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser?>(
      future: authService.currentUser(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data != null) {
          return RootShell(authService: authService);
        }
        return LoginScreen(authService: authService);
      },
    );
  }
}
