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

import 'package:share_plus/share_plus.dart';
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

  /// Builds the export as an in-memory file, ready to hand to a share
  /// sheet (which on web falls back to a browser download).
  ///
  /// The name is returned separately because `XFile.fromData` only keeps it
  /// on web; elsewhere the share sheet needs it via `fileNameOverrides`, or
  /// the file goes out under a random UUID name.
  Future<({XFile file, String name})> exportFile() async {
    final data = await buildExport();
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final name = 'quizapp-export-$timestamp.json';
    final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(data));
    return (file: XFile.fromData(bytes, mimeType: 'application/json', name: name), name: name);
  }
}
