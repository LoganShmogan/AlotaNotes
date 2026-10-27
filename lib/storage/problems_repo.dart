import 'package:sqflite/sqflite.dart';

import '../core/models.dart';
import 'db.dart';

/// The problem tracker: LeetCode-style practice problems and the log of
/// every attempt at them. Scheduling itself is computed by the caller
/// (core/scheduling.dart), same split as QuestionsRepo/ReviewsRepo; this
/// repo only stores the result.
class ProblemsRepo {
  final Database _db;
  const ProblemsRepo(this._db);

  // Attempt count and whether the latest attempt was solved, computed in
  // SQL so a list never needs one query per problem.
  static const _select = '''
    SELECT p.*,
      (SELECT COUNT(*) FROM problem_attempts a WHERE a.problem_id = p.id) AS attempt_count,
      (SELECT a.solved FROM problem_attempts a WHERE a.problem_id = p.id
        ORDER BY a.attempted_at DESC, a.id DESC LIMIT 1) AS last_solved
    FROM problems p
  ''';

  /// Tags are stored as one comma-separated, lowercased string.
  static List<String> normalizeTags(Iterable<String> tags) {
    final seen = <String>{};
    for (final tag in tags) {
      final t = tag.trim().toLowerCase();
      if (t.isNotEmpty) seen.add(t);
    }
    return seen.toList();
  }

  Problem _rowToProblem(Map<String, Object?> row) {
    final tags = row['tags'] as String;
    return Problem(
      id: row['id'] as int,
      title: row['title'] as String,
      url: row['url'] as String?,
      platform: row['platform'] as String,
      difficulty: row['difficulty'] as String,
      tags: tags.isEmpty ? const [] : tags.split(','),
      solution: row['solution'] as String,
      notes: row['notes'] as String,
      card: srsCardFromRow(row),
      attemptCount: row['attempt_count'] as int,
      lastAttemptSolved: row['last_solved'] == 1,
      createdAt: isoToDt(row['created_at'] as String),
      updatedAt: isoToDt(row['updated_at'] as String),
    );
  }

  ProblemAttempt _rowToAttempt(Map<String, Object?> row) => ProblemAttempt(
        id: row['id'] as int,
        problemId: row['problem_id'] as int,
        attemptedAt: isoToDt(row['attempted_at'] as String),
        solved: row['solved'] == 1,
        durationMinutes: row['duration_minutes'] as int?,
        rating: ReviewRating.fromValue(row['rating'] as int),
        notes: row['notes'] as String,
        nextDueAfter: isoToDt(row['next_due_after'] as String),
        stabilityAfter: (row['stability_after'] as num?)?.toDouble(),
      );

  Future<Problem> create(
    String title, {
    String difficulty = problemDifficultyMedium,
    String? url,
    String platform = '',
    List<String> tags = const [],
    String solution = '',
    String notes = '',
    DateTime? now,
  }) async {
    final createdAt = dtToIso(now ?? utcNow());
    final id = await _db.insert('problems', {
      'title': title,
      'url': url,
      'platform': platform,
      'difficulty': difficulty,
      'tags': normalizeTags(tags).join(','),
      'solution': solution,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': createdAt,
    });
    return get(id);
  }

  Future<Problem> get(int id) async {
    final rows = await _db.rawQuery('$_select WHERE p.id = ?', [id]);
    if (rows.isEmpty) {
      throw StateError('No problem with id $id');
    }
    return _rowToProblem(rows.first);
  }

  Future<List<Problem>> list() async {
    final rows = await _db.rawQuery('$_select ORDER BY p.title COLLATE NOCASE, p.id');
    return rows.map(_rowToProblem).toList();
  }

  /// Problems whose re-solve is due, soonest-overdue first.
  Future<List<Problem>> listDue(DateTime now) async {
    final rows = await _db.rawQuery(
      '$_select WHERE p.next_due_at IS NOT NULL AND p.next_due_at <= ? ORDER BY p.next_due_at',
      [dtToIso(now)],
    );
    return rows.map(_rowToProblem).toList();
  }

  /// Only the fields passed change. `url: ''` clears the link.
  Future<Problem> update(
    int id, {
    String? title,
    String? difficulty,
    String? url,
    String? platform,
    List<String>? tags,
    String? solution,
    String? notes,
    DateTime? now,
  }) async {
    await _db.update(
      'problems',
      {
        'title': ?title,
        'difficulty': ?difficulty,
        if (url != null) 'url': url.isEmpty ? null : url,
        'platform': ?platform,
        if (tags != null) 'tags': normalizeTags(tags).join(','),
        'solution': ?solution,
        'notes': ?notes,
        'updated_at': dtToIso(now ?? utcNow()),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return get(id);
  }

  Future<void> delete(int id) async {
    await _db.delete('problems', where: 'id = ?', whereArgs: [id]);
  }

  /// Logs one attempt and moves the problem's schedule to [after] (the
  /// card once this attempt's rating has been applied), atomically.
  Future<ProblemAttempt> recordAttempt(
    int problemId, {
    required bool solved,
    required ReviewRating rating,
    required SrsCard after,
    int? durationMinutes,
    String notes = '',
    DateTime? attemptedAt,
  }) async {
    final at = attemptedAt ?? utcNow();
    final id = await _db.transaction((txn) async {
      await txn.update('problems', srsCardToRow(after), where: 'id = ?', whereArgs: [problemId]);
      return txn.insert('problem_attempts', {
        'problem_id': problemId,
        'attempted_at': dtToIso(at),
        'solved': solved ? 1 : 0,
        'duration_minutes': durationMinutes,
        'rating': rating.value,
        'notes': notes,
        'next_due_after': dtToIso(after.due),
        'stability_after': after.stability,
      });
    });
    final rows = await _db.query('problem_attempts', where: 'id = ?', whereArgs: [id]);
    return _rowToAttempt(rows.first);
  }

  /// Newest first.
  Future<List<ProblemAttempt>> listAttempts(int problemId) async {
    final rows = await _db.query(
      'problem_attempts',
      where: 'problem_id = ?',
      whereArgs: [problemId],
      orderBy: 'attempted_at DESC, id DESC',
    );
    return rows.map(_rowToAttempt).toList();
  }

  Future<int> countAttemptsSince(DateTime since) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM problem_attempts WHERE attempted_at >= ?',
      [dtToIso(since)],
    );
    return rows.first['n'] as int;
  }
}
