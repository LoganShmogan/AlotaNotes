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
  ({String givenAnswer, bool isCorrect, String gradingMethod, DateTime answeredAt})? _graded;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _current == null
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
                : _buildQuestion(_current!),
      ),
    );
  }

  Widget _buildQuestion(Question question) {
    final graded = _graded;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('${_queue.length} more due after this one', style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        PixelCard(
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
                  decoration: const InputDecoration(labelText: 'Your answer'),
                ),
              const SizedBox(height: 16),
              if (graded == null) PixelButton(label: 'Submit', onPressed: _submit),
            ],
          ),
        ),
        if (graded != null) ...[
          const SizedBox(height: 16),
          PixelCard(
            color: graded.isCorrect ? colorGreen : colorPaperTint,
            shadowColor: colorInk,
            child: Text(
              graded.isCorrect ? 'Correct!' : 'Incorrect. Expected: ${question.expectedAnswer}',
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SectionLabel('How well did you know it?'),
          RatingButtons(
            previews: previewNextDue(question.card, graded.answeredAt, scheduler: _scheduler),
            now: graded.answeredAt,
            highlighted: suggestedRating(graded.isCorrect),
            // Disabled while saving, so a double tap can't review twice.
            onSelected: _saving ? null : _rate,
          ),
        ],
      ],
    );
  }
}
