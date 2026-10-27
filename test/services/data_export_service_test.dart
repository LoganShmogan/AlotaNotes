import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizapp/core/models.dart';
import 'package:quizapp/core/scheduling.dart';
import 'package:quizapp/services/data_export_service.dart';
import 'package:quizapp/storage/db.dart';
import 'package:quizapp/storage/folders_repo.dart';
import 'package:quizapp/storage/notes_repo.dart';
import 'package:quizapp/storage/problems_repo.dart';
import 'package:quizapp/storage/questions_repo.dart';
import 'package:quizapp/storage/reviews_repo.dart';

import '../helpers/test_env.dart';

void main() {
  setUpTestEnv();

  test('buildExport on an empty database has every table, empty', () async {
    final export = await DataExportService(await openTestDatabase()).buildExport();
    expect(export['schema_version'], schemaVersion);
    expect(DateTime.parse(export['exported_at'] as String).isUtc, isTrue);
    for (final table in [
      'folders',
      'notes',
      'questions',
      'question_choices',
      'question_history',
      'problems',
      'problem_attempts',
    ]) {
      expect(export[table], isEmpty, reason: table);
    }
  });

  test('buildExport includes the raw rows of every table', () async {
    final db = await openTestDatabase();
    final folder = await FoldersRepo(db).create('Physics');
    final note = await NotesRepo(db).create(folder.id, 'Optics', 'Light bends.', sourceFilename: 'optics.md');
    final question = await QuestionsRepo(db)
        .create(note.id, questionTypeMultipleChoice, 'Bends?', 'Yes', choices: [('Yes', true), ('No', false)]);
    await ReviewsRepo(db).record(question.id, 'Yes', true, ReviewRating.good, gradingMethodMcqExact, question.card);
    final problem = await ProblemsRepo(db).create('Two Sum', difficulty: problemDifficultyEasy);
    await ProblemsRepo(db)
        .recordAttempt(problem.id, solved: true, rating: ReviewRating.good, after: newCard(utcNow()), durationMinutes: 12);

    final export = await DataExportService(db).buildExport();
    expect((export['folders'] as List).single['name'], 'Physics');
    expect((export['notes'] as List).single['source_filename'], 'optics.md');
    expect((export['questions'] as List).single['prompt'], 'Bends?');
    expect(export['question_choices'] as List, hasLength(2));
    expect((export['question_history'] as List).single['given_answer'], 'Yes');
    expect((export['problems'] as List).single['title'], 'Two Sum');
    expect((export['problem_attempts'] as List).single['duration_minutes'], 12);
  });

  test('exportFile is a pretty-printed JSON file with a filesystem-safe timestamped name', () async {
    final db = await openTestDatabase();
    await FoldersRepo(db).create('Physics');

    final export = await DataExportService(db).exportFile();
    expect(export.file.mimeType, 'application/json');
    expect(export.name, matches(RegExp(r'^quizapp-export-\d{4}-\d{2}-\d{2}T[\d-]+Z\.json$')));

    final text = utf8.decode(await export.file.readAsBytes());
    expect(text, contains('\n  "folders": ['));
    final decoded = jsonDecode(text) as Map<String, dynamic>;
    expect((decoded['folders'] as List).single['name'], 'Physics');
  });
}
