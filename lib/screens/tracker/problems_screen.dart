import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/models.dart';
import '../../core/scheduling.dart';
import '../../storage/db.dart';
import '../../storage/problems_repo.dart';
import '../../theme/theme.dart';
import '../../theme/widgets.dart';
import 'problem_detail_screen.dart';
import 'problem_editor_screen.dart';

enum _Filter { all, due, todo, attempted, solved }

/// The Tracker tab: every practice problem, searchable and filterable by
/// status/difficulty, each showing where its forgetting curve stands.
class ProblemsScreen extends StatefulWidget {
  final Database db;

  /// Fires when something elsewhere (a review) may have changed problems.
  final Listenable? refresh;

  /// Called after this screen changed problems (add/log/edit/delete).
  final VoidCallback? onChanged;

  const ProblemsScreen({super.key, required this.db, this.refresh, this.onChanged});

  @override
  State<ProblemsScreen> createState() => _ProblemsScreenState();
}

class _ProblemsScreenState extends State<ProblemsScreen> {
  late final ProblemsRepo _repo = ProblemsRepo(widget.db);
  List<Problem> _problems = [];
  bool _loading = true;
  _Filter _filter = _Filter.all;
  String? _difficulty;
  String _query = '';

  @override
  void initState() {
    super.initState();
    widget.refresh?.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final problems = await _repo.list();
    if (!mounted) return;
    setState(() {
      _problems = problems;
      _loading = false;
    });
  }

  bool _matches(Problem p, DateTime now) {
    final passesFilter = switch (_filter) {
      _Filter.all => true,
      _Filter.due => p.card != null && isDue(p.card!.due, now),
      _Filter.todo => p.status == ProblemStatus.todo,
      _Filter.attempted => p.status == ProblemStatus.attempted,
      _Filter.solved => p.status == ProblemStatus.solved,
    };
    if (!passesFilter) return false;
    if (_difficulty != null && p.difficulty != _difficulty) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return p.title.toLowerCase().contains(q) || p.platform.toLowerCase().contains(q) || p.tags.any((t) => t.contains(q));
  }

  Future<void> _add() async {
    final id = await Navigator.of(context).push<int>(MaterialPageRoute(builder: (_) => ProblemEditorScreen(db: widget.db)));
    if (id == null) return;
    await _open(id);
  }

  Future<void> _open(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProblemDetailScreen(db: widget.db, problemId: id)));
    await _refresh();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final now = utcNow();
    final shown = _problems.where((p) => _matches(p, now)).toList();
    final solved = _problems.where((p) => p.status == ProblemStatus.solved).length;
    final due = _problems.where((p) => p.card != null && isDue(p.card!.due, now)).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Tracker')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _problems.isEmpty
              ? EmptyState(
                  icon: Icons.code,
                  message: 'Track practice problems here, LeetCode-style.\n'
                      'Each one comes back for a re-solve right before you\'d forget it.',
                  action: PixelButton(label: 'Add a problem', icon: Icons.add, onPressed: _add),
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search by name, platform or tag',
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final (filter, label) in [
                              (_Filter.all, 'All'),
                              (_Filter.due, 'Due ($due)'),
                              (_Filter.todo, 'To do'),
                              (_Filter.attempted, 'Attempted'),
                              (_Filter.solved, 'Solved'),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(label),
                                  selected: _filter == filter,
                                  onSelected: (_) => setState(() => _filter = filter),
                                ),
                              ),
                            const SizedBox(width: 8),
                            for (final (value, label) in [
                              (problemDifficultyEasy, 'Easy'),
                              (problemDifficultyMedium, 'Medium'),
                              (problemDifficultyHard, 'Hard'),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: Text(label),
                                  selected: _difficulty == value,
                                  onSelected: (on) => setState(() => _difficulty = on ? value : null),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_problems.length} problems · $solved solved · $due due',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      if (shown.isEmpty)
                        const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No problems match.'))),
                      for (final problem in shown) _ProblemTile(problem: problem, now: now, onTap: () => _open(problem.id)),
                    ],
                  ),
                ),
      floatingActionButton: _problems.isEmpty
          ? null
          : FloatingActionButton(onPressed: _add, tooltip: 'Add problem', child: const Icon(Icons.add)),
    );
  }
}

class _ProblemTile extends StatelessWidget {
  final Problem problem;
  final DateTime now;
  final VoidCallback onTap;
  const _ProblemTile({required this.problem, required this.now, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final card = problem.card;
    final theme = Theme.of(context);
    final String schedule;
    if (card == null) {
      schedule = 'Not attempted';
    } else if (isDue(card.due, now)) {
      schedule = 'Due now';
    } else {
      schedule = 'Next in ${formatInterval(card.due.difference(now))}';
    }
    final attempts = problem.attemptCount == 1 ? '1 attempt' : '${problem.attemptCount} attempts';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PixelCard(
        onTap: onTap,
        shadowColor: card != null && isDue(card.due, now) ? colorYellow : colorPurple,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(problem.title, style: theme.textTheme.titleMedium)),
                const SizedBox(width: 8),
                DifficultyPill(problem.difficulty),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusPill(problem.status),
                for (final tag in problem.tags) Text('#$tag', style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('$attempts · $schedule', style: theme.textTheme.bodySmall)),
                if (card != null) RetentionMeter(retrievability(card, now)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
