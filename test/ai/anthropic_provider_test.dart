import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quizapp/ai/anthropic_provider.dart';
import 'package:quizapp/ai/base.dart';

void main() {
  test('parses a successful response into GeneratedQuestions', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(request.headers['x-api-key'], 'test-key');
      expect(request.headers['anthropic-version'], '2023-06-01');

      return http.Response(
        jsonEncode({
          'content': [
            {
              'text': jsonEncode({
                'questions': [
                  {'prompt': 'What is 2+2?', 'expected_answer': '4', 'choices': null, 'correct_choice_index': null}
                ]
              }),
            },
          ],
        }),
        200,
      );
    });

    final provider = AnthropicProvider(apiKey: 'test-key', model: 'claude-sonnet-5', httpClient: client);
    final questions = await provider.generateQuestions('Some note text');

    expect(questions, hasLength(1));
    expect(questions.first.expectedAnswer, '4');
  });

  test('non-2xx status raises AIProviderError', () async {
    final client = MockClient((request) async => http.Response('bad request', 400));
    final provider = AnthropicProvider(apiKey: 'k', model: 'm', httpClient: client);

    await expectLater(provider.generateQuestions('note'), throwsA(isA<AIProviderError>()));
  });

  test('unexpected response shape raises AIProviderError', () async {
    final client = MockClient((request) async => http.Response(jsonEncode({'unexpected': true}), 200));
    final provider = AnthropicProvider(apiKey: 'k', model: 'm', httpClient: client);

    await expectLater(provider.generateQuestions('note'), throwsA(isA<AIProviderError>()));
  });
}
