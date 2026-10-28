import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quillfin/ai/base.dart';
import 'package:quillfin/ai/openai_provider.dart';
import 'package:quillfin/core/models.dart';

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

  test('throws AIProviderError when a question entry is not an object', () {
    expect(
      () => parseGeneratedQuestions('{"questions": ["just a string"]}'),
      throwsA(isA<AIProviderError>().having((e) => e.message, 'message', contains('not an object'))),
    );
  });

  test('an empty choices list is treated as short answer', () {
    final questions = parseGeneratedQuestions(
      '{"questions": [{"prompt": "P", "expected_answer": "A", "choices": []}]}',
    );
    expect(questions.single.questionType, questionTypeShortAnswer);
    expect(questions.single.choices, isNull);
  });

  test('AIProviderError.toString is its message', () {
    expect(const AIProviderError('boom').toString(), 'boom');
  });

  test('providers default to a real http.Client and a 30s timeout', () {
    final provider = OpenAIProvider(apiKey: 'k', model: 'm');
    expect(provider.httpClient, isA<http.Client>());
    expect(provider.timeout, const Duration(seconds: 30));
  });
}
