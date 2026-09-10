/// Single registration point for AI providers, mirroring the Python desktop
/// app's `ai/provider_factory.py`.
library;

import 'anthropic_provider.dart';
import 'base.dart';
import 'openai_provider.dart';

const providerOpenAI = 'openai';
const providerAnthropic = 'anthropic';
const knownProviders = [providerOpenAI, providerAnthropic];

class UnknownProviderError implements Exception {
  final String message;
  const UnknownProviderError(this.message);
  @override
  String toString() => message;
}

AIProvider buildProvider(String providerName, String apiKey, String model, String? baseUrl) {
  switch (providerName) {
    case providerOpenAI:
      return OpenAIProvider(apiKey: apiKey, model: model, baseUrl: baseUrl);
    case providerAnthropic:
      return AnthropicProvider(apiKey: apiKey, model: model, baseUrl: baseUrl);
    default:
      throw UnknownProviderError(
        "Unknown AI provider '$providerName'. Known providers: ${knownProviders.join(', ')}",
      );
  }
}
