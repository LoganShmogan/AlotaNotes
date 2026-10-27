import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/models.dart';
import '../../core/scheduling.dart';
import '../../storage/db.dart';
import '../../storage/problems_repo.dart';
import '../../storage/questions_repo.dart';
import '../../storage/reviews_repo.dart';
import '../../theme/theme.dart';
import '../../theme/widgets.dart';
import '../quiz/quiz_screen.dart';
import '../tracker/problem_detail_screen.dart';

/// The home tab: what's due now (quiz questions and problems to re-solve),
/// how much was done today, average recall across everything reviewed so
/// far, and how many items come due each of the next seven days.
class TodayScreen extends StatefulWidget {
  final Database db;
  final Listenable? refresh;
  final VoidCallback? onChanged;
  const TodayScreen({super.key, required this.db, this.refresh, this.onChanged});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayData {
  final int questionsDue;
  final List<Problem> problemsDue;
  final int reviewedToday;
  final double? averageRecall;
  final List<int> forecast; // items coming due on each of the next 7 days
  const _TodayData(this.questionsDue, this.problemsDue, this.reviewedToday, this.averageRecall, this.forecast);
}

class _TodayScreenState extends State<TodayScreen> {
  late final QuestionsRepo _questions = QuestionsRepo(widget.db);
  late final ProblemsRepo _problems = ProblemsRepo(widget.db);
  late final ReviewsRepo _reviews = ReviewsRepo(widget.db);
  _TodayData? _data;

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
    final now = utcNow();
    final local = now.toLocal();
    final startOfDay = DateTime(local.year, local.month, local.day);
    final questions = await _questions.listActive();
    final problems = await _problems.list();
    final reviewedToday = await _reviews.countSince(startOfDay) + await _problems.countAttemptsSince(startOfDay);

    final cards = [for (final q in questions) q.card, for (final p in problems) ?p.card];
    final reviewed = cards.where((c) => c.lastReview != null).toList();
    final averageRecall = reviewed.isEmpty
        ? null
        : reviewed.map((c) => retrievability(c, now)).reduce((a, b) => a + b) / reviewed.length;
    final forecast = List.filled(7, 0);
    for (final card in cards) {
      final due = card.due.toLocal();
      final dayIndex = DateTime(due.year, due.month, due.day).difference(startOfDay).inDays;
      // Tomorrow onwards; today's are already in the due counts.
      if (dayIndex >= 1 && dayIndex <= 7) forecast[dayIndex - 1]++;
    }

    if (!mounted) return;
    setState(() {
      _data = _TodayData(
        questions.where((q) => isDue(q.card.due, now)).length,
        problems.where((p) => p.card != null && isDue(p.card!.due, now)).toList(),
        reviewedToday,
        averageRecall,
        forecast,
      );
    });
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    await _refresh();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('Today')),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _refresh, child: _buildBody(data)),
    );
  }

  Widget _buildBody(_TodayData data) {
    final theme = Theme.of(context);
    final totalDue = data.questionsDue + data.problemsDue.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        PixelCard(
          color: colorPlum,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                totalDue == 0 ? 'All caught up' : '$totalDue ready to review',
                style: theme.textTheme.headlineSmall!.copyWith(color: colorOnPlum),
              ),
              const SizedBox(height: 6),
              Text(
                totalDue == 0
                    ? 'Nothing is due right now. Add notes or log a problem to grow your review queue.'
                    : 'Reviewing right before you forget is what makes it stick.',
                style: theme.textTheme.bodyMedium!.copyWith(color: colorOnPlumSoft),
              ),
              if (data.questionsDue > 0) ...[
                const SizedBox(height: 16),
                PixelButton(
                  label: 'Start quiz (${data.questionsDue})',
                  icon: Icons.play_arrow,
                  onPressed: () => _push(QuizScreen(db: widget.db)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: StatTile(label: 'Questions due', value: '${data.questionsDue}', accent: colorYellow)),
            const SizedBox(width: 6),
            Expanded(child: StatTile(label: 'Problems due', value: '${data.problemsDue.length}', accent: colorBlue)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: StatTile(label: 'Reviewed today', value: '${data.reviewedToday}', accent: colorGreen)),
            const SizedBox(width: 6),
            Expanded(
              child: StatTile(
                label: 'Average recall',
                value: data.averageRecall == null ? '–' : '${(data.averageRecall! * 100).round()}%',
              ),
            ),
          ],
        ),
        if (data.problemsDue.isNotEmpty) ...[
          const SectionLabel('Problems to re-solve'),
          for (final problem in data.problemsDue)
            Card(
              child: ListTile(
                leading: const Icon(Icons.code),
                title: Text(problem.title),
                subtitle: Text(problem.tags.isEmpty ? problem.platform : problem.tags.map((t) => '#$t').join(' ')),
                trailing: DifficultyPill(problem.difficulty),
                onTap: () => _push(ProblemDetailScreen(db: widget.db, problemId: problem.id)),
              ),
            ),
        ],
        const SectionLabel('Coming up'),
        _Forecast(counts: data.forecast),
      ],
    );
  }
}

/// Seven bars, one per upcoming day, scaled to the busiest day.
class _Forecast extends StatelessWidget {
  final List<int> counts;
  const _Forecast({required this.counts});

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final maxCount = counts.fold(0, (a, b) => a > b ? a : b);
    final today = DateTime.now();
    return PixelCard(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      child: SizedBox(
        height: 110,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < counts.length; i++)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${counts[i]}', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Container(
                      height: maxCount == 0 ? 0 : 56 * counts[i] / maxCount,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: i == 0 ? colorYellow : colorPurple,
                        border: counts[i] == 0 ? null : Border.all(color: colorInk, width: 2),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      i == 0 ? 'Tmrw' : _weekdays[DateTime(today.year, today.month, today.day + i + 1).weekday - 1],
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
