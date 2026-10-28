import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../ai/provider_factory.dart';
import '../../auth/auth_service.dart';
import '../../layout/breakpoints.dart';
import '../../services/reminder_service.dart';
import '../../settings/app_settings.dart';
import '../../theme/widgets.dart';
import '../login/login_screen.dart';

const _apiKeyStorageKey = 'ai_api_key';

/// "Manage your connections" -- AI provider + model + API key today;
/// cloud-storage (Dropbox/Drive/OneNote) OAuth connections are a later
/// slice. No real login system yet (see auth/auth_service.dart) -- this is
/// not a SavePoint account, just where the local admin session and AI
/// connection live.
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

  Future<void> _logout() async {
    await widget.authService.logout();
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
                    title: Text(_user?.username ?? '...'),
                    subtitle: const Text('Local device account'),
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
                    decoration: const InputDecoration(labelText: 'API key'),
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
                  OutlinedButton(onPressed: _logout, child: const Text('Log out')),
                ],
              ),
            ),
    );
  }
}
