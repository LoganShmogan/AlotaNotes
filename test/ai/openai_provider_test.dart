// Every request is mocked via http's own MockClient -- no real network or
// API key involved, same rationale as the Python desktop app's
// `responses`-mocked provider tests (see Docs/ai_providers.md there).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quillfin/ai/base.dart';
import 'package:quillfin/ai/openai_provider.dart';

void main() {
  test('parses a successful response into GeneratedQuestions', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://api.openai.com/v1/chat/completions');
      expect(request.headers['Authorization'], 'Bearer test-key');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], 'gpt-4o-mini');

      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'questions': [
                    {'prompt': 'What is 2+2?', 'expected_answer': '4', 'choices': null, 'correct_choice_index': null}
                  ]
                }),
              },
            },
          ],
        }),
        200,
      );
    });

    final provider = OpenAIProvider(apiKey: 'test-key', model: 'gpt-4o-mini', httpClient: client);
    final questions = await provider.generateQuestions('Some note text');

    expect(questions, hasLength(1));
    expect(questions.first.prompt, 'What is 2+2?');
  });

  test('non-2xx status raises AIProviderError', () async {
    final client = MockClient((request) async => http.Response('server error', 500));
    final provider = OpenAIProvider(apiKey: 'k', model: 'm', httpClient: client);

    await expectLater(provider.generateQuestions('note'), throwsA(isA<AIProviderError>()));
  });

  test('network failure raises AIProviderError', () async {
    final client = MockClient((request) async => throw const SocketExceptionStub());
    final provider = OpenAIProvider(apiKey: 'k', model: 'm', httpClient: client);

    await expectLater(provider.generateQuestions('note'), throwsA(isA<AIProviderError>()));
  });

  test('invalid JSON body raises AIProviderError', () async {
    final client = MockClient((request) async => http.Response('not json', 200));
    final provider = OpenAIProvider(apiKey: 'k', model: 'm', httpClient: client);

    await expectLater(provider.generateQuestions('note'), throwsA(isA<AIProviderError>()));
  });

  test('unexpected response shape raises AIProviderError', () async {
    final client = MockClient((request) async => http.Response(jsonEncode({'unexpected': true}), 200));
    final provider = OpenAIProvider(apiKey: 'k', model: 'm', httpClient: client);

    await expectLater(provider.generateQuestions('note'), throwsA(isA<AIProviderError>()));
  });

  test('base_url override is respected', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'http://localhost:11434/v1/chat/completions');
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({'questions': []}),
              },
            },
          ],
        }),
        200,
      );
    });
    final provider = OpenAIProvider(
      apiKey: 'k',
      model: 'llama3',
      baseUrl: 'http://localhost:11434/v1',
      httpClient: client,
    );

    final questions = await provider.generateQuestions('note');
    expect(questions, isEmpty);
  });
}

/// A minimal stand-in so this test file doesn't need `dart:io`'s
/// SocketException just to prove "any thrown exception becomes AIProviderError".
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'SocketExceptionStub: connection refused';
}
