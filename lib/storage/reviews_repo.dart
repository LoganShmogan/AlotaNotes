import 'package:sqflite/sqflite.dart';

import '../core/models.dart';
import 'db.dart';

/// Append-only: this repo has no update()/delete() -- see db.dart's
/// question_history table comment.
class ReviewsRepo {
  final Database _db;
  const ReviewsRepo(this._db);

  ReviewRecord _rowToReview(Map<String, Object?> row) => ReviewRecord(
        id: row['id'] as int,
        questionId: row['question_id'] as int,
        askedAt: isoToDt(row['asked_at'] as String),
        givenAnswer: row['given_answer'] as String,
        isCorrect: (row['is_correct'] as int) == 1,
        rating: ReviewRating.fromValue(row['rating'] as int),
        gradingMethod: row['grading_method'] as String,
        nextDueAfter: isoToDt(row['next_due_after'] as String),
        stabilityAfter: (row['stability_after'] as num?)?.toDouble(),
      );

  /// [after] is the question's card once this review has been applied.
  Future<ReviewRecord> record(
    int questionId,
    String givenAnswer,
    bool isCorrect,
    ReviewRating rating,
    String gradingMethod,
    SrsCard after, {
    DateTime? askedAt,
  }) async {
    final asked = askedAt ?? utcNow();
    final id = await _db.insert('question_history', {
      'question_id': questionId,
      'asked_at': dtToIso(asked),
      'given_answer': givenAnswer,
      'is_correct': isCorrect ? 1 : 0,
      'rating': rating.value,
      'grading_method': gradingMethod,
      'next_due_after': dtToIso(after.due),
      'stability_after': after.stability,
    });
    final rows = await _db.query('question_history', where: 'id = ?', whereArgs: [id]);
    return _rowToReview(rows.first);
  }

  Future<List<ReviewRecord>> listForQuestion(int questionId) async {
    final rows = await _db.query(
      'question_history',
      where: 'question_id = ?',
      whereArgs: [questionId],
      orderBy: 'asked_at',
    );
    return rows.map(_rowToReview).toList();
  }

  /// How many answers were given at or after [since].
  Future<int> countSince(DateTime since) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM question_history WHERE asked_at >= ?',
      [dtToIso(since)],
    );
    return rows.first['n'] as int;
  }
}
