/// Local short-answer grading: normalized text/keyword matching, no AI call.
/// Direct port of the Python desktop app's `core/grading.py` -- same two-step
/// approach (exact match after normalizing, then token-overlap fallback) and
/// the same reasoning for why it's local rather than AI-graded (see
/// Docs/beginners_guide.md section 8 in the Python repo: no per-answer cost,
/// no network latency, works offline).
///
/// Multiple-choice grading needs none of this -- it's a direct equality
/// check against the stored correct Choice, done by the caller.
library;

const overlapThreshold = 0.6;

final _punctuationRe = RegExp(r'[^\w\s]');

// A small, hand-embedded stopword set -- same rationale as the Python app's
// stopwords.py: not worth pulling in a full NLP package for this.
const Set<String> _stopwords = {
  'a', 'an', 'and', 'are', 'as', 'at', 'be', 'by', 'for', 'from', 'has',
  'have', 'in', 'is', 'it', 'its', 'of', 'on', 'or', 'that', 'the', 'this',
  'to', 'was', 'were', 'will', 'with',
};

String normalizeAnswerText(String text) {
  final lowered = text.toLowerCase();
  final stripped = lowered.replaceAll(_punctuationRe, '');
  return stripped.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
}

Set<String> answerTokens(String text) {
  return normalizeAnswerText(text).split(' ').where((w) => w.isNotEmpty && !_stopwords.contains(w)).toSet();
}

/// Exact normalized match, or >=overlapThreshold token overlap against expectedAnswer.
bool gradeShortAnswer(String expectedAnswer, String givenAnswer) {
  final normalizedExpected = normalizeAnswerText(expectedAnswer);
  final normalizedGiven = normalizeAnswerText(givenAnswer);
  if (normalizedExpected == normalizedGiven) return true;

  final expected = answerTokens(expectedAnswer);
  if (expected.isEmpty) return false;

  final given = answerTokens(givenAnswer);
  final overlap = expected.intersection(given).length / expected.length;
  return overlap >= overlapThreshold;
}
