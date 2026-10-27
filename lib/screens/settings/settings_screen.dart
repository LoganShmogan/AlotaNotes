import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/models.dart';
import '../../core/scheduling.dart';
import '../../services/data_export_service.dart';
import '../../services/reminder_service.dart';
import '../../settings/app_settings.dart';
import '../../theme/widgets.dart';

/// App-wide settings: FSRS target retention, study reminders, default
/// question format and full data export. AI provider/model/key and cloud
/// connections live in the Account tab instead (see
/// Docs/flutter_rewrite_plan.md's information architecture).
class SettingsScreen extends StatefulWidget {
  final Database db;
  final ReminderService reminders;
  const SettingsScreen({super.key, required this.db, required this.reminders});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settingsStore = const AppSettingsStore();
  AppSettings _settings = const AppSettings();
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
      _settings = settings;
      _loading = false;
    });
  }

  Future<void> _update(AppSettings Function(AppSettings current) change, {bool resync = false}) async {
    // Reload first: the Account tab may have saved since this screen loaded.
    final updated = change(await _settingsStore.load());
    await _settingsStore.save(updated);
    if (resync) await widget.reminders.trySync(widget.db);
    if (!mounted) return;
    setState(() => _settings = updated);
  }

  Future<void> _setRemindersEnabled(bool enabled) async {
    if (enabled && !await widget.reminders.requestPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notifications are blocked. Allow them in system settings to get reminders.')),
      );
      return;
    }
    await _update((s) => s.copyWith(remindersEnabled: enabled), resync: true);
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _settings.reminderHour, minute: _settings.reminderMinute),
    );
    if (picked == null) return;
    await _update((s) => s.copyWith(reminderHour: picked.hour, reminderMinute: picked.minute), resync: true);
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

  String get _deliveryNote => switch (widget.reminders.delivery) {
        ReminderDelivery.scheduled => 'A notification on days something is due, even with the app closed.',
        ReminderDelivery.whileOpen => "Shown while the app is open: this platform can't schedule notifications ahead.",
        ReminderDelivery.none => 'Not available here. The Today tab shows what is due.',
      };

  @override
  Widget build(BuildContext context) {
    final retentionPercent = (_settings.desiredRetention * 100).round();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: SectionLabel('Memory')),
                ListTile(
                  title: Text('Target recall: $retentionPercent%'),
                  subtitle: const Text(
                    'How likely you should be to still remember something when it comes back. '
                    'Higher means more frequent reviews.',
                  ),
                ),
                Slider(
                  value: _settings.desiredRetention,
                  min: minDesiredRetention,
                  max: maxDesiredRetention,
                  divisions: ((maxDesiredRetention - minDesiredRetention) * 100).round(),
                  label: '$retentionPercent%',
                  onChanged: (v) => setState(() => _settings = _settings.copyWith(desiredRetention: v)),
                  onChangeEnd: (v) => _update((s) => s.copyWith(desiredRetention: v)),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: SectionLabel('Reminders')),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_outlined),
                  title: const Text('Daily study reminder'),
                  subtitle: Text(_deliveryNote),
                  value: _settings.remindersEnabled && widget.reminders.supported,
                  onChanged: widget.reminders.supported ? _setRemindersEnabled : null,
                ),
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('Reminder time'),
                  trailing: Text(
                    TimeOfDay(hour: _settings.reminderHour, minute: _settings.reminderMinute).format(context),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  enabled: _settings.remindersEnabled && widget.reminders.supported,
                  onTap: _pickReminderTime,
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: SectionLabel('Default question format')),
                RadioListTile<String>(
                  title: const Text('Short answer'),
                  value: questionTypeShortAnswer,
                  // ignore: deprecated_member_use
                  groupValue: _settings.defaultQuestionFormat,
                  // ignore: deprecated_member_use
                  onChanged: (v) => _update((s) => s.copyWith(defaultQuestionFormat: v)),
                ),
                RadioListTile<String>(
                  title: const Text('Multiple choice'),
                  value: questionTypeMultipleChoice,
                  // ignore: deprecated_member_use
                  groupValue: _settings.defaultQuestionFormat,
                  // ignore: deprecated_member_use
                  onChanged: (v) => _update((s) => s.copyWith(defaultQuestionFormat: v)),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: SectionLabel('Your data')),
                ListTile(
                  leading: _exporting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_outlined),
                  title: const Text('Export all data'),
                  subtitle: const Text('Every folder, note, question, problem and review history as one JSON file'),
                  onTap: _exporting ? null : _exportData,
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
