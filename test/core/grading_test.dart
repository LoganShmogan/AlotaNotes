import 'package:flutter_test/flutter_test.dart';
import 'package:quizapp/core/grading.dart';

void main() {
  test('exact match after normalizing case/punctuation/whitespace', () {
    expect(gradeShortAnswer('Paris', 'paris'), isTrue);
    expect(gradeShortAnswer('Paris.', 'paris'), isTrue);
    expect(gradeShortAnswer('  Paris  ', 'paris'), isTrue);
  });

  test('token-overlap fallback forgives minor wording differences', () {
    expect(gradeShortAnswer('the mitochondria is the powerhouse of the cell', 'mitochondria powerhouse cell'),
        isTrue);
  });

  test('rejects answers below the overlap threshold', () {
    expect(gradeShortAnswer('mitochondria', 'nucleus'), isFalse);
  });

  test('empty expected answer never matches', () {
    expect(gradeShortAnswer('', 'anything'), isFalse);
  });

  test('normalizeAnswerText strips punctuation and collapses whitespace', () {
    expect(normalizeAnswerText("Don't  stop!"), "dont stop");
  });

  test('answerTokens excludes stopwords', () {
    expect(answerTokens('the cat and the hat'), {'cat', 'hat'});
  });
}
