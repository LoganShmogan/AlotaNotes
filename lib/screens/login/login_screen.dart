import 'package:flutter/material.dart';

import '../../auth/auth_service.dart';
import '../../services/reminder_service.dart';
import '../../theme/theme.dart';
import '../../theme/widgets.dart';
import '../root_shell.dart';

class LoginScreen extends StatefulWidget {
  final AuthService authService;
  final ReminderService? reminders;
  const LoginScreen({super.key, required this.authService, this.reminders});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;
  bool _submitting = false;

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      await widget.authService.login(_usernameController.text.trim(), _passwordController.text);
      if (!mounted) return;
      // Dismiss the keyboard before navigating -- letting a route transition
      // start while the IME hide animation is still in flight leaves stale
      // WindowInsets state on some Android versions/emulators, which throws
      // off hit-testing (not just painting) on the next screen until the
      // next full relayout. Closing it first avoids the race entirely.
      FocusScope.of(context).unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RootShell(authService: widget.authService, reminders: widget.reminders)),
      );
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Quiz App AI', style: Theme.of(context).textTheme.displaySmall),
                  const SizedBox(height: 6),
                  Text(
                    'Notes, quizzes and a problem tracker that remind you right before you forget.',
                    style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: colorInkSoft),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(labelText: 'Username'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  PixelButton(
                    label: _submitting ? 'Signing in...' : 'Sign in',
                    onPressed: _submitting ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
