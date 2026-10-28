import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../auth/auth_service.dart';
import '../layout/breakpoints.dart';
import '../services/reminder_service.dart';
import '../storage/db.dart';
import '../sync/cloud_session.dart';
import '../sync/sync_service.dart';
import '../theme/theme.dart';
import '../theme/widgets.dart';
import 'account/account_screen.dart';
import 'notes/notes_home_screen.dart';
import 'settings/settings_screen.dart';
import 'today/today_screen.dart';
import 'tracker/problems_screen.dart';

/// One top-level destination.
class _Destination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  const _Destination(this.label, this.icon, this.selectedIcon);
}

const _destinations = [
  _Destination('Today', Icons.today_outlined, Icons.today),
  _Destination('Notes', Icons.sticky_note_2_outlined, Icons.sticky_note_2),
  _Destination('Tracker', Icons.code, Icons.code),
  _Destination('Account', Icons.person_outline, Icons.person),
  _Destination('Settings', Icons.settings_outlined, Icons.settings),
];

/// Keyboard shortcuts available everywhere in the shell, listed by the
/// Ctrl+/ help dialog.
const shellShortcuts = [
  ('Ctrl/⌘ + 1…5', 'Switch section'),
  ('Ctrl/⌘ + /', 'Show keyboard shortcuts'),
  ('Enter', 'Submit an answer (quiz)'),
  ('1 – 4', 'Rate Again / Hard / Good / Easy (quiz)'),
  ('Esc', 'Close a dialog or panel'),
];

/// The app shell with five sections: Today, Notes, Tracker, Account,
/// Settings. Navigation adapts to the window (Docs/quillfin_plan.md §5):
/// - compact: bottom navigation bar
/// - medium and expanded, or any short (landscape phone) window: a rail
/// - large and up: a labelled sidebar with the QuillFin lockup
///
/// Whenever a review, attempt or problem edit happens in one section
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
  CloudSession? _cloud;
  // Where the session is published: the app's CloudScope, or (when the
  // shell runs without one, as in some tests) a scope of its own.
  CloudSessionHolder? _holder;
  final _ownHolder = CloudSessionHolder();

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final db = await openAppDatabase();
    final user = await widget.authService.currentUser();
    if (!mounted) return;
    final client = user == null || user.isLocal ? null : widget.authService.convexClient();
    _holder = CloudScope.holderOf(context) ?? _ownHolder;
    setState(() {
      _db = db;
      if (client != null) {
        final sync = SyncService(db: db, client: client, userId: user!.id, onRemoteChanges: _studyChanged);
        _cloud = CloudSession(user: user, client: client, sync: sync);
        _holder!.value = _cloud;
        sync.start();
      }
    });
    _reminders.trySync(db);
  }

  @override
  void dispose() {
    if (_cloud != null) _holder?.clearLater(_cloud!);
    _cloud?.sync.dispose();
    _ownHolder.dispose();
    _studyVersion.dispose();
    _reminders.dispose();
    super.dispose();
  }

  void _studyChanged() {
    _studyVersion.value++;
    _reminders.trySync(_db!);
  }

  void _select(int index) {
    // Coming back to a section should show what other sections just changed.
    if (index != _selectedIndex) _studyVersion.value++;
    setState(() => _selectedIndex = index);
  }

  void _showShortcuts() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keyboard shortcuts'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (keys, action) in shellShortcuts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(width: 130, child: Text(keys, style: Theme.of(context).textTheme.titleSmall)),
                    Expanded(child: Text(action)),
                  ],
                ),
              ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
        for (var i = 0; i < _destinations.length; i++) ...{
          SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i), control: true): () => _select(i),
          SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i), meta: true): () => _select(i),
        },
        const SingleActivator(LogicalKeyboardKey.slash, control: true): _showShortcuts,
        const SingleActivator(LogicalKeyboardKey.slash, meta: true): _showShortcuts,
      };

  @override
  Widget build(BuildContext context) {
    if (_db == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final tabs = [
      TodayScreen(db: _db!, refresh: _studyVersion, onChanged: _studyChanged),
      NotesHomeScreen(db: _db!, refresh: _studyVersion),
      ProblemsScreen(db: _db!, refresh: _studyVersion, onChanged: _studyChanged),
      AccountScreen(authService: widget.authService, reminders: widget.reminders),
      SettingsScreen(db: _db!, reminders: _reminders),
    ];
    final body = IndexedStack(index: _selectedIndex, children: tabs);
    final size = context.windowSize;
    final useBottomBar = size == WindowSize.compact && !context.isShortHeight;

    final Widget shell;
    if (useBottomBar) {
      shell = Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _select,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
          ],
        ),
      );
    } else {
      final extended = size >= WindowSize.large;
      shell = Scaffold(
        body: SafeArea(
          right: false,
          child: Row(
            children: [
              NavigationRail(
                extended: extended,
                minExtendedWidth: 232,
                selectedIndex: _selectedIndex,
                onDestinationSelected: _select,
                labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                leading: Padding(
                  padding: EdgeInsets.fromLTRB(extended ? 16 : 0, 12, 0, 20),
                  child: extended ? const BrandLockup(size: 22, showOwner: true) : const QuillFinMark(size: 30),
                ),
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: IconButton(
                        tooltip: 'Keyboard shortcuts (Ctrl+/)',
                        icon: const Icon(Icons.keyboard_outlined),
                        onPressed: _showShortcuts,
                      ),
                    ),
                  ),
                ),
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
                ],
              ),
              VerticalDivider(width: 1, color: context.brand.line),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    final content = CallbackShortcuts(bindings: _shortcuts, child: Focus(autofocus: true, child: shell));
    return _holder == _ownHolder ? CloudScope(notifier: _ownHolder, child: content) : content;
  }
}
