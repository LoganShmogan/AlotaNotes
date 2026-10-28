import { describe, expect, test } from "vitest";
import { answerTokens, gradeShortAnswer, normalizeAnswerText } from "../convex/grading";

// Mirrors lib/core/grading.dart: exact match, then 60% keyword overlap.
describe("grading", () => {
  test("normalises case, punctuation and spacing", () => {
    expect(normalizeAnswerText("  The  Mitochondria! ")).toBe("the mitochondria");
  });

  test("drops stopwords from tokens", () => {
    expect([...answerTokens("The capital of France")]).toEqual(["capital", "france"]);
  });

  test.each([
    ["Paris", "paris", true],
    ["Paris", "Paris!", true],
    ["the powerhouse of the cell", "powerhouse cell", true],
    ["mitochondria produce energy for the cell", "mitochondria produce energy", true],
    ["mitochondria produce energy for the cell", "mitochondria", false],
    ["Paris", "London", false],
    ["the of", "anything", false],
  ])("%s / %s -> %s", (expected, given, result) => {
    expect(gradeShortAnswer(expected, given)).toBe(result);
  });
});
