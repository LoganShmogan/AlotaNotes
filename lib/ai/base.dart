/// Provider-agnostic AI abstraction for quiz question generation. Direct
/// port of the Python desktop app's `ai/base.py` -- same reasoning: grading
/// is NOT part of this interface (that's local, see core/grading.dart), and
/// every provider implementation wraps its own failures into one shared
/// `AIProviderError` so callers only ever need to catch one type.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/models.dart';

class GeneratedQuestion {
  final String questionType;
  final String prompt;
  final String expectedAnswer;
  final List<String>? choices;
  final int? correctChoiceIndex;

  const GeneratedQuestion({
    required this.questionType,
    required this.prompt,
    required this.expectedAnswer,
    this.choices,
    this.correctChoiceIndex,
  });
}

class LinkedNoteContext {
  final int noteId;
  final String title;
  final String excerpt;
  final List<String> sharedKeywords;

  const LinkedNoteContext({
    required this.noteId,
    required this.title,
    required this.excerpt,
    required this.sharedKeywords,
  });
}

class AIProviderError implements Exception {
  final String message;
  const AIProviderError(this.message);
  @override
  String toString() => message;
}

abstract class AIProvider {
  final String apiKey;
  final String model;
  final String? baseUrl;
  final Duration timeout;
  // Injectable so tests can mock the HTTP boundary (via http's own
  // testing.dart MockClient) instead of hitting a real network -- same
  // reasoning as the Python desktop app's `responses`-mocked provider tests.
  final http.Client httpClient;

  AIProvider({
    required this.apiKey,
    required this.model,
    this.baseUrl,
    this.timeout = const Duration(seconds: 30),
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client();

  Future<List<GeneratedQuestion>> generateQuestions(
    String noteText, {
    int numQuestions = 5,
    String questionFormat = questionTypeShortAnswer,
    List<LinkedNoteContext>? linkedNotesContext,
  });
}

/// Shared strict-JSON response parser used by every provider implementation.
List<GeneratedQuestion> parseGeneratedQuestions(String content) {
  Map<String, dynamic> data;
  try {
    data = jsonDecode(content) as Map<String, dynamic>;
  } on FormatException catch (e) {
    throw AIProviderError('AI response was not valid JSON: $e');
  }

  final rawQuestions = data['questions'];
  if (rawQuestions is! List) {
    throw AIProviderError("AI response JSON missing 'questions' key");
  }

  final questions = <GeneratedQuestion>[];
  for (final raw in rawQuestions) {
    if (raw is! Map) {
      throw AIProviderError('AI response question entry malformed: not an object');
    }
    final prompt = raw['prompt'];
    final expectedAnswer = raw['expected_answer'];
    if (prompt is! String || expectedAnswer is! String) {
      throw AIProviderError('AI response question entry malformed: missing prompt/expected_answer');
    }
    final rawChoices = raw['choices'];
    List<String>? choices;
    if (rawChoices is List && rawChoices.isNotEmpty) {
      choices = rawChoices.map((c) => c.toString()).toList();
    }
    questions.add(GeneratedQuestion(
      questionType: choices != null ? questionTypeMultipleChoice : questionTypeShortAnswer,
      prompt: prompt,
      expectedAnswer: expectedAnswer,
      choices: choices,
      correctChoiceIndex: raw['correct_choice_index'] as int?,
    ));
  }
  return questions;
}
