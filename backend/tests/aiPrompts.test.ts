import { describe, expect, test } from "vitest";
import { buildQuestionGenerationPrompt, GenerationParseError, parseGeneratedQuestions, systemPrompt } from "../convex/aiPrompts";

describe("buildQuestionGenerationPrompt", () => {
  test("matches the Flutter app's short-answer prompt", () => {
    const { system, user } = buildQuestionGenerationPrompt("Note body", 3, "short_answer");
    expect(system).toBe(systemPrompt);
    expect(user).toBe(
      "Generate 3 quiz questions from the following note.\n" +
        'Generate short-answer questions: set "choices" and "correct_choice_index" to null.\n\n' +
        "Note:\nNote body",
    );
  });

  test("asks for four choices and lists linked notes", () => {
    const { user } = buildQuestionGenerationPrompt("Body", 2, "multiple_choice", [
      { title: "Cells", excerpt: "About cells", sharedKeywords: ["atp", "energy"] },
    ]);
    expect(user).toContain("exactly 4 plausible");
    expect(user).toContain("\n\nRelated notes for additional context:\n- Cells (shared concepts: atp, energy): About cells");
  });
});

describe("parseGeneratedQuestions", () => {
  test("reads short-answer and multiple-choice questions", () => {
    const questions = parseGeneratedQuestions(
      JSON.stringify({
        questions: [
          { prompt: "Q1", expected_answer: "A1", choices: null, correct_choice_index: null },
          { prompt: "Q2", expected_answer: "B", choices: ["A", "B", 3, "D"], correct_choice_index: 1 },
        ],
      }),
    );
    expect(questions).toEqual([
      { questionType: "short_answer", prompt: "Q1", expectedAnswer: "A1", choices: null, correctChoiceIndex: null },
      { questionType: "multiple_choice", prompt: "Q2", expectedAnswer: "B", choices: ["A", "B", "3", "D"], correctChoiceIndex: 1 },
    ]);
  });

  test("accepts JSON inside a code fence", () => {
    const fenced = '```json\n{"questions": [{"prompt": "Q", "expected_answer": "A"}]}\n```';
    expect(parseGeneratedQuestions(fenced)).toHaveLength(1);
  });

  test("drops a correct_choice_index that's out of range", () => {
    const [q] = parseGeneratedQuestions(
      JSON.stringify({ questions: [{ prompt: "Q", expected_answer: "A", choices: ["A", "B"], correct_choice_index: 5 }] }),
    );
    expect(q.correctChoiceIndex).toBeNull();
  });

  test.each([
    ["not JSON", "not valid JSON"],
    ["null", "missing 'questions'"],
    ['{"questions": {}}', "missing 'questions'"],
    ['{"questions": [1]}', "not an object"],
    ['{"questions": [[]]}', "not an object"],
    ['{"questions": [{"prompt": "Q"}]}', "missing prompt/expected_answer"],
  ])("rejects %s", (content, message) => {
    expect(() => parseGeneratedQuestions(content)).toThrow(GenerationParseError);
    expect(() => parseGeneratedQuestions(content)).toThrow(message);
  });
});
