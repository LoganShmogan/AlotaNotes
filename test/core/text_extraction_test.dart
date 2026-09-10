// Fixtures for .docx/.pptx are built by hand here (a minimal valid zip +
// XML), not checked in as binaries -- same reasoning as the Python desktop
// app's tests/fixtures/pdf_builder.py: no extra "write this format"
// dependency, and it keeps the fixture's exact shape visible in the test
// itself. .pdf isn't covered here (Syncfusion's PdfDocument needs a fuller
// PDF structure than is worth hand-building); the .pdf branch is exercised
// manually instead -- a known, deliberate gap in this file's coverage.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quizapp/core/text_extraction.dart';

Future<Directory> _tempDir() => Directory.systemTemp.createTemp('text_extraction_test_');

void _writeZip(String path, Map<String, String> filesByName) {
  final archive = Archive();
  for (final entry in filesByName.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  final zipBytes = ZipEncoder().encode(archive);
  File(path).writeAsBytesSync(zipBytes!);
}

const _docxDocumentXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>First paragraph.</w:t></w:r></w:p>
    <w:p><w:r><w:t>Second </w:t></w:r><w:r><w:t>paragraph.</w:t></w:r></w:p>
  </w:body>
</w:document>
''';

String _pptxSlideXml(String text) => '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
       xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:sp><p:txBody><a:p><a:r><a:t>$text</a:t></a:r></a:p></p:txBody></p:sp>
    </p:spTree>
  </p:cSld>
</p:sld>
''';

void main() {
  test('.txt is read as-is', () async {
    final dir = await _tempDir();
    final path = p.join(dir.path, 'note.txt');
    await File(path).writeAsString('Plain text content.');

    expect(await extractText(path), 'Plain text content.');
  });

  test('.md is read as-is', () async {
    final dir = await _tempDir();
    final path = p.join(dir.path, 'note.md');
    await File(path).writeAsString('# Heading\n\nBody.');

    expect(await extractText(path), '# Heading\n\nBody.');
  });

  test('.docx extracts paragraph text, joining runs within a paragraph', () async {
    final dir = await _tempDir();
    final path = p.join(dir.path, 'note.docx');
    _writeZip(path, {'word/document.xml': _docxDocumentXml});

    final text = await extractText(path);
    expect(text, 'First paragraph.\nSecond paragraph.');
  });

  test('.pptx extracts text per slide, slides in numeric order', () async {
    final dir = await _tempDir();
    final path = p.join(dir.path, 'deck.pptx');
    _writeZip(path, {
      'ppt/slides/slide2.xml': _pptxSlideXml('Second slide'),
      'ppt/slides/slide1.xml': _pptxSlideXml('First slide'),
      'ppt/slides/slide10.xml': _pptxSlideXml('Tenth slide'), // numeric, not lexical, sort
    });

    final text = await extractText(path);
    expect(text, 'First slide\n\nSecond slide\n\nTenth slide');
  });

  test('unsupported extension throws UnsupportedFileTypeError', () async {
    final dir = await _tempDir();
    final path = p.join(dir.path, 'note.exe');
    await File(path).writeAsBytes([0, 1, 2]);

    await expectLater(extractText(path), throwsA(isA<UnsupportedFileTypeError>()));
  });
}
