import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../auth/auth_service.dart';
import '../storage/db.dart';
import 'account/account_screen.dart';
import 'notes/notes_home_screen.dart';
import 'quiz/quiz_screen.dart';
import 'settings/settings_screen.dart';

/// The four-tab shell: Notes, Quiz, Account, Settings.
class RootShell extends StatefulWidget {
  final AuthService authService;
  const RootShell({super.key, required this.authService});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _selectedIndex = 0;
  Database? _db;

  @override
  void initState() {
    super.initState();
    openAppDatabase().then((db) {
      if (mounted) setState(() => _db = db);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_db == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final tabs = [
      NotesHomeScreen(db: _db!),
      QuizScreen(db: _db!),
      AccountScreen(authService: widget.authService),
      SettingsScreen(db: _db!),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.notes), label: 'Notes'),
          BottomNavigationBarItem(icon: Icon(Icons.quiz), label: 'Quiz'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Account'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
