import 'package:flutter_test/flutter_test.dart';
import 'package:quizapp/ai/base.dart';
import 'package:quizapp/core/models.dart';

void main() {
  test('parses short-answer questions', () {
    const json = '''
    {"questions": [
      {"prompt": "What is 2+2?", "expected_answer": "4", "choices": null, "correct_choice_index": null}
    ]}
    ''';
    final questions = parseGeneratedQuestions(json);
    expect(questions, hasLength(1));
    expect(questions.first.questionType, questionTypeShortAnswer);
    expect(questions.first.prompt, 'What is 2+2?');
    expect(questions.first.expectedAnswer, '4');
    expect(questions.first.choices, isNull);
  });

  test('parses multiple-choice questions', () {
    const json = '''
    {"questions": [
      {"prompt": "Pick one", "expected_answer": "B", "choices": ["A", "B", "C", "D"], "correct_choice_index": 1}
    ]}
    ''';
    final questions = parseGeneratedQuestions(json);
    expect(questions.first.questionType, questionTypeMultipleChoice);
    expect(questions.first.choices, ['A', 'B', 'C', 'D']);
    expect(questions.first.correctChoiceIndex, 1);
  });

  test('throws AIProviderError on invalid JSON', () {
    expect(() => parseGeneratedQuestions('not json'), throwsA(isA<AIProviderError>()));
  });

  test('throws AIProviderError when questions key is missing', () {
    expect(() => parseGeneratedQuestions('{"foo": []}'), throwsA(isA<AIProviderError>()));
  });

  test('throws AIProviderError on a malformed question entry', () {
    expect(
      () => parseGeneratedQuestions('{"questions": [{"prompt": "no expected answer"}]}'),
      throwsA(isA<AIProviderError>()),
    );
  });
}
