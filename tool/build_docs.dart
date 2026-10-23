// Renders README.md and Docs/*.md into Save Point branded PDFs in
// Docs/pdf/, styled like the rest of Save Point's business documents
// (brand colours and fonts from "02 Brand and Marketing/Colour codes +
// fonts"):
//
//   dart run tool/build_docs.dart
//
// The Markdown files stay the source of truth; rerun this after editing
// them. Each file becomes an HTML page in build/docs/ and is printed to PDF
// with headless Chrome, the same way the other Save Point PDFs were made.
// Fonts come from Google Fonts, falling back to locally installed copies of
// Chakra Petch and Figtree when offline.
import 'dart:io';

import 'package:markdown/markdown.dart' as md;

const _preparedFor = 'Logan Young, Save Point Limited';
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

Future<void> main() async {
  final chrome = _findChrome();
  if (chrome == null) {
    stderr.writeln('Google Chrome or Chromium is needed to print PDFs; none found on PATH.');
    exit(2);
  }

  final sources = [
    File('README.md'),
    ...Directory('Docs').listSync().whereType<File>().where((f) => f.path.endsWith('.md')).toList()
      ..sort((a, b) => a.path.compareTo(b.path)),
  ];
  final htmlDir = Directory('build/docs')..createSync(recursive: true);
  final pdfDir = Directory('Docs/pdf')..createSync(recursive: true);
  final logo = File('Docs/assets/save-point-logo.svg').absolute.uri;
  final now = DateTime.now();
  final date = '${now.day} ${_months[now.month - 1]} ${now.year}';

  for (final source in sources) {
    final name = source.uri.pathSegments.last.replaceAll('.md', '');
    final (title, body) = _render(source.readAsStringSync());
    final html = File('${htmlDir.path}/$name.html')..writeAsStringSync(_page(title, body, logo, date));
    final pdf = File('${pdfDir.path}/${name == 'README' ? 'overview' : name}.pdf');

    final result = await Process.run(chrome, [
      '--headless',
      '--disable-gpu',
      '--no-pdf-header-footer',
      '--virtual-time-budget=10000',
      '--print-to-pdf=${pdf.absolute.path}',
      html.absolute.uri.toString(),
    ]);
    if (result.exitCode != 0 || !pdf.existsSync()) {
      stderr.writeln('Failed to print ${source.path}:\n${result.stderr}');
      exit(1);
    }
    stdout.writeln('${source.path} -> ${pdf.path}');
  }
}

String? _findChrome() {
  for (final name in ['google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser']) {
    final which = Process.runSync('which', [name]);
    if (which.exitCode == 0) return (which.stdout as String).trim();
  }
  return null;
}

/// Returns the document's title (its first `#` heading, removed from the
/// body since the page header shows it) and the rest as HTML. A paragraph
/// straight after the title becomes the header's lede.
(String, String) _render(String markdown) {
  final lines = markdown.split('\n');
  final titleIndex = lines.indexWhere((l) => l.startsWith('# '));
  final title = titleIndex == -1 ? 'Untitled' : lines[titleIndex].substring(2).trim();
  if (titleIndex != -1) lines.removeAt(titleIndex);

  var html = md.markdownToHtml(lines.join('\n'), extensionSet: md.ExtensionSet.gitHubFlavored).trim();
  if (html.startsWith('<p>')) {
    final end = html.indexOf('</p>') + 4;
    html = '<p class="lede">${html.substring(3, end)}\n<hr class="rule">${html.substring(end)}';
  }
  return (title, html);
}

String _escape(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('"', '&quot;');

String _page(String title, String body, Uri logo, String date) => '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>${_escape(title)} | Save Point Limited</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Chakra+Petch:wght@700&family=Figtree:wght@400;700&family=IBM+Plex+Mono:wght@400&display=swap" rel="stylesheet">
<style>
  :root {
    --purple: #b791c2;
    --yellow: #eecc67;
    --blue: #699fd5;
    --green: #82c889;
    --ink: #111;
    --muted: #555;
    --line: #d8d8d8;
    --tint: #f6f1f8;
    --code-bg: #f1f1f1;
  }
  @page {
    size: A4;
    margin: 18mm 18mm 20mm;
    @bottom-left {
      content: "Save Point Limited · savepoint.co.nz";
      font: 8pt Figtree, sans-serif;
      color: var(--muted);
    }
    @bottom-right {
      content: "${_escape(title).replaceAll('"', '\\"')} · " counter(page) " of " counter(pages);
      font: 8pt Figtree, sans-serif;
      color: var(--muted);
    }
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    background: #fff;
    color: var(--ink);
    font: 10.5pt/1.55 Figtree, sans-serif;
  }
  h1, h2, h3, h4 { font-family: "Chakra Petch", sans-serif; font-weight: 700; line-height: 1.2; }
  .logo { height: 34px; display: block; }
  .swatches { display: flex; gap: 6px; margin: 26px 0 12px; }
  .swatches span { width: 13px; height: 13px; }
  h1 { font-size: 26pt; margin: 0 0 6px; }
  .byline { color: var(--muted); font-size: 9pt; margin: 0 0 18px; }
  .lede { font-size: 12pt; margin: 0 0 18px; }
  hr { border: 0; border-top: 1px solid var(--ink); margin: 18px 0; }
  h2 {
    font-size: 15pt;
    margin: 30px 0 10px;
    padding-top: 16px;
    border-top: 1px solid var(--ink);
    break-after: avoid;
  }
  .rule + h2, hr + h2 { border-top: 0; padding-top: 0; }
  h2::before {
    content: "";
    display: inline-block;
    width: 11px;
    height: 11px;
    margin-right: 9px;
    background: var(--purple);
  }
  h3 { font-size: 12pt; margin: 20px 0 6px; break-after: avoid; }
  h4 { font-size: 10.5pt; margin: 16px 0 4px; break-after: avoid; }
  p, ul, ol { margin: 0 0 10px; }
  ul, ol { padding-left: 20px; }
  li { margin: 2px 0; }
  li::marker { color: var(--purple); }
  a { color: var(--ink); text-decoration-color: var(--purple); }
  code {
    font: 9pt "IBM Plex Mono", "DejaVu Sans Mono", monospace;
    background: var(--code-bg);
    padding: 1px 4px;
    border-radius: 2px;
  }
  pre {
    background: var(--code-bg);
    padding: 10px 12px;
    margin: 0 0 12px;
    white-space: pre-wrap;
  }
  pre code { padding: 0; background: none; font-size: 8.5pt; line-height: 1.45; }
  blockquote {
    margin: 0 0 12px;
    padding: 10px 14px;
    background: var(--tint);
    border-left: 4px solid var(--purple);
  }
  blockquote p:last-child { margin-bottom: 0; }
  table { width: 100%; border-collapse: collapse; margin: 0 0 14px; font-size: 9.5pt; }
  thead th { background: var(--ink); color: #fff; text-align: left; font-weight: 700; }
  th, td { padding: 6px 8px; vertical-align: top; }
  tbody td { border-bottom: 1px solid var(--line); }
  tr { break-inside: avoid; }
</style>
</head>
<body>
<header>
  <img class="logo" src="$logo" alt="Save Point">
  <div class="swatches">
    <span style="background:var(--purple)"></span><span style="background:var(--yellow)"></span><span style="background:var(--blue)"></span><span style="background:var(--green)"></span>
  </div>
  <h1>${_escape(title)}</h1>
  <p class="byline">AlotaNotes Quiz App · Prepared for $_preparedFor · $date</p>
</header>
$body
</body>
</html>
''';
