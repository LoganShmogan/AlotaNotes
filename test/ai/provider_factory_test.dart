import 'package:flutter_test/flutter_test.dart';
import 'package:quizapp/ai/anthropic_provider.dart';
import 'package:quizapp/ai/openai_provider.dart';
import 'package:quizapp/ai/provider_factory.dart';

void main() {
  test('knownProviders lists every buildable provider', () {
    expect(knownProviders, [providerOpenAI, providerAnthropic]);
  });

  test('builds an OpenAIProvider with the given settings', () {
    final provider = buildProvider(providerOpenAI, 'key', 'gpt-4o-mini', 'http://localhost:11434/v1');
    expect(provider, isA<OpenAIProvider>());
    expect(provider.apiKey, 'key');
    expect(provider.model, 'gpt-4o-mini');
    expect(provider.baseUrl, 'http://localhost:11434/v1');
  });

  test('builds an AnthropicProvider with the given settings', () {
    final provider = buildProvider(providerAnthropic, 'key', 'claude-haiku-5-5', null);
    expect(provider, isA<AnthropicProvider>());
    expect(provider.model, 'claude-haiku-5-5');
    expect(provider.baseUrl, isNull);
  });

  test('unknown provider names throw UnknownProviderError listing the known ones', () {
    expect(
      () => buildProvider('gemini', 'key', 'model', null),
      throwsA(isA<UnknownProviderError>().having(
        (e) => e.toString(),
        'message',
        "Unknown AI provider 'gemini'. Known providers: openai, anthropic",
      )),
    );
  });
}
