// Short-answer grading, a port of the Flutter app's lib/core/grading.dart:
// an exact match after normalising, or enough keyword overlap. Local and
// free, no AI call. Multiple choice is just "is the chosen one correct".

export const OVERLAP_THRESHOLD = 0.6;

const STOPWORDS = new Set([
  "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "has", "have", "in", "is", "it", "its", "of",
  "on", "or", "that", "the", "this", "to", "was", "were", "will", "with",
]);

// Dart's \w is ASCII letters, digits and underscore.
export function normalizeAnswerText(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^\w\s]/g, "")
    .split(/\s+/)
    .filter((w) => w.length > 0)
    .join(" ");
}

export function answerTokens(text: string): Set<string> {
  return new Set(normalizeAnswerText(text).split(" ").filter((w) => w.length > 0 && !STOPWORDS.has(w)));
}

export function gradeShortAnswer(expected: string, given: string): boolean {
  if (normalizeAnswerText(expected) === normalizeAnswerText(given)) return true;
  const want = answerTokens(expected);
  if (want.size === 0) return false;
  const got = answerTokens(given);
  let overlap = 0;
  for (const token of want) if (got.has(token)) overlap++;
  return overlap / want.size >= OVERLAP_THRESHOLD;
}
