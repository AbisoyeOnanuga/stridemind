import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

/// Utility that converts uploaded file bytes into plain text so the
/// Gemini text API can process them.  Binary formats (PDF, images) are
/// returned as-is (null text) to be sent via the multimodal API instead.
abstract final class PlanFileReader {
  /// Returns plain-text content for text-based formats, or null for
  /// binary formats that must go via Gemini's multimodal/inline-data API.
  static String? extractText(Uint8List bytes, String extension) {
    switch (extension.toLowerCase()) {
      case 'txt':
      case 'csv':
        return _decodeText(bytes);
      case 'xlsx':
        return _extractXlsx(bytes);
      case 'docx':
        return _extractDocx(bytes);
      default:
        return null; // PDF / images handled as multimodal
    }
  }

  /// Maps a file extension to its MIME type for Gemini multimodal calls.
  static String? mimeType(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return null;
    }
  }

  static bool isSupported(String extension) {
    const supported = {
      'txt', 'csv', 'xlsx', 'docx', 'pdf',
      'jpg', 'jpeg', 'png', 'webp', 'heic',
    };
    return supported.contains(extension.toLowerCase());
  }

  // ---------------------------------------------------------------------------

  static String _decodeText(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  static String _extractXlsx(Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    final buffer = StringBuffer();
    for (final sheetName in workbook.tables.keys) {
      final sheet = workbook.tables[sheetName]!;
      buffer.writeln('--- Sheet: $sheetName ---');
      for (final row in sheet.rows) {
        final cells = row.map((c) => c?.value?.toString() ?? '').toList();
        if (cells.any((c) => c.isNotEmpty)) {
          buffer.writeln(cells.join('\t'));
        }
      }
    }
    return buffer.toString();
  }

  static String _extractDocx(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final docXml = archive.findFile('word/document.xml');
      if (docXml == null) {
        throw const FormatException(
            'Could not find document.xml inside the .docx file.');
      }
      final xml = utf8.decode(docXml.content as List<int>);
      return xml
          .replaceAll(RegExp(r'<w:p[ >]'), ' <w:p ')
          .replaceAll(RegExp(r'<w:br[ /]'), '\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim();
    } catch (e) {
      throw FormatException('Failed to read .docx file: $e');
    }
  }
}
