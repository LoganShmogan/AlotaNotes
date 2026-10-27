import 'package:flutter_test/flutter_test.dart';
import 'package:quizapp/core/models.dart';
import 'package:quizapp/core/scheduling.dart';
import 'package:quizapp/storage/problems_repo.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/test_env.dart';

void main() {
  setUpTestEnv();
  late Database db;
  late ProblemsRepo problems;
  final t0 = DateTime.utc(2026, 1, 1);

  setUp(() async {
    db = await openTestDatabase();
    problems = ProblemsRepo(db);
  });

  test('create/get round-trip; a new problem is untried and has no schedule', () async {
    final p = await problems.create(
      'Two Sum',
      difficulty: problemDifficultyEasy,
      url: 'https://leetcode.com/problems/two-sum/',
      platform: 'LeetCode',
      tags: [' Arrays ', 'hash map', 'arrays', ''],
      solution: 'def two_sum(): ...',
      notes: 'Use a dict',
      now: t0,
    );
    expect((p.title, p.difficulty, p.url, p.platform), ('Two Sum', 'easy', 'https://leetcode.com/problems/two-sum/', 'LeetCode'));
    expect(p.tags, ['arrays', 'hash map']); // trimmed, lowercased, de-duplicated
    expect((p.solution, p.notes, p.createdAt, p.updatedAt), ('def two_sum(): ...', 'Use a dict', t0, t0));
    expect((p.card, p.attemptCount, p.status), (null, 0, ProblemStatus.todo));
    expect((await problems.get(p.id)).title, 'Two Sum');
  });

  test('defaults: medium, no link, no tags', () async {
    final p = await problems.create('LRU Cache');
    expect((p.difficulty, p.url, p.platform), (problemDifficultyMedium, null, ''));
    expect(p.tags, isEmpty);
  });

  test('get throws for a missing id', () async {
    expect(() => problems.get(42), throwsStateError);
  });

  test('the schema rejects an unknown difficulty', () async {
    expect(() => problems.create('X', difficulty: 'impossible'), throwsA(isA<DatabaseException>()));
  });

  test('list is alphabetical, case-insensitive', () async {
    for (final title in ['merge intervals', 'Two Sum', 'Binary Search']) {
      await problems.create(title);
    }
    expect((await problems.list()).map((p) => p.title), ['Binary Search', 'merge intervals', 'Two Sum']);
  });

  test('update changes only what is passed; an empty url clears the link', () async {
    final p = await problems.create('Old', url: 'https://x', tags: ['a'], now: t0);
    final later = DateTime.utc(2026, 2, 1);
    var updated = await problems.update(p.id, title: 'New', tags: ['B', 'c'], now: later);
    expect((updated.title, updated.url, updated.updatedAt), ('New', 'https://x', later));
    expect(updated.tags, ['b', 'c']);
    expect(updated.createdAt, t0);

    updated = await problems.update(
      p.id,
      url: '',
      difficulty: problemDifficultyHard,
      platform: 'NeetCode',
      solution: 's',
      notes: 'n',
    );
    expect((updated.url, updated.difficulty, updated.platform, updated.solution, updated.notes), (null, 'hard', 'NeetCode', 's', 'n'));
    expect(updated.updatedAt.isAfter(later), isTrue);
  });

  test('recordAttempt logs the attempt and moves the schedule together', () async {
    final p = await problems.create('Two Sum');
    final after = reviewCard(newCard(t0), ReviewRating.easy, t0);
    final attempt = await problems.recordAttempt(
      p.id,
      solved: true,
      rating: ReviewRating.easy,
      after: after,
      durationMinutes: 14,
      notes: 'Got it first try',
      attemptedAt: t0,
    );
    expect((attempt.problemId, attempt.solved, attempt.rating, attempt.durationMinutes, attempt.notes),
        (p.id, true, ReviewRating.easy, 14, 'Got it first try'));
    expect((attempt.attemptedAt, attempt.nextDueAfter, attempt.stabilityAfter), (t0, after.due, after.stability));

    final reloaded = await problems.get(p.id);
    expect((reloaded.card!.state, reloaded.card!.due), (after.state, after.due));
    expect((reloaded.attemptCount, reloaded.status), (1, ProblemStatus.solved));
  });

  test('status follows the latest attempt; attempts list newest first', () async {
    final p = await problems.create('Hard one');
    var card = newCard(t0);
    for (final (day, solved) in [(1, true), (2, false)]) {
      final at = DateTime.utc(2026, 1, day);
      card = reviewCard(card, solved ? ReviewRating.good : ReviewRating.again, at);
      await problems.recordAttempt(p.id,
          solved: solved, rating: solved ? ReviewRating.good : ReviewRating.again, after: card, attemptedAt: at);
    }
    final reloaded = await problems.get(p.id);
    expect((reloaded.attemptCount, reloaded.lastAttemptSolved, reloaded.status), (2, false, ProblemStatus.attempted));

    final attempts = await problems.listAttempts(p.id);
    expect(attempts.map((a) => a.solved), [false, true]);
    expect(attempts.first.durationMinutes, isNull);
  });

  test('recordAttempt defaults its time to now', () async {
    final p = await problems.create('P');
    final before = DateTime.now().toUtc();
    final attempt = await problems.recordAttempt(p.id, solved: true, rating: ReviewRating.good, after: newCard(before));
    expect(attempt.attemptedAt.isBefore(before), isFalse);
  });

  test('listDue skips untried problems and those not due yet, soonest first', () async {
    Future<void> scheduled(String title, DateTime due) async {
      final p = await problems.create(title);
      await problems.recordAttempt(p.id,
          solved: true, rating: ReviewRating.good, after: SrsCard(state: srsStateReview, due: due, stability: 3, difficulty: 5));
    }

    await problems.create('Untried');
    await scheduled('Later', DateTime.utc(2026, 1, 4));
    await scheduled('Sooner', DateTime.utc(2026, 1, 2));
    await scheduled('Future', DateTime.utc(2026, 3, 1));
    expect((await problems.listDue(DateTime.utc(2026, 1, 5))).map((p) => p.title), ['Sooner', 'Later']);
  });

  test('countAttemptsSince counts attempts at or after the cutoff', () async {
    final p = await problems.create('P');
    for (final day in [1, 2, 3]) {
      await problems.recordAttempt(p.id,
          solved: true, rating: ReviewRating.good, after: newCard(t0), attemptedAt: DateTime.utc(2026, 1, day));
    }
    expect(await problems.countAttemptsSince(DateTime.utc(2026, 1, 2)), 2);
  });

  test('delete removes the problem and its attempts', () async {
    final p = await problems.create('Gone');
    await problems.recordAttempt(p.id, solved: false, rating: ReviewRating.again, after: newCard(t0));
    await problems.delete(p.id);
    expect(await problems.list(), isEmpty);
    expect(await db.query('problem_attempts'), isEmpty);
  });

  test('the schema rejects a negative duration and an out-of-range rating', () async {
    final p = await problems.create('P');
    expect(
      () => problems.recordAttempt(p.id, solved: true, rating: ReviewRating.good, after: newCard(t0), durationMinutes: -1),
      throwsA(isA<DatabaseException>()),
    );
    expect(
      () => db.insert('problem_attempts', {
        'problem_id': p.id,
        'attempted_at': '2026-01-01T00:00:00.000Z',
        'solved': 1,
        'rating': 5,
        'next_due_after': '2026-01-01T00:00:00.000Z',
      }),
      throwsA(isA<DatabaseException>()),
    );
  });
}
