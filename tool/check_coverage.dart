// Fails unless every line in lib/ is covered. Run after
// `flutter test --coverage`:
//
//   dart run tool/check_coverage.dart [min-percent]
//
// Reads coverage/lcov.info directly (no lcov/genhtml install needed) and
// also fails if a lib/ file never appears in it at all, i.e. no test even
// imports it -- the case a plain percentage silently hides.
import 'dart:io';

void main(List<String> args) {
  final minPercent = args.isEmpty ? 100.0 : double.parse(args.first);
  final lcov = File('coverage/lcov.info');
  if (!lcov.existsSync()) {
    stderr.writeln('coverage/lcov.info not found; run `flutter test --coverage` first.');
    exit(2);
  }

  final missedLines = <String, List<int>>{};
  final lineCounts = <String, int>{};
  String? current;
  for (final line in lcov.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      current = line.substring(3);
      missedLines[current] = [];
      lineCounts[current] = 0;
    } else if (line.startsWith('DA:') && current != null) {
      final [number, hits, ...] = line.substring(3).split(',');
      lineCounts[current] = lineCounts[current]! + 1;
      if (int.parse(hits) == 0) missedLines[current]!.add(int.parse(number));
    }
  }

  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => p.endsWith('.dart'))
      .toList()
    ..sort();
  final neverLoaded = libFiles.where((p) => !lineCounts.containsKey(p)).toList();

  final total = lineCounts.values.fold(0, (a, b) => a + b);
  final missed = missedLines.values.fold(0, (a, b) => a + b.length);
  final percent = total == 0 ? 0.0 : 100 * (total - missed) / total;

  for (final entry in missedLines.entries.where((e) => e.value.isNotEmpty)) {
    stdout.writeln('${entry.key}: uncovered lines ${entry.value.join(', ')}');
  }
  for (final path in neverLoaded) {
    stdout.writeln('$path: never loaded by any test');
  }
  stdout.writeln('Line coverage: ${total - missed}/$total (${percent.toStringAsFixed(1)}%)');

  if (percent < minPercent || neverLoaded.isNotEmpty) {
    stderr.writeln('Below the required ${minPercent.toStringAsFixed(1)}%.');
    exit(1);
  }
}
