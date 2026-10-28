import 'package:flutter/material.dart';

import 'auth/auth_service.dart';
import 'screens/login/login_screen.dart';
import 'screens/root_shell.dart';
import 'services/reminder_service.dart';
import 'settings/theme_controller.dart';
import 'sync/cloud_session.dart';
import 'theme/theme.dart';

class QuillFinApp extends StatefulWidget {
  final AuthService authService;
  final ReminderService? reminders;
  final ThemeController? themeController;
  const QuillFinApp({super.key, required this.authService, this.reminders, this.themeController});

  @override
  State<QuillFinApp> createState() => _QuillFinAppState();
}

class _QuillFinAppState extends State<QuillFinApp> {
  late final ThemeController _theme = widget.themeController ?? ThemeController();
  final _light = buildAppTheme();
  final _dark = buildAppTheme(brightness: Brightness.dark);
  final _cloud = CloudSessionHolder();

  @override
  void dispose() {
    _cloud.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _theme.load();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeControllerScope(
      controller: _theme,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: _theme,
        builder: (context, mode, _) => MaterialApp(
          title: brandName,
          debugShowCheckedModeBanner: false,
          theme: _light,
          darkTheme: _dark,
          themeMode: mode,
          builder: (context, child) => CloudScope(notifier: _cloud, child: child!),
          home: _AuthGate(authService: widget.authService, reminders: widget.reminders),
        ),
      ),
    );
  }
}

/// Shows the login screen or the main app shell depending on whether a
/// (currently hardcoded, see auth/auth_service.dart) session already exists.
class _AuthGate extends StatelessWidget {
  final AuthService authService;
  final ReminderService? reminders;
  const _AuthGate({required this.authService, this.reminders});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser?>(
      future: authService.currentUser(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data != null) {
          return RootShell(authService: authService, reminders: reminders);
        }
        return LoginScreen(authService: authService, reminders: reminders);
      },
    );
  }
}
