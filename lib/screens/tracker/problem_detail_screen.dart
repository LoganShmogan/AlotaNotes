import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models.dart';
import '../../core/scheduling.dart';
import '../../settings/app_settings.dart';
import '../../storage/db.dart';
import '../../storage/problems_repo.dart';
import '../../layout/breakpoints.dart';
import '../../theme/theme.dart';
import '../../theme/widgets.dart';
import 'log_attempt_sheet.dart';
import 'problem_editor_screen.dart';

/// One tracked problem: what it is, your solution, where its forgetting
/// curve stands, and every attempt so far. The "Timer" button runs a clock
/// that pre-fills the time taken when the attempt is logged.
class ProblemDetailScreen extends StatefulWidget {
  final Database db;
  final int problemId;

  /// Called after an attempt is logged or the problem is edited.
  final VoidCallback? onChanged;

  /// When set, the screen is embedded as the detail pane of the tracker's
  /// list-detail layout: deleting calls this instead of popping, and there's
  /// no back button.
  final VoidCallback? onDeleted;

  const ProblemDetailScreen({super.key, required this.db, required this.problemId, this.onChanged, this.onDeleted});

  @override
  State<ProblemDetailScreen> createState() => _ProblemDetailScreenState();
}

class _ProblemDetailScreenState extends State<ProblemDetailScreen> {
  late final ProblemsRepo _repo = ProblemsRepo(widget.db);
  fsrs.Scheduler _scheduler = buildScheduler();
  Problem? _problem;
  List<ProblemAttempt> _attempts = [];
  DateTime? _timerStartedAt;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final settings = await const AppSettingsStore().load();
    final problem = await _repo.get(widget.problemId);
    final attempts = await _repo.listAttempts(widget.problemId);
    if (!mounted) return;
    setState(() {
      _scheduler = buildScheduler(desiredRetention: settings.desiredRetention);
      _problem = problem;
      _attempts = attempts;
    });
  }

  void _toggleTimer() {
    _ticker?.cancel();
    setState(() {
      if (_timerStartedAt == null) {
        _timerStartedAt = DateTime.now();
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
      } else {
        _timerStartedAt = null;
        _ticker = null;
      }
    });
  }

  Future<void> _logAttempt() async {
    final problem = _problem!;
    final now = utcNow();
    final started = _timerStartedAt;
    final sheet = LogAttemptSheet(
      card: problem.card,
      scheduler: _scheduler,
      now: now,
      initialMinutes: started == null ? null : DateTime.now().difference(started).inMinutes,
    );
    // A bottom sheet on phones; a dialog where a sheet would stretch across
    // a wide window or cover a short (landscape) one.
    final input = context.windowSize == WindowSize.compact && !context.isShortHeight
        ? await showModalBottomSheet<AttemptInput>(context: context, isScrollControlled: true, builder: (_) => sheet)
        : await showDialog<AttemptInput>(
            context: context,
            builder: (_) => Dialog(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: sheet),
            ),
          );
    if (input == null) return;
    final after = reviewCard(problem.card ?? newCard(now), input.rating, now, scheduler: _scheduler);
    await _repo.recordAttempt(
      problem.id,
      solved: input.solved,
      rating: input.rating,
      after: after,
      durationMinutes: input.minutes,
      notes: input.notes,
      attemptedAt: now,
    );
    _ticker?.cancel();
    _ticker = null;
    _timerStartedAt = null;
    await _refresh();
    widget.onChanged?.call();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Logged. Next re-solve in ${formatInterval(after.due.difference(now))}.')),
    );
  }

  Future<void> _edit() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProblemEditorScreen(db: widget.db, problemId: widget.problemId)),
    );
    await _refresh();
    widget.onChanged?.call();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete problem?'),
        content: const Text('This also deletes its attempt history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.delete(widget.problemId);
    if (widget.onDeleted != null) {
      widget.onDeleted!();
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    final opened = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't open $url")));
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Problem'),
        automaticallyImplyLeading: widget.onDeleted == null,
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit', onPressed: problem == null ? null : _edit),
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: problem == null ? null : _delete),
        ],
      ),
      body: problem == null ? const Center(child: CircularProgressIndicator()) : _buildBody(problem),
    );
  }

  Widget _buildBody(Problem problem) {
    final theme = Theme.of(context);
    final b = context.brand;
    final now = utcNow();
    final card = problem.card;
    final started = _timerStartedAt;
    final elapsed = started == null ? null : DateTime.now().difference(started);
    final gutter = context.windowSize.gutter;
    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 32),
      children: [
        ContentWidth(
          maxWidth: 760,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BrandCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(problem.title, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        DifficultyPill(problem.difficulty),
                        StatusPill(problem.status),
                        if (problem.platform.isNotEmpty) Pill(problem.platform),
                        for (final tag in problem.tags) Pill('#$tag'),
                      ],
                    ),
                    if (problem.url != null) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        onPressed: () => _openLink(problem.url!),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: Text(problem.url!, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              BrandCard(
                color: b.deep,
                child: card == null
                    ? Text(
                        'Not attempted yet. Log your first attempt to start its review schedule.',
                        style: theme.textTheme.bodyLarge!.copyWith(color: b.onDeep),
                      )
                    : Row(
                        children: [
                          _memoryStat(
                            'Next re-solve',
                            isDue(card.due, now) ? 'Due now' : 'in ${formatInterval(card.due.difference(now))}',
                          ),
                          _memoryStat('Recall now', '${(retrievability(card, now, scheduler: _scheduler) * 100).round()}%'),
                          _memoryStat('Memory', card.stability == null ? '–' : formatInterval(_stabilityDuration(card))),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _toggleTimer,
                      icon: Icon(started == null ? Icons.timer_outlined : Icons.stop),
                      label: Text(started == null ? 'Timer' : _formatElapsed(elapsed!)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: PrimaryButton(label: 'Log attempt', icon: Icons.add_task, onPressed: _logAttempt)),
                ],
              ),
              if (problem.solution.isNotEmpty) ...[
                const SectionLabel('Solution'),
                BrandCard(
                  color: b.surfaceTint,
                  child: SelectableText(
                    problem.solution,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 13.5, color: b.ink, height: 1.45),
                  ),
                ),
              ],
              if (problem.notes.isNotEmpty) ...[
                const SectionLabel('Notes'),
                BrandCard(child: Text(problem.notes)),
              ],
              SectionLabel('Attempts (${_attempts.length})'),
              if (_attempts.isEmpty) Text('None yet.', style: theme.textTheme.bodySmall),
              for (final attempt in _attempts) _attemptTile(attempt),
            ],
          ),
        ),
      ],
    );
  }

  // Stability is how long until recall drops to 90%, in days.
  Duration _stabilityDuration(SrsCard card) => Duration(minutes: (card.stability! * 24 * 60).round());

  Widget _memoryStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(fontFamily: fontDisplay, fontSize: 20, fontWeight: FontWeight.w700, color: context.brand.quill)),
          Text(label, style: TextStyle(fontSize: 13, color: context.brand.onDeepSoft)),
        ],
      ),
    );
  }

  Widget _attemptTile(ProblemAttempt attempt) {
    final local = attempt.attemptedAt.toLocal();
    final date = '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final details = [
      date,
      if (attempt.durationMinutes != null) '${attempt.durationMinutes} min',
      attempt.rating.label,
    ].join(' · ');
    return Card(
      child: ListTile(
        leading: Icon(attempt.solved ? Icons.check_circle : Icons.cancel_outlined,
            color: attempt.solved ? context.brand.success : context.brand.danger),
        title: Text(attempt.solved ? 'Solved' : 'Not solved'),
        subtitle: Text(attempt.notes.isEmpty ? details : '$details\n${attempt.notes}'),
      ),
    );
  }
}

String _formatElapsed(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
