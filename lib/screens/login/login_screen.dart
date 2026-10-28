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
  String? _error;
  bool _waiting = false;

  Future<void> _enter(Future<AppUser> Function() how) async {
    setState(() {
      _error = null;
      _waiting = true;
    });
    try {
      await how();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RootShell(authService: widget.authService, reminders: widget.reminders)),
      );
    } on AuthCancelled {
      // Back to the choices, with nothing to report.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _waiting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.authService;
    final textTheme = Theme.of(context).textTheme;
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
          Text('Welcome to QuillFin', style: textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(brandTagline, style: textTheme.bodyLarge!.copyWith(color: context.brand.inkSoft)),
          const SizedBox(height: 28),
          if (_waiting && auth.cloudAvailable) ...[
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 16),
            Text('Finish signing in in your browser.', textAlign: TextAlign.center, style: textTheme.bodyLarge),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: auth.cancelSignIn, child: const Text('Cancel')),
          ] else ...[
            if (auth.cloudAvailable) ...[
              PrimaryButton(label: 'Sign in or create an account', onPressed: _waiting ? null : () => _enter(auth.signIn)),
              const SizedBox(height: 8),
              Text(
                'Sync your notes, questions and problems across your devices.',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall!.copyWith(color: context.brand.inkSoft),
              ),
              const SizedBox(height: 20),
            ],
            OutlinedButton(
              onPressed: _waiting ? null : () => _enter(auth.continueOnDevice),
              child: const Text('Continue on this device'),
            ),
            const SizedBox(height: 8),
            Text(
              auth.cloudAvailable
                  ? 'No account: everything stays on this device. You can sign in later from Account.'
                  : 'Everything stays on this device.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall!.copyWith(color: context.brand.inkSoft),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
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
