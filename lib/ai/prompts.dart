/// Prompt templates for AI-driven quiz question generation. Direct port of
/// the Python desktop app's `ai/prompts.py`.
library;

import '../core/models.dart';
import 'base.dart';

const systemPrompt =
    'You are a quiz question generator. Given study notes, generate quiz questions '
    'strictly in the requested format. Respond with ONLY valid JSON matching this '
    'schema, with no other text: {"questions": [{"prompt": string, '
    '"expected_answer": string, "choices": array of strings or null, '
    '"correct_choice_index": integer or null}]}.';

const _multipleChoiceInstruction =
    'Generate multiple-choice questions: each question must include exactly 4 plausible '
    '"choices" (one correct, three distractors) and "correct_choice_index" pointing to the '
    'index of the correct one within choices.';
const _shortAnswerInstruction =
    'Generate short-answer questions: set "choices" and "correct_choice_index" to null.';

String _formatInstruction(String questionFormat) =>
    questionFormat == questionTypeMultipleChoice ? _multipleChoiceInstruction : _shortAnswerInstruction;

String _linkedNotesBlock(List<LinkedNoteContext>? linkedNotesContext) {
  if (linkedNotesContext == null || linkedNotesContext.isEmpty) return '';
  final related = linkedNotesContext
      .map((ctx) => '- ${ctx.title} (shared concepts: ${ctx.sharedKeywords.join(', ')}): ${ctx.excerpt}')
      .join('\n');
  return '\n\nRelated notes for additional context:\n$related';
}

/// Returns (systemPrompt, userPrompt).
(String, String) buildQuestionGenerationPrompt(
  String noteText,
  int numQuestions,
  String questionFormat, {
  List<LinkedNoteContext>? linkedNotesContext,
}) {
  final userPrompt = 'Generate $numQuestions quiz questions from the following note.\n'
      '${_formatInstruction(questionFormat)}\n\n'
      'Note:\n$noteText'
      '${_linkedNotesBlock(linkedNotesContext)}';
  return (systemPrompt, userPrompt);
}
