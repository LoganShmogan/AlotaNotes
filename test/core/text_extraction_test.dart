// Fixtures for .docx/.pptx are built by hand here (a minimal valid zip +
// XML), not checked in as binaries -- same reasoning as the Python desktop
// app's tests/fixtures/pdf_builder.py: no extra "write this format"
// dependency, and it keeps the fixture's exact shape visible in the test
// itself. The .pdf fixture is generated with Syncfusion's own PDF writer
// (the same package the app reads with), since a valid PDF is too fiddly to
// hand-build.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizapp/core/text_extraction.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

List<int> _zip(Map<String, String> filesByName) {
  final archive = Archive();
  for (final entry in filesByName.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive)!;
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

List<int> _pdf(List<String> pageTexts) {
  final document = PdfDocument();
  for (final text in pageTexts) {
    document.pages.add().graphics.drawString(text, PdfStandardFont(PdfFontFamily.helvetica, 12));
  }
  final bytes = document.saveSync();
  document.dispose();
  return bytes;
}

void main() {
  test('.txt is read as-is', () {
    expect(extractText('note.txt', utf8.encode('Plain text content.')), 'Plain text content.');
  });

  test('.md is read as-is', () {
    expect(extractText('note.md', utf8.encode('# Heading\n\nBody.')), '# Heading\n\nBody.');
  });

  test('.docx extracts paragraph text, joining runs within a paragraph', () {
    final text = extractText('note.docx', _zip({'word/document.xml': _docxDocumentXml}));
    expect(text, 'First paragraph.\nSecond paragraph.');
  });

  test('.pptx extracts text per slide, slides in numeric order', () {
    final text = extractText('deck.pptx', _zip({
      'ppt/slides/slide2.xml': _pptxSlideXml('Second slide'),
      'ppt/slides/slide1.xml': _pptxSlideXml('First slide'),
      'ppt/slides/slide10.xml': _pptxSlideXml('Tenth slide'), // numeric, not lexical, sort
    }));
    expect(text, 'First slide\n\nSecond slide\n\nTenth slide');
  });

  test('unsupported extension throws UnsupportedFileTypeError', () {
    expect(() => extractText('note.exe', [0, 1, 2]), throwsA(isA<UnsupportedFileTypeError>()));
  });

  test('.pdf extracts embedded text from every page', () {
    final text = extractText('lecture.pdf', _pdf(['Page one text', 'Page two text']));
    expect(text, contains('Page one text'));
    expect(text, contains('Page two text'));
  });

  test('extension matching is case-insensitive', () {
    expect(extractText('NOTE.TXT', utf8.encode('upper')), 'upper');
  });

  test('.txt tolerates invalid UTF-8 instead of throwing', () {
    expect(extractText('note.txt', [0x68, 0x69, 0xff]), 'hi\uFFFD');
  });

  test('.docx without word/document.xml yields empty text', () {
    expect(extractText('note.docx', _zip({'other.xml': '<x/>'})), '');
  });

  test('.pptx with no slides yields empty text', () {
    expect(extractText('deck.pptx', _zip({'ppt/presentation.xml': '<x/>'})), '');
  });

  test('a file name with no extension is unsupported, with a helpful message', () {
    expect(
      () => extractText('README', []),
      throwsA(isA<UnsupportedFileTypeError>().having(
        (e) => e.toString(),
        'message',
        "Unsupported file type ''. Supported: .txt, .md, .pdf, .docx, .pptx",
      )),
    );
  });
}
