/// Anthropic Messages API provider. Direct port of the Python desktop app's
/// `ai/anthropic_provider.py`.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'base.dart';
import 'prompts.dart';

class AnthropicProvider extends AIProvider {
  static const defaultBaseUrl = 'https://api.anthropic.com';
  static const anthropicVersion = '2023-06-01';
  static const maxTokens = 2048;

  AnthropicProvider({
    required super.apiKey,
    required super.model,
    super.baseUrl,
    super.timeout,
    super.httpClient,
  });

  Future<Map<String, dynamic>> _post(Map<String, dynamic> payload) async {
    final url = Uri.parse('${(baseUrl ?? defaultBaseUrl).replaceAll(RegExp(r"/$"), "")}/v1/messages');
    http.Response response;
    try {
      response = await httpClient
          .post(
            url,
            headers: {
              'x-api-key': apiKey,
              'anthropic-version': anthropicVersion,
              'content-type': 'application/json',
              // Required for Anthropic to allow the request from a browser
              // (CORS) in the web build; ignored on other platforms.
              'anthropic-dangerous-direct-browser-access': 'true',
            },
            body: jsonEncode(payload),
          )
          .timeout(timeout);
    } catch (e) {
      throw AIProviderError('Request to Anthropic API failed: $e');
    }

    if (response.statusCode >= 400) {
      throw AIProviderError('Anthropic API returned HTTP ${response.statusCode}: ${response.body}');
    }

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw AIProviderError('Anthropic API returned invalid JSON: $e');
    }
  }

  @override
  Future<List<GeneratedQuestion>> generateQuestions(
    String noteText, {
    int numQuestions = 5,
    String questionFormat = 'short_answer',
    List<LinkedNoteContext>? linkedNotesContext,
  }) async {
    final prompts = buildQuestionGenerationPrompt(
      noteText,
      numQuestions,
      questionFormat,
      linkedNotesContext: linkedNotesContext,
    );
    final payload = {
      'model': model,
      'max_tokens': maxTokens,
      'system': prompts.$1,
      'messages': [
        {'role': 'user', 'content': prompts.$2},
      ],
    };
    final data = await _post(payload);
    String content;
    try {
      content = data['content'][0]['text'] as String;
    } catch (e) {
      throw AIProviderError('Unexpected Anthropic response shape: $e');
    }
    return parseGeneratedQuestions(content);
  }
}
