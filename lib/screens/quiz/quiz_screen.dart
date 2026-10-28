import 'package:flutter/material.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sqflite/sqflite.dart';

import '../../core/grading.dart';
import '../../core/models.dart';
import '../../core/scheduling.dart';
import '../../settings/app_settings.dart';
import '../../storage/db.dart';
import '../../storage/questions_repo.dart';
import '../../storage/reviews_repo.dart';
import '../../layout/breakpoints.dart';
import '../../theme/theme.dart';
import '../../theme/widgets.dart';
import '../review/rating_buttons.dart';

/// A review session over every question due right now. Mirrors the Python
/// desktop app's QuizSessionScreen/QuizController: grade the answer locally
/// (core/grading.dart for short-answer, direct equality for multiple
/// choice), then -- new with FSRS -- let the user confirm or adjust the
/// rating auto-grading suggests (wrong -> Again, right -> Good). Only the
/// rating tap saves: it advances the card (core/scheduling.dart), records
/// the immutable history row (ReviewsRepo) and moves on.
class QuizScreen extends StatefulWidget {
  final Database db;
  const QuizScreen({super.key, required this.db});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late final QuestionsRepo _questionsRepo = QuestionsRepo(widget.db);
  late final ReviewsRepo _reviewsRepo = ReviewsRepo(widget.db);
  fsrs.Scheduler _scheduler = buildScheduler();
  List<Question> _queue = [];
  Question? _current;
  bool _loading = true;
  int _reviewed = 0;
  bool _saving = false;
  final _answerController = TextEditingController();
  String? _selectedChoice;

  // Set once the current question has been answered.
  _Graded? _graded;

  // Holds keyboard focus once an answer is graded, so 1-4 reach the rating
  // shortcuts after the answer field is disabled.
  final _keyFocus = FocusNode(debugLabel: 'quiz keys');

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final settings = await const AppSettingsStore().load();
    final due = await _questionsRepo.listDue(utcNow());
    if (!mounted) return;
    setState(() {
      _scheduler = buildScheduler(desiredRetention: settings.desiredRetention);
      _queue = due;
      _loading = false;
    });
    _advance();
  }

  void _advance() {
    _answerController.clear();
    _selectedChoice = null;
    _graded = null;
    setState(() => _current = _queue.isEmpty ? null : _queue.removeAt(0));
  }

  (bool, String) _grade(Question question, String givenAnswer) {
    if (question.questionType == questionTypeMultipleChoice) {
      Choice? correct;
      for (final c in question.choices) {
        if (c.isCorrect) {
          correct = c;
          break;
        }
      }
      return (correct != null && givenAnswer == correct.choiceText, gradingMethodMcqExact);
    }
    final isCorrect = gradeShortAnswer(question.expectedAnswer, givenAnswer);
    final method = normalizeAnswerText(question.expectedAnswer) == normalizeAnswerText(givenAnswer)
        ? gradingMethodExactMatch
        : gradingMethodKeywordMatch;
    return (isCorrect, method);
  }

  void _submit() {
    final question = _current!;
    final givenAnswer = question.questionType == questionTypeMultipleChoice
        ? (_selectedChoice ?? '')
        : _answerController.text;
    final (isCorrect, gradingMethod) = _grade(question, givenAnswer);
    setState(() {
      _graded = (givenAnswer: givenAnswer, isCorrect: isCorrect, gradingMethod: gradingMethod, answeredAt: utcNow());
    });
    _keyFocus.requestFocus();
  }

  Future<void> _rate(ReviewRating rating) async {
    final question = _current!;
    final graded = _graded!;
    setState(() => _saving = true);
    final after = reviewCard(question.card, rating, graded.answeredAt, scheduler: _scheduler);
    await _questionsRepo.updateScheduling(question.id, after);
    await _reviewsRepo.record(
      question.id,
      graded.givenAnswer,
      graded.isCorrect,
      rating,
      graded.gradingMethod,
      after,
      askedAt: graded.answeredAt,
    );
    if (!mounted) return;
    _reviewed++;
    _saving = false;
    _advance();
  }

  @override
  void dispose() {
    _answerController.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final graded = _graded;
    final pinRatings = graded != null && context.windowSize == WindowSize.compact && !context.isShortHeight;
    final ratings = current == null || graded == null ? null : _ratingButtons(current, graded);
    return CallbackShortcuts(
      bindings: ratingShortcuts(graded == null || _saving ? null : _rate),
      child: Focus(
        focusNode: _keyFocus,
        child: Scaffold(
          appBar: AppBar(title: const Text('Quiz')),
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : current == null
                    ? ListView(
                        children: [
                          const SizedBox(height: 80),
                          EmptyState(
                            icon: Icons.celebration_outlined,
                            message: _reviewed == 0
                                ? 'Nothing due right now. Nice work!'
                                : 'Session done: $_reviewed reviewed. Nothing else is due right now.',
                          ),
                        ],
                      )
                    : _buildQuestion(current, inlineRatings: pinRatings ? null : ratings),
          ),
          // Compact: ratings pinned at the bottom, within thumb reach.
          bottomNavigationBar: pinRatings
              ? SafeArea(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    decoration: BoxDecoration(
                      color: context.brand.paper,
                      border: Border(top: BorderSide(color: context.brand.line)),
                    ),
                    child: ratings,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _ratingButtons(Question question, _Graded graded) => RatingButtons(
        previews: previewNextDue(question.card, graded.answeredAt, scheduler: _scheduler),
        now: graded.answeredAt,
        highlighted: suggestedRating(graded.isCorrect),
        // Disabled while saving, so a double tap can't review twice.
        onSelected: _saving ? null : _rate,
      );

  Widget _buildQuestion(Question question, {Widget? inlineRatings}) {
    final graded = _graded;
    final theme = Theme.of(context);
    final b = context.brand;
    final gutter = context.windowSize.gutter;
    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 24),
      children: [
        ContentWidth(
          maxWidth: maxReadingWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${_queue.length} more due after this one', style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              BrandCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(question.prompt, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 16),
                    if (question.questionType == questionTypeMultipleChoice)
                      // groupValue/onChanged are deprecated in favor of RadioGroup as of
                      // Flutter 3.32, but still functional; not worth migrating for one
                      // radio list yet.
                      ...question.choices.map((choice) => RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            title: Text(choice.choiceText),
                            // ignore: deprecated_member_use
                            groupValue: _selectedChoice,
                            value: choice.choiceText,
                            // ignore: deprecated_member_use
                            onChanged: graded != null ? null : (value) => setState(() => _selectedChoice = value),
                          ))
                    else
                      TextField(
                        controller: _answerController,
                        enabled: graded == null,
                        autofocus: true,
                        decoration: const InputDecoration(labelText: 'Your answer'),
                        onSubmitted: (_) => _submit(),
                      ),
                    if (graded == null) ...[
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: PrimaryButton(label: 'Submit', onPressed: _submit),
                      ),
                    ],
                  ],
                ),
              ),
              if (graded != null) ...[
                const SizedBox(height: 14),
                BrandCard(
                  color: (graded.isCorrect ? b.success : b.danger).withValues(alpha: 0.14),
                  child: Row(
                    children: [
                      Icon(graded.isCorrect ? Icons.check_circle : Icons.cancel, color: graded.isCorrect ? b.success : b.danger),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          graded.isCorrect ? 'Correct!' : 'Incorrect. Expected: ${question.expectedAnswer}',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SectionLabel('How well did you know it?'),
                ?inlineRatings,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

typedef _Graded = ({String givenAnswer, bool isCorrect, String gradingMethod, DateTime answeredAt});
