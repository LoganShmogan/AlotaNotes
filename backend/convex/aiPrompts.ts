// Prompt building and response parsing for quiz generation. A port of the
// Flutter app's lib/ai/prompts.dart and parseGeneratedQuestions in
// lib/ai/base.dart, so a note generates the same kind of questions on
// QuillFin's key as on the user's own.

export type QuestionFormat = "short_answer" | "multiple_choice";

export type LinkedNote = { title: string; excerpt: string; sharedKeywords: string[] };

export type GeneratedQuestion = {
  questionType: QuestionFormat;
  prompt: string;
  expectedAnswer: string;
  choices: string[] | null;
  correctChoiceIndex: number | null;
};

export const systemPrompt =
  "You are a quiz question generator. Given study notes, generate quiz questions " +
  "strictly in the requested format. Respond with ONLY valid JSON matching this " +
  'schema, with no other text: {"questions": [{"prompt": string, ' +
  '"expected_answer": string, "choices": array of strings or null, ' +
  '"correct_choice_index": integer or null}]}.';

const multipleChoiceInstruction =
  "Generate multiple-choice questions: each question must include exactly 4 plausible " +
  '"choices" (one correct, three distractors) and "correct_choice_index" pointing to the ' +
  "index of the correct one within choices.";
const shortAnswerInstruction = 'Generate short-answer questions: set "choices" and "correct_choice_index" to null.';

function linkedNotesBlock(linkedNotes: LinkedNote[] | undefined): string {
  if (!linkedNotes || linkedNotes.length === 0) return "";
  const related = linkedNotes
    .map((n) => `- ${n.title} (shared concepts: ${n.sharedKeywords.join(", ")}): ${n.excerpt}`)
    .join("\n");
  return `\n\nRelated notes for additional context:\n${related}`;
}

export function buildQuestionGenerationPrompt(
  noteText: string,
  numQuestions: number,
  questionFormat: QuestionFormat,
  linkedNotes?: LinkedNote[],
): { system: string; user: string } {
  const instruction = questionFormat === "multiple_choice" ? multipleChoiceInstruction : shortAnswerInstruction;
  const user =
    `Generate ${numQuestions} quiz questions from the following note.\n` +
    `${instruction}\n\n` +
    `Note:\n${noteText}` +
    linkedNotesBlock(linkedNotes);
  return { system: systemPrompt, user };
}

export class GenerationParseError extends Error {}

// Models sometimes wrap JSON in a Markdown code fence despite the prompt.
function stripCodeFence(content: string): string {
  const match = content.trim().match(/^```(?:json)?\s*([\s\S]*?)\s*```$/);
  return match ? match[1] : content;
}

export function parseGeneratedQuestions(content: string): GeneratedQuestion[] {
  let data: unknown;
  try {
    data = JSON.parse(stripCodeFence(content));
  } catch (e) {
    throw new GenerationParseError(`AI response was not valid JSON: ${e}`);
  }
  const rawQuestions = (data as { questions?: unknown } | null)?.questions;
  if (!Array.isArray(rawQuestions)) {
    throw new GenerationParseError("AI response JSON missing 'questions' key");
  }
  return rawQuestions.map((raw) => {
    if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
      throw new GenerationParseError("AI response question entry malformed: not an object");
    }
    const { prompt, expected_answer, choices: rawChoices, correct_choice_index } = raw as Record<string, unknown>;
    if (typeof prompt !== "string" || typeof expected_answer !== "string") {
      throw new GenerationParseError("AI response question entry malformed: missing prompt/expected_answer");
    }
    const choices = Array.isArray(rawChoices) && rawChoices.length > 0 ? rawChoices.map(String) : null;
    const index = Number.isInteger(correct_choice_index) ? (correct_choice_index as number) : null;
    return {
      questionType: choices !== null ? "multiple_choice" : "short_answer",
      prompt,
      expectedAnswer: expected_answer,
      choices,
      correctChoiceIndex: choices !== null && index !== null && index >= 0 && index < choices.length ? index : null,
    };
  });
}
