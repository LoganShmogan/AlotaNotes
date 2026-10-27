import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../auth/auth_service.dart';
import '../services/reminder_service.dart';
import '../storage/db.dart';
import 'account/account_screen.dart';
import 'notes/notes_home_screen.dart';
import 'settings/settings_screen.dart';
import 'today/today_screen.dart';
import 'tracker/problems_screen.dart';

/// The five-tab shell: Today, Notes, Tracker, Account, Settings.
///
/// Whenever a review, attempt or problem edit happens on one tab
/// ([_studyChanged]), the others refresh and study reminders are re-planned.
class RootShell extends StatefulWidget {
  final AuthService authService;

  /// Defaults to one that never notifies, so tests and previews don't touch
  /// the real notification plugin; main.dart passes the real one.
  final ReminderService? reminders;

  const RootShell({super.key, required this.authService, this.reminders});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _selectedIndex = 0;
  Database? _db;
  late final ReminderService _reminders = widget.reminders ?? ReminderService(delivery: ReminderDelivery.none);
  final _studyVersion = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    openAppDatabase().then((db) {
      if (!mounted) return;
      setState(() => _db = db);
      _reminders.trySync(db);
    });
  }

  @override
  void dispose() {
    _studyVersion.dispose();
    _reminders.dispose();
    super.dispose();
  }

  void _studyChanged() {
    _studyVersion.value++;
    _reminders.trySync(_db!);
  }

  void _select(int index) {
    // Coming back to a tab should show what other tabs just changed.
    if (index != _selectedIndex) _studyVersion.value++;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    if (_db == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final tabs = [
      TodayScreen(db: _db!, refresh: _studyVersion, onChanged: _studyChanged),
      NotesHomeScreen(db: _db!),
      ProblemsScreen(db: _db!, refresh: _studyVersion, onChanged: _studyChanged),
      AccountScreen(authService: widget.authService, reminders: widget.reminders),
      SettingsScreen(db: _db!, reminders: _reminders),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.notes), label: 'Notes'),
          NavigationDestination(icon: Icon(Icons.code), label: 'Tracker'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
