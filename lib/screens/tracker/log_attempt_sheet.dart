import 'package:flutter/material.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../../core/models.dart';
import '../../core/scheduling.dart';
import '../../theme/widgets.dart';
import '../review/rating_buttons.dart';

/// What the user entered for one attempt.
typedef AttemptInput = ({bool solved, int? minutes, ReviewRating rating, String notes});

/// Bottom sheet for logging a go at a problem: solved or not, how long it
/// took, and a self-rated FSRS grade (suggested from solved/not, always
/// changeable). Pops with an [AttemptInput], or null if dismissed.
class LogAttemptSheet extends StatefulWidget {
  /// The problem's current card; null if never attempted.
  final SrsCard? card;
  final fsrs.Scheduler scheduler;
  final int? initialMinutes;
  final DateTime now;

  const LogAttemptSheet({
    super.key,
    required this.card,
    required this.scheduler,
    required this.now,
    this.initialMinutes,
  });

  @override
  State<LogAttemptSheet> createState() => _LogAttemptSheetState();
}

class _LogAttemptSheetState extends State<LogAttemptSheet> {
  bool _solved = true;
  ReviewRating? _rating; // null = follow the suggestion
  late final _minutes = TextEditingController(text: widget.initialMinutes?.toString() ?? '');
  final _notes = TextEditingController();

  ReviewRating get _effectiveRating => _rating ?? suggestedRating(_solved);

  @override
  void dispose() {
    _minutes.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    final minutes = int.tryParse(_minutes.text.trim());
    Navigator.of(context).pop<AttemptInput>((
      solved: _solved,
      minutes: minutes == null || minutes < 0 ? null : minutes,
      rating: _effectiveRating,
      notes: _notes.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final previews = previewNextDue(widget.card ?? newCard(widget.now), widget.now, scheduler: widget.scheduler);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Log attempt', style: Theme.of(context).textTheme.headlineSmall),
            const SectionLabel('Did you solve it?'),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(label: const Text('Solved'), selected: _solved, onSelected: (_) => setState(() => _solved = true)),
                ChoiceChip(
                  label: const Text('Not solved'),
                  selected: !_solved,
                  onSelected: (_) => setState(() => _solved = false),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Time taken (minutes, optional)'),
            ),
            const SectionLabel('How hard was it to recall?'),
            RatingButtons(
              previews: previews,
              now: widget.now,
              highlighted: _effectiveRating,
              onSelected: (r) => setState(() => _rating = r),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Notes (optional)', hintText: 'What tripped you up?'),
            ),
            const SizedBox(height: 20),
            PixelButton(label: 'Save attempt', onPressed: _save),
          ],
        ),
      ),
    );
  }
}
