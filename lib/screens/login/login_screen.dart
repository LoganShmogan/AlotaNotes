import 'package:flutter/material.dart';

import '../../auth/auth_service.dart';
import '../../services/reminder_service.dart';
import '../../layout/breakpoints.dart';
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
    final form = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!context.showsTwoPanes) ...[
            const Align(alignment: Alignment.centerLeft, child: BrandLockup(size: 30, showOwner: true)),
            const SizedBox(height: 28),
          ],
          Text('Welcome back', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(brandTagline, style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: context.brand.inkSoft)),
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
          PrimaryButton(label: _submitting ? 'Signing in...' : 'Sign in', onPressed: _submitting ? null : _submit),
        ],
      ),
    );
    final formPane = SafeArea(
      child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: form)),
    );
    if (!context.showsTwoPanes) return Scaffold(body: formPane);

    // Expanded and wider: brand panel on the left, form on the right.
    final b = context.brand;
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: Container(
              color: b.deep,
              padding: const EdgeInsets.all(48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BrandLockup(size: 30, showOwner: true, color: b.onDeep),
                  const Spacer(),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Text(
                      'Remember what you learn, right before you would forget it.',
                      style: Theme.of(context).textTheme.displaySmall!.copyWith(color: b.onDeep),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Notes, AI quizzes and a practice tracker, scheduled with FSRS.',
                    style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: b.onDeepSoft),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: formPane),
        ],
      ),
    );
  }
}
