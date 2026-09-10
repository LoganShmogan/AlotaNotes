import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/models.dart';
import '../../storage/questions_repo.dart';
import '../quiz/question_editor_screen.dart';

/// Traceability from the note's side: every question generated from this
/// note, with its current schedule position at a glance.
class NoteQuestionsScreen extends StatefulWidget {
  final Database db;
  final int noteId;
  const NoteQuestionsScreen({super.key, required this.db, required this.noteId});

  @override
  State<NoteQuestionsScreen> createState() => _NoteQuestionsScreenState();
}

class _NoteQuestionsScreenState extends State<NoteQuestionsScreen> {
  late final QuestionsRepo _questionsRepo = QuestionsRepo(widget.db);
  List<Question> _questions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final questions = await _questionsRepo.listByNote(widget.noteId);
    if (!mounted) return;
    setState(() {
      _questions = questions;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Questions from this note')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _questions.isEmpty
              ? const Center(child: Text('No questions generated yet.'))
              : ListView.builder(
                  itemCount: _questions.length,
                  itemBuilder: (context, index) {
                    final question = _questions[index];
                    return ListTile(
                      leading: Icon(question.active ? Icons.quiz_outlined : Icons.block),
                      title: Text(question.prompt, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${question.questionType == questionTypeMultipleChoice ? 'Multiple choice' : 'Short answer'}'
                        '${question.isManuallyEdited ? ' · edited' : ''}',
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => QuestionEditorScreen(db: widget.db, questionId: question.id),
                          ),
                        );
                        _refresh();
                      },
                    );
                  },
                ),
    );
  }
}
