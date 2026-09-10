/// OpenAI-compatible Chat Completions provider. Direct port of the Python
/// desktop app's `ai/openai_provider.py` -- `base_url` override covers any
/// OpenAI-compatible endpoint: OpenRouter, Groq, Ollama, LM Studio, etc.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'base.dart';
import 'prompts.dart';

class OpenAIProvider extends AIProvider {
  static const defaultBaseUrl = 'https://api.openai.com/v1';

  OpenAIProvider({
    required super.apiKey,
    required super.model,
    super.baseUrl,
    super.timeout,
    super.httpClient,
  });

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> payload) async {
    final url = Uri.parse('${(baseUrl ?? defaultBaseUrl).replaceAll(RegExp(r"/$"), "")}$path');
    http.Response response;
    try {
      response = await httpClient
          .post(
            url,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(timeout);
    } catch (e) {
      throw AIProviderError('Request to OpenAI-compatible API failed: $e');
    }

    if (response.statusCode >= 400) {
      throw AIProviderError('OpenAI-compatible API returned HTTP ${response.statusCode}: ${response.body}');
    }

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw AIProviderError('OpenAI-compatible API returned invalid JSON: $e');
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
      'messages': [
        {'role': 'system', 'content': prompts.$1},
        {'role': 'user', 'content': prompts.$2},
      ],
      'response_format': {'type': 'json_object'},
    };
    final data = await _post('/chat/completions', payload);
    String content;
    try {
      content = data['choices'][0]['message']['content'] as String;
    } catch (e) {
      throw AIProviderError('Unexpected OpenAI-compatible response shape: $e');
    }
    return parseGeneratedQuestions(content);
  }
}
