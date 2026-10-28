import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/models.dart';
import '../../core/scheduling.dart';
import '../../layout/breakpoints.dart';
import '../../storage/db.dart';
import '../../storage/problems_repo.dart';
import '../../theme/theme.dart';
import '../../theme/widgets.dart';
import 'problem_detail_screen.dart';
import 'problem_editor_screen.dart';

enum _Filter { all, due, todo, attempted, solved }

enum _SortColumn { title, difficulty, status, due, recall, attempts }

/// The Tracker section: every practice problem, searchable and filterable
/// by status/difficulty, each showing where its forgetting curve stands.
///
/// Layout by window size (Docs/quillfin_plan.md §5):
/// - compact/medium: a list of cards; tapping opens the problem as a page
/// - expanded and up: list on the left, the selected problem on the right
/// - large and up: a card/table toggle; the table sorts by any column
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
  int? _selectedId;
  bool _tableView = false;
  _SortColumn _sortColumn = _SortColumn.title;
  bool _sortAscending = true;

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
      if (_selectedId != null && !problems.any((p) => p.id == _selectedId)) _selectedId = null;
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
    if (context.showsTwoPanes) {
      setState(() => _selectedId = id);
      await _refresh();
      widget.onChanged?.call();
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProblemDetailScreen(db: widget.db, problemId: id)));
    await _refresh();
    widget.onChanged?.call();
  }

  void _detailChanged() {
    _refresh();
    widget.onChanged?.call();
  }

  void _detailDeleted() {
    setState(() => _selectedId = null);
    _detailChanged();
  }

  @override
  Widget build(BuildContext context) {
    final large = context.windowSize >= WindowSize.large;
    final table = large && _tableView;
    final list = _loading
        ? const Center(child: CircularProgressIndicator())
        : _problems.isEmpty
            ? EmptyState(
                icon: Icons.code,
                message: 'Track practice problems here, LeetCode-style.\n'
                    'Each one comes back for a re-solve right before you\'d forget it.',
                action: PrimaryButton(label: 'Add a problem', icon: Icons.add, onPressed: _add),
              )
            : RefreshIndicator(onRefresh: _refresh, child: _buildList(table));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tracker'),
        actions: [
          if (large && _problems.isNotEmpty)
            IconButton(
              tooltip: table ? 'Card view' : 'Table view',
              icon: Icon(table ? Icons.view_agenda_outlined : Icons.table_rows_outlined),
              onPressed: () => setState(() => _tableView = !_tableView),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: table
          // The table needs the width; the selected problem opens as a page.
          ? list
          : ListDetail(
              list: list,
              detail: _selectedId == null
                  ? null
                  : ProblemDetailScreen(
                      key: ValueKey(_selectedId),
                      db: widget.db,
                      problemId: _selectedId!,
                      onChanged: _detailChanged,
                      onDeleted: _detailDeleted,
                    ),
              emptyDetail: const EmptyState(icon: Icons.touch_app_outlined, message: 'Select a problem to see it here.'),
            ),
      floatingActionButton: _problems.isEmpty
          ? null
          : FloatingActionButton(onPressed: _add, tooltip: 'Add problem', child: const Icon(Icons.add)),
    );
  }

  Widget _buildList(bool table) {
    final now = utcNow();
    final shown = _problems.where((p) => _matches(p, now)).toList();
    final solved = _problems.where((p) => p.status == ProblemStatus.solved).length;
    final due = _problems.where((p) => p.card != null && isDue(p.card!.due, now)).length;
    final gutter = context.showsTwoPanes && !table ? 16.0 : context.windowSize.gutter;
    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 96),
      children: [
        ContentWidth(
          maxWidth: table ? maxContentWidthXL : maxContentWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search by name, platform or tag'),
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
              Text('${_problems.length} problems · $solved solved · $due due', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              if (shown.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No problems match.')))
              else if (table)
                _ProblemTable(
                  problems: _sorted(shown, now),
                  now: now,
                  sortColumn: _sortColumn,
                  ascending: _sortAscending,
                  onSort: (column) => setState(() {
                    _sortAscending = column == _sortColumn ? !_sortAscending : true;
                    _sortColumn = column;
                  }),
                  onOpen: (id) => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => ProblemDetailScreen(db: widget.db, problemId: id)))
                      .then((_) => _detailChanged()),
                )
              else
                for (final problem in shown)
                  _ProblemTile(
                    problem: problem,
                    now: now,
                    selected: context.showsTwoPanes && problem.id == _selectedId,
                    onTap: () => _open(problem.id),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  List<Problem> _sorted(List<Problem> problems, DateTime now) {
    // Untried problems have no due date or recall: they sort last.
    const never = 1 << 62;
    Comparable key(Problem p) => switch (_sortColumn) {
          _SortColumn.title => p.title.toLowerCase(),
          _SortColumn.difficulty => problemDifficulties.indexOf(p.difficulty),
          _SortColumn.status => p.status.index,
          _SortColumn.due => p.card?.due.millisecondsSinceEpoch ?? never,
          _SortColumn.recall => p.card == null ? -1.0 : retrievability(p.card!, now),
          _SortColumn.attempts => p.attemptCount,
        };
    final sorted = [...problems]..sort((a, b) => key(a).compareTo(key(b)));
    return _sortAscending ? sorted : sorted.reversed.toList();
  }
}

String _scheduleLabel(SrsCard? card, DateTime now) {
  if (card == null) return 'Not attempted';
  if (isDue(card.due, now)) return 'Due now';
  return 'Next in ${formatInterval(card.due.difference(now))}';
}

class _ProblemTile extends StatelessWidget {
  final Problem problem;
  final DateTime now;
  final bool selected;
  final VoidCallback onTap;
  const _ProblemTile({required this.problem, required this.now, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final card = problem.card;
    final theme = Theme.of(context);
    final b = context.brand;
    final attempts = problem.attemptCount == 1 ? '1 attempt' : '${problem.attemptCount} attempts';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: BrandCard(
        onTap: onTap,
        color: selected ? b.surfaceTint : null,
        accent: card != null && isDue(card.due, now) ? b.quill : null,
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
                Expanded(child: Text('$attempts · ${_scheduleLabel(card, now)}', style: theme.textTheme.bodySmall)),
                if (card != null) RetentionMeter(retrievability(card, now)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProblemTable extends StatelessWidget {
  final List<Problem> problems;
  final DateTime now;
  final _SortColumn sortColumn;
  final bool ascending;
  final ValueChanged<_SortColumn> onSort;
  final ValueChanged<int> onOpen;

  const _ProblemTable({
    required this.problems,
    required this.now,
    required this.sortColumn,
    required this.ascending,
    required this.onSort,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    const columns = [
      (_SortColumn.title, 'Problem', false),
      (_SortColumn.difficulty, 'Difficulty', false),
      (_SortColumn.status, 'Status', false),
      (_SortColumn.due, 'Next re-solve', false),
      (_SortColumn.recall, 'Recall', true),
      (_SortColumn.attempts, 'Attempts', true),
    ];
    return BrandCard(
      padding: EdgeInsets.zero,
      child: DataTable(
        showCheckboxColumn: false,
        sortColumnIndex: columns.indexWhere((c) => c.$1 == sortColumn),
        sortAscending: ascending,
        columns: [
          for (final (column, label, numeric) in columns)
            DataColumn(label: Text(label), numeric: numeric, onSort: (_, _) => onSort(column)),
        ],
        rows: [
          for (final p in problems)
            DataRow(
              onSelectChanged: (_) => onOpen(p.id),
              cells: [
                DataCell(Text(p.title)),
                DataCell(DifficultyPill(p.difficulty)),
                DataCell(StatusPill(p.status)),
                DataCell(Text(_scheduleLabel(p.card, now))),
                DataCell(Text(p.card == null ? '–' : '${(retrievability(p.card!, now) * 100).round()}%')),
                DataCell(Text('${p.attemptCount}')),
              ],
            ),
        ],
      ),
    );
  }
}
