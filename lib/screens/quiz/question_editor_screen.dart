import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/models.dart';
import '../../storage/notes_repo.dart';
import '../../storage/questions_repo.dart';
import '../../theme/theme.dart';
import '../../theme/widgets.dart';
import '../notes/note_editor_screen.dart';

/// Manual editing of an AI-generated (or previously edited) question, plus
/// traceability back to the note it came from -- both explicitly called out
/// in Docs/flutter_rewrite_plan.md as new capabilities the old desktop app
/// didn't have.
class QuestionEditorScreen extends StatefulWidget {
  final Database db;
  final int questionId;
  const QuestionEditorScreen({super.key, required this.db, required this.questionId});

  @override
  State<QuestionEditorScreen> createState() => _QuestionEditorScreenState();
}

class _QuestionEditorScreenState extends State<QuestionEditorScreen> {
  late final QuestionsRepo _questionsRepo = QuestionsRepo(widget.db);
  late final NotesRepo _notesRepo = NotesRepo(widget.db);
  final _promptController = TextEditingController();
  final _expectedAnswerController = TextEditingController();
  final List<TextEditingController> _choiceControllers = [];
  int? _correctChoiceIndex;
  Question? _question;
  Note? _sourceNote;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final question = await _questionsRepo.get(widget.questionId);
    final note = await _notesRepo.get(question.noteId);
    _promptController.text = question.prompt;
    _expectedAnswerController.text = question.expectedAnswer;
    for (var i = 0; i < question.choices.length; i++) {
      _choiceControllers.add(TextEditingController(text: question.choices[i].choiceText));
      if (question.choices[i].isCorrect) _correctChoiceIndex = i;
    }
    if (!mounted) return;
    setState(() {
      _question = question;
      _sourceNote = note;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    List<(String, bool)>? choices;
    var expectedAnswer = _expectedAnswerController.text.trim();
    if (_choiceControllers.isNotEmpty) {
      choices = [
        for (var i = 0; i < _choiceControllers.length; i++)
          (_choiceControllers[i].text.trim(), i == _correctChoiceIndex),
      ];
      // The expected-answer field is hidden for multiple choice, so keep it
      // in step with the selected choice; the quiz shows it on a wrong answer.
      for (final (text, isCorrect) in choices) {
        if (isCorrect) expectedAnswer = text;
      }
    }
    await _questionsRepo.updateContent(
      widget.questionId,
      prompt: _promptController.text.trim(),
      expectedAnswer: expectedAnswer,
      choices: choices,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved.')));
  }

  void _openSourceNote(Note note) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(db: widget.db, noteId: note.id)),
    );
  }

  @override
  void dispose() {
    _promptController.dispose();
    _expectedAnswerController.dispose();
    for (final c in _choiceControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Question'),
        actions: [
          IconButton(
            icon: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_sourceNote != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('Generated from'),
                      subtitle: Text(_sourceNote!.title),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openSourceNote(_sourceNote!),
                    ),
                  ),
                if (_question?.isManuallyEdited == true)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Align(alignment: Alignment.centerLeft, child: Pill('Manually edited', color: colorYellow)),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _promptController,
                  decoration: const InputDecoration(labelText: 'Question prompt'),
                  maxLines: null,
                ),
                const SizedBox(height: 16),
                if (_choiceControllers.isEmpty)
                  TextField(
                    controller: _expectedAnswerController,
                    decoration: const InputDecoration(labelText: 'Expected answer'),
                  )
                else ...[
                  const SectionLabel('Choices (select the correct one)'),
                  for (var i = 0; i < _choiceControllers.length; i++)
                    Row(
                      children: [
                        Radio<int>(
                          // ignore: deprecated_member_use
                          groupValue: _correctChoiceIndex,
                          value: i,
                          // ignore: deprecated_member_use
                          onChanged: (value) => setState(() => _correctChoiceIndex = value),
                        ),
                        Expanded(child: TextField(controller: _choiceControllers[i])),
                      ],
                    ),
                ],
              ],
            ),
    );
  }
}
