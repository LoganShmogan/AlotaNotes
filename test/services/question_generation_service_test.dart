import 'package:flutter_test/flutter_test.dart';
import 'package:quillfin/ai/base.dart';
import 'package:quillfin/core/models.dart';
import 'package:quillfin/services/question_generation_service.dart';
import 'package:quillfin/storage/folders_repo.dart';
import 'package:quillfin/storage/notes_repo.dart';
import 'package:quillfin/storage/questions_repo.dart';

import '../helpers/test_env.dart';

/// Returns canned questions and records what it was asked for.
class FakeProvider extends AIProvider {
  final List<GeneratedQuestion> questions;
  String? lastNoteText;
  int? lastNumQuestions;
  String? lastFormat;

  FakeProvider(this.questions) : super(apiKey: 'k', model: 'm');

  @override
  Future<List<GeneratedQuestion>> generateQuestions(
    String noteText, {
    int numQuestions = 5,
    String questionFormat = questionTypeShortAnswer,
    List<LinkedNoteContext>? linkedNotesContext,
  }) async {
    lastNoteText = noteText;
    lastNumQuestions = numQuestions;
    lastFormat = questionFormat;
    return questions;
  }
}

void main() {
  setUpTestEnv();

  Future<(NotesRepo, QuestionsRepo, int)> setUpNote(String body) async {
    final db = await openTestDatabase();
    final folder = await FoldersRepo(db).create('F');
    final notes = NotesRepo(db);
    final note = await notes.create(folder.id, 'N', body);
    return (notes, QuestionsRepo(db), note.id);
  }

  test('sends the note body and settings to the provider', () async {
    final (notes, questions, noteId) = await setUpNote('Photosynthesis makes sugar.');
    final provider = FakeProvider(const []);
    final service = QuestionGenerationService(
      notesRepo: notes,
      questionsRepo: questions,
      provider: provider,
      defaultQuestionFormat: questionTypeMultipleChoice,
    );

    await service.generateForNote(noteId, numQuestions: 2);
    expect(provider.lastNoteText, 'Photosynthesis makes sugar.');
    expect(provider.lastNumQuestions, 2);
    expect(provider.lastFormat, questionTypeMultipleChoice);
  });

  test('defaults to five questions', () async {
    final (notes, questions, noteId) = await setUpNote('b');
    final provider = FakeProvider(const []);
    await QuestionGenerationService(
      notesRepo: notes,
      questionsRepo: questions,
      provider: provider,
      defaultQuestionFormat: questionTypeShortAnswer,
    ).generateForNote(noteId);
    expect(provider.lastNumQuestions, defaultNumQuestions);
  });

  test('persists short-answer and multiple-choice questions against the note', () async {
    final (notes, questions, noteId) = await setUpNote('b');
    final service = QuestionGenerationService(
      notesRepo: notes,
      questionsRepo: questions,
      provider: FakeProvider(const [
        GeneratedQuestion(questionType: questionTypeShortAnswer, prompt: 'What?', expectedAnswer: 'That'),
        GeneratedQuestion(
          questionType: questionTypeMultipleChoice,
          prompt: 'Which?',
          expectedAnswer: 'B',
          choices: ['A', 'B', 'C'],
          correctChoiceIndex: 1,
        ),
        // Empty choices are stored as a plain question with no choices.
        GeneratedQuestion(questionType: questionTypeShortAnswer, prompt: 'Empty', expectedAnswer: 'x', choices: []),
      ]),
      defaultQuestionFormat: questionTypeShortAnswer,
    );

    final created = await service.generateForNote(noteId);
    expect(created, hasLength(3));

    final stored = await questions.listByNote(noteId);
    expect(stored.map((q) => q.prompt), ['What?', 'Which?', 'Empty']);
    expect(stored[0].choices, isEmpty);
    expect(stored[1].choices.map((c) => (c.choiceText, c.isCorrect)), [('A', false), ('B', true), ('C', false)]);
    expect(stored[2].choices, isEmpty);
  });

  test('provider errors propagate without saving anything', () async {
    final (notes, questions, noteId) = await setUpNote('b');
    final service = QuestionGenerationService(
      notesRepo: notes,
      questionsRepo: questions,
      provider: _ThrowingProvider(),
      defaultQuestionFormat: questionTypeShortAnswer,
    );

    await expectLater(service.generateForNote(noteId), throwsA(isA<AIProviderError>()));
    expect(await questions.listByNote(noteId), isEmpty);
  });
}

class _ThrowingProvider extends FakeProvider {
  _ThrowingProvider() : super(const []);

  @override
  Future<List<GeneratedQuestion>> generateQuestions(
    String noteText, {
    int numQuestions = 5,
    String questionFormat = questionTypeShortAnswer,
    List<LinkedNoteContext>? linkedNotesContext,
  }) async =>
      throw const AIProviderError('rate limited');
}
