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
        intervalIndexBefore: row['interval_index_before'] as int,
        intervalIndexAfter: row['interval_index_after'] as int,
        gradingMethod: row['grading_method'] as String,
      );

  Future<ReviewRecord> record(
    int questionId,
    String givenAnswer,
    bool isCorrect,
    int intervalIndexBefore,
    int intervalIndexAfter,
    String gradingMethod, {
    DateTime? askedAt,
  }) async {
    final asked = askedAt ?? utcNow();
    final id = await _db.insert('question_history', {
      'question_id': questionId,
      'asked_at': dtToIso(asked),
      'given_answer': givenAnswer,
      'is_correct': isCorrect ? 1 : 0,
      'interval_index_before': intervalIndexBefore,
      'interval_index_after': intervalIndexAfter,
      'grading_method': gradingMethod,
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
}
