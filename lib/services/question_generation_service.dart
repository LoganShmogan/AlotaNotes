/// Drives AI question generation for a note and persists the results.
/// Mirrors the Python desktop app's `gui/controllers/question_generation_controller.py`.
///
/// Note: linked-note context (cross-note keyword linking) isn't ported yet
/// -- see Docs/flutter_rewrite_plan.md's open questions -- so generation
/// here only ever sees the single note's own body.
library;

import '../ai/base.dart';
import '../core/models.dart';
import '../storage/notes_repo.dart';
import '../storage/questions_repo.dart';

const defaultNumQuestions = 5;

class QuestionGenerationService {
  final NotesRepo notesRepo;
  final QuestionsRepo questionsRepo;
  final AIProvider provider;
  final String defaultQuestionFormat;

  const QuestionGenerationService({
    required this.notesRepo,
    required this.questionsRepo,
    required this.provider,
    required this.defaultQuestionFormat,
  });

  Future<List<Question>> generateForNote(int noteId, {int numQuestions = defaultNumQuestions}) async {
    final note = await notesRepo.get(noteId);
    final generated = await provider.generateQuestions(
      note.body,
      numQuestions: numQuestions,
      questionFormat: defaultQuestionFormat,
    );

    final created = <Question>[];
    for (final g in generated) {
      List<(String, bool)>? choices;
      if (g.choices != null && g.choices!.isNotEmpty) {
        choices = [
          for (var i = 0; i < g.choices!.length; i++) (g.choices![i], i == g.correctChoiceIndex),
        ];
      }
      final question = await questionsRepo.create(
        note.id,
        g.questionType,
        g.prompt,
        g.expectedAnswer,
        choices: choices,
      );
      created.add(question);
    }
    return created;
  }
}
