/// Plain-text extraction from imported note files. Mirrors the Python
/// desktop app's `core/text_extraction.py`: no OCR, no structure/formatting
/// preservation, each extractor pulls whatever embedded text it can find.
///
/// Dart's package ecosystem for this is thinner than Python's
/// (pypdf/python-docx/python-pptx), which is exactly the risk
/// Docs/flutter_rewrite_plan.md flagged as needing a spike before
/// committing to the full import feature list. Resolution:
/// - .txt/.md: trivial, stdlib file read.
/// - .pdf: `syncfusion_flutter_pdf` -- a real pure-Dart PDF library (free
///   for individuals/small teams under Syncfusion's community license, not
///   fully OSS -- worth knowing, not hidden).
/// - .docx/.pptx: no well-established pure-Dart extractor package exists,
///   so these are hand-rolled here using `archive` (unzip) + `xml` (parse),
///   the same approach `python-docx`/`python-pptx` use under the hood --
///   both .docx and .pptx are just zip archives of XML files.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';

const supportedExtensions = ['.txt', '.md', '.pdf', '.docx', '.pptx'];

class UnsupportedFileTypeError implements Exception {
  final String message;
  const UnsupportedFileTypeError(this.message);
  @override
  String toString() => message;
}

Future<String> _extractTxtOrMd(File file) => file.readAsString();

Future<String> _extractPdf(File file) async {
  final document = PdfDocument(inputBytes: await file.readAsBytes());
  try {
    return PdfTextExtractor(document).extractText();
  } finally {
    document.dispose();
  }
}

/// .docx word/document.xml stores paragraphs as `<w:p>` containing `<w:t>`
/// text runs. Concatenate every `<w:t>` within a paragraph, one paragraph
/// per line.
Future<String> _extractDocx(File file) async {
  final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
  final entry = archive.findFile('word/document.xml');
  if (entry == null) return '';
  final document = XmlDocument.parse(_utf8DecodeArchiveFile(entry));

  final paragraphs = <String>[];
  for (final p in document.findAllElements('w:p')) {
    final text = p.findAllElements('w:t').map((t) => t.innerText).join();
    paragraphs.add(text);
  }
  return paragraphs.join('\n').trim();
}

/// .pptx stores each slide as ppt/slides/slideN.xml, with text in `<a:t>`
/// runs inside `<p:txBody>` shapes. One slide's text per paragraph, slides
/// separated by a blank line (mirrors the Python app's pptx extractor).
Future<String> _extractPptx(File file) async {
  final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
  final slideFiles = archive.files
      .where((f) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(f.name))
      .toList()
    ..sort((a, b) => _slideNumber(a.name).compareTo(_slideNumber(b.name)));

  final slidesText = <String>[];
  for (final entry in slideFiles) {
    final document = XmlDocument.parse(_utf8DecodeArchiveFile(entry));
    final shapesText = document.findAllElements('a:t').map((t) => t.innerText).join();
    slidesText.add(shapesText);
  }
  return slidesText.join('\n\n').trim();
}

int _slideNumber(String path) {
  final match = RegExp(r'slide(\d+)\.xml$').firstMatch(path);
  return int.parse(match!.group(1)!);
}

String _utf8DecodeArchiveFile(ArchiveFile file) {
  final content = file.content as List<int>;
  return utf8.decode(content, allowMalformed: true);
}

Future<String> extractText(String path) async {
  final extension = _extensionOf(path);
  final file = File(path);
  switch (extension) {
    case '.txt':
    case '.md':
      return _extractTxtOrMd(file);
    case '.pdf':
      return _extractPdf(file);
    case '.docx':
      return _extractDocx(file);
    case '.pptx':
      return _extractPptx(file);
    default:
      throw UnsupportedFileTypeError(
        "Unsupported file type '$extension'. Supported: ${supportedExtensions.join(', ')}",
      );
  }
}

String _extensionOf(String path) {
  final dot = path.lastIndexOf('.');
  if (dot == -1) return '';
  return path.substring(dot).toLowerCase();
}
