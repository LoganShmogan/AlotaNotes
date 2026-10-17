import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/grading.dart';
import '../../core/models.dart';
import '../../core/scheduling.dart';
import '../../storage/db.dart';
import '../../storage/questions_repo.dart';
import '../../storage/reviews_repo.dart';

/// "Today's Quizzes" -- everything due right now. Mirrors the Python
/// desktop app's QuizSessionScreen/QuizController: grade the answer locally
/// (core/grading.dart for short-answer, direct equality for multiple
/// choice), advance the schedule (core/scheduling.dart), persist, move on,
/// and record the immutable history row (ReviewsRepo) stats will read from.
class QuizScreen extends StatefulWidget {
  final Database db;
  const QuizScreen({super.key, required this.db});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late final QuestionsRepo _questionsRepo = QuestionsRepo(widget.db);
  late final ReviewsRepo _reviewsRepo = ReviewsRepo(widget.db);
  List<Question> _queue = [];
  Question? _current;
  bool _loading = true;
  bool _submitted = false;
  bool? _wasCorrect;
  final _answerController = TextEditingController();
  String? _selectedChoice;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final due = await _questionsRepo.listDue(utcNow());
    if (!mounted) return;
    setState(() {
      _queue = due;
      _loading = false;
    });
    _advance();
  }

  void _advance() {
    _answerController.clear();
    _selectedChoice = null;
    _submitted = false;
    _wasCorrect = null;
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

  Future<void> _submit() async {
    final question = _current;
    if (question == null) return;
    final givenAnswer = question.questionType == questionTypeMultipleChoice
        ? (_selectedChoice ?? '')
        : _answerController.text;
    final (isCorrect, gradingMethod) = _grade(question, givenAnswer);
    final answeredAt = utcNow();
    final outcome = applyReview(question.intervalIndex, isCorrect, answeredAt);

    await _questionsRepo.updateScheduling(
      question.id,
      intervalIndex: outcome.newIndex,
      lastAskedAt: answeredAt,
      nextDueAt: outcome.nextDueAt,
    );
    await _reviewsRepo.record(
      question.id,
      givenAnswer,
      isCorrect,
      question.intervalIndex,
      outcome.newIndex,
      gradingMethod,
      askedAt: answeredAt,
    );

    if (!mounted) return;
    setState(() {
      _submitted = true;
      _wasCorrect = isCorrect;
    });
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Today's Quizzes")),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _current == null
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(child: Text('Nothing due right now. Nice work!')),
                    ],
                  )
                : _buildQuestion(_current!),
      ),
    );
  }

  Widget _buildQuestion(Question question) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('${_queue.length} more due after this one', style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(question.prompt, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                if (question.questionType == questionTypeMultipleChoice)
                  // groupValue/onChanged are deprecated in favor of RadioGroup as of
                  // Flutter 3.32, but still functional; not worth migrating for one
                  // radio list yet.
                  ...question.choices.map((choice) => RadioListTile<String>(
                        title: Text(choice.choiceText),
                        // ignore: deprecated_member_use
                        groupValue: _selectedChoice,
                        value: choice.choiceText,
                        // ignore: deprecated_member_use
                        onChanged: _submitted ? null : (value) => setState(() => _selectedChoice = value),
                      ))
                else
                  TextField(
                    controller: _answerController,
                    enabled: !_submitted,
                    decoration: const InputDecoration(labelText: 'Your answer'),
                  ),
                const SizedBox(height: 16),
                if (!_submitted)
                  ElevatedButton(onPressed: _submit, child: const Text('Submit'))
                else ...[
                  Text(
                    _wasCorrect == true ? 'Correct!' : 'Incorrect. Expected: ${question.expectedAnswer}',
                    style: TextStyle(
                      color: _wasCorrect == true ? Colors.greenAccent : Colors.amberAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _advance, child: const Text('Next')),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
