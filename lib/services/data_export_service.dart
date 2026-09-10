/// Full data export -- every folder, note, question, choice, and review
/// history row, as one portable JSON file. This is a top-level requirement
/// per Docs/flutter_rewrite_plan.md ("get all my data out should always
/// work with no friction"), not an afterthought.
///
/// Exports raw table rows directly (not through the repos' typed models),
/// deliberately: an export is a snapshot of what's really in the database,
/// and going straight to the rows means adding a new column later doesn't
/// silently drop it from exports just because a model class hasn't been
/// updated to carry it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DataExportService {
  final Database db;
  const DataExportService(this.db);

  Future<Map<String, dynamic>> buildExport() async {
    final tables = ['folders', 'notes', 'questions', 'question_choices', 'question_history'];
    final data = <String, dynamic>{
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'schema_version': 1,
    };
    for (final table in tables) {
      data[table] = await db.query(table);
    }
    return data;
  }

  /// Writes the export to a temp file and returns its path, ready to hand
  /// to a share sheet or file picker save dialog.
  Future<File> exportToTempFile() async {
    final data = await buildExport();
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final file = File(p.join(directory.path, 'quizapp-export-$timestamp.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return file;
  }
}
