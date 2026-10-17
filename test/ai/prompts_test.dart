import 'package:flutter_test/flutter_test.dart';
import 'package:quizapp/ai/base.dart';
import 'package:quizapp/ai/prompts.dart';
import 'package:quizapp/core/models.dart';

void main() {
  test('returns the shared system prompt and a user prompt with the note', () {
    final (system, user) = buildQuestionGenerationPrompt('Cells divide.', 3, questionTypeShortAnswer);
    expect(system, systemPrompt);
    expect(user, startsWith('Generate 3 quiz questions from the following note.'));
    expect(user, contains('Note:\nCells divide.'));
  });

  test('short-answer format asks for null choices', () {
    final (_, user) = buildQuestionGenerationPrompt('n', 1, questionTypeShortAnswer);
    expect(user, contains('Generate short-answer questions'));
    expect(user, isNot(contains('multiple-choice')));
  });

  test('multiple-choice format asks for 4 choices', () {
    final (_, user) = buildQuestionGenerationPrompt('n', 1, questionTypeMultipleChoice);
    expect(user, contains('Generate multiple-choice questions'));
    expect(user, contains('exactly 4 plausible'));
  });

  test('no related-notes block when linked context is null or empty', () {
    final (_, withNull) = buildQuestionGenerationPrompt('n', 1, questionTypeShortAnswer);
    final (_, withEmpty) =
        buildQuestionGenerationPrompt('n', 1, questionTypeShortAnswer, linkedNotesContext: const []);
    expect(withNull, isNot(contains('Related notes')));
    expect(withEmpty, isNot(contains('Related notes')));
  });

  test('linked notes are appended one per line with their shared keywords', () {
    final (_, user) = buildQuestionGenerationPrompt(
      'n',
      1,
      questionTypeShortAnswer,
      // Built at runtime rather than as const, as the app will once note
      // linking populates these (see Docs/future_work.md).
      linkedNotesContext: [
        for (final (id, title, excerpt, keywords) in [
          (1, 'Mitosis', 'Splitting.', ['cell', 'dna']),
          (2, 'Meiosis', 'Halving.', ['cell']),
        ])
          LinkedNoteContext(noteId: id, title: title, excerpt: excerpt, sharedKeywords: keywords),
      ],
    );
    expect(
      user,
      endsWith('\n\nRelated notes for additional context:\n'
          '- Mitosis (shared concepts: cell, dna): Splitting.\n'
          '- Meiosis (shared concepts: cell): Halving.'),
    );
  });
}
