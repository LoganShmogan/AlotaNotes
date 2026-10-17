import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/models.dart';
import '../../services/data_export_service.dart';
import '../../settings/app_settings.dart';

/// App-wide settings: default question format and full data export. AI
/// provider/model/key and cloud connections live in the Account tab
/// instead (see Docs/flutter_rewrite_plan.md's information architecture).
///
/// Quiz reminders (local notifications) are deliberately not built yet --
/// verifying notification permission/scheduling behavior needs a real
/// device, not this session's headless emulator, and future_work-style
/// honesty matters more than a button that silently does nothing useful.
class SettingsScreen extends StatefulWidget {
  final Database db;
  const SettingsScreen({super.key, required this.db});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settingsStore = const AppSettingsStore();
  String _defaultFormat = questionTypeShortAnswer;
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _settingsStore.load();
    if (!mounted) return;
    setState(() {
      _defaultFormat = settings.defaultQuestionFormat;
      _loading = false;
    });
  }

  Future<void> _setDefaultFormat(String format) async {
    final settings = await _settingsStore.load();
    await _settingsStore.save(AppSettings(
      provider: settings.provider,
      model: settings.model,
      baseUrl: settings.baseUrl,
      defaultQuestionFormat: format,
    ));
    if (!mounted) return;
    setState(() => _defaultFormat = format);
  }

  Future<void> _exportData() async {
    setState(() => _exporting = true);
    try {
      final export = await DataExportService(widget.db).exportFile();
      await Share.shareXFiles([export.file], fileNameOverrides: [export.name], text: 'Quiz App AI data export');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('Default question format', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                RadioListTile<String>(
                  title: const Text('Short answer'),
                  value: questionTypeShortAnswer,
                  // ignore: deprecated_member_use
                  groupValue: _defaultFormat,
                  // ignore: deprecated_member_use
                  onChanged: (v) => _setDefaultFormat(v!),
                ),
                RadioListTile<String>(
                  title: const Text('Multiple choice'),
                  value: questionTypeMultipleChoice,
                  // ignore: deprecated_member_use
                  groupValue: _defaultFormat,
                  // ignore: deprecated_member_use
                  onChanged: (v) => _setDefaultFormat(v!),
                ),
                const Divider(height: 32),
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Quiz reminders'),
                  subtitle: const Text('Coming soon — needs a real device to verify'),
                ),
                const Divider(height: 32),
                ListTile(
                  leading: _exporting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_outlined),
                  title: const Text('Export all data'),
                  subtitle: const Text('Every folder, note, question, and review history as one JSON file'),
                  onTap: _exporting ? null : _exportData,
                ),
              ],
            ),
    );
  }
}
