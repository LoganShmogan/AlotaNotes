import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../ai/provider_factory.dart';
import '../../auth/auth_service.dart';
import '../../layout/breakpoints.dart';
import '../../services/reminder_service.dart';
import '../../settings/app_settings.dart';
import '../../sync/cloud_session.dart';
import '../../theme/widgets.dart';
import '../login/login_screen.dart';

const _apiKeyStorageKey = 'ai_api_key';

/// The QuillFin account (or device-only session) and the AI connection:
/// provider, model and your own API key. Signed in without a key, question
/// generation uses QuillFin's AI within your plan (Settings > Plan).
/// Cloud-storage (Dropbox/Drive/OneNote) connections are a later slice.
class AccountScreen extends StatefulWidget {
  final AuthService authService;
  final ReminderService? reminders;
  const AccountScreen({super.key, required this.authService, this.reminders});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _secureStorage = const FlutterSecureStorage();
  final _settingsStore = const AppSettingsStore();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  final _baseUrlController = TextEditingController();
  String _provider = defaultProvider;
  AppUser? _user;
  bool _loading = true;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = await widget.authService.currentUser();
    final key = await _secureStorage.read(key: _apiKeyStorageKey);
    final settings = await _settingsStore.load();
    if (!mounted) return;
    setState(() {
      _user = user;
      _apiKeyController.text = key ?? '';
      _provider = settings.provider;
      _modelController.text = settings.model;
      _baseUrlController.text = settings.baseUrl ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    await _secureStorage.write(key: _apiKeyStorageKey, value: _apiKeyController.text.trim());
    // Start from what's stored, so saving here never resets Settings-tab
    // choices (question format, retention, reminders).
    final baseUrl = _baseUrlController.text.trim();
    final settings = await _settingsStore.load();
    await _settingsStore.save(
      settings.copyWith(
        provider: _provider,
        model: _modelController.text.trim(),
        baseUrl: baseUrl.isEmpty ? null : baseUrl,
        clearBaseUrl: baseUrl.isEmpty,
      ),
    );
    if (!mounted) return;
    setState(() => _saved = true);
  }

  /// Signing out of an account first pushes what it can, then asks whether
  /// to keep this device's copy. A device-only session just goes back to
  /// the sign-in choices.
  Future<void> _signOut() async {
    final session = CloudScope.maybeOf(context);
    if (session != null) {
      final choice = await showDialog<_SignOutChoice>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sign out?'),
          content: const Text(
            'Your notes and problems stay in your account. You can keep a copy on this device, '
            "which won't sync until you sign in again, or delete it from this device.",
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(context, _SignOutChoice.delete),
              child: const Text('Delete from this device'),
            ),
            FilledButton(onPressed: () => Navigator.pop(context, _SignOutChoice.keep), child: const Text('Keep a copy')),
          ],
        ),
      );
      if (choice == null) return;
      // Best effort: whatever doesn't reach the server in time stays local.
      await session.sync.syncNow().timeout(const Duration(seconds: 15), onTimeout: () {});
      if (choice == _SignOutChoice.delete) await session.sync.store.deleteLocalData();
    }
    await _leave();
  }

  Future<void> _signInToSync() => _leave();

  Future<void> _leave() async {
    await widget.authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(authService: widget.authService, reminders: widget.reminders),
      ),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) => ListView(
                padding: EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: centeredInset(constraints.maxWidth, context.windowSize.gutter),
                ),
                children: [
                  ListTile(
                    leading: const Icon(Icons.account_circle),
                    title: Text(_user?.displayName ?? '...'),
                    subtitle: Text(
                      _user == null || _user!.isLocal
                          ? 'Not signed in: everything stays on this device'
                          : _user!.email ?? 'QuillFin account',
                    ),
                  ),
                  if (_user != null && _user!.isLocal && widget.authService.cloudAvailable)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: PrimaryButton(label: 'Sign in to sync', onPressed: _signInToSync),
                    ),
                  const Divider(height: 32),
                  const SectionLabel('AI provider'),
                  DropdownButtonFormField<String>(
                    initialValue: _provider,
                    items: [for (final p in knownProviders) DropdownMenuItem(value: p, child: Text(p))],
                    onChanged: (value) {
                      if (value != null) setState(() => _provider = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _modelController,
                    decoration: const InputDecoration(labelText: 'Model (e.g. gpt-4o-mini)'),
                    onChanged: (_) => setState(() => _saved = false),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _baseUrlController,
                    decoration: const InputDecoration(labelText: 'Base URL override (optional)'),
                    onChanged: (_) => setState(() => _saved = false),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'API key',
                      helperText: CloudScope.maybeOf(context) == null
                          ? null
                          : "Optional: without one, QuillFin's AI is used, within your plan.",
                    ),
                    onChanged: (_) => setState(() => _saved = false),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _save, child: Text(_saved ? 'Saved' : 'Save')),
                  const Divider(height: 32),
                  Text(
                    'Cloud storage connections (Dropbox, Google Drive, OneNote) — coming later.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 32),
                  OutlinedButton(onPressed: _signOut, child: const Text('Sign out')),
                ],
              ),
            ),
    );
  }
}

enum _SignOutChoice { keep, delete }
