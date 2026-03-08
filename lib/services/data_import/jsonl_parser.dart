import 'dart:convert';

import 'data_parser.dart';
import 'file_format_exception.dart';

/// Parses newline-delimited JSON (JSONL / NDJSON) into canonical record maps.
///
/// Each non-empty, non-comment line must be a self-contained JSON object:
/// ```
/// {"timestamp_ms":0,"accel_x_g":0.02,...}
/// {"timestamp_ms":5,"accel_x_g":0.03,...}
/// ```
/// Lines starting with `#` are treated as comments and skipped.
///
/// Throws [FileFormatException] when:
/// - All lines are empty / comments (no records).
/// - A non-comment line is not valid JSON.
/// - A non-comment line's top-level value is not a JSON object.
class JsonlParser extends DataParser {
  const JsonlParser();

  @override
  List<Map<String, dynamic>> parse(String content) {
    final lines = content.split('\n');
    final records = <Map<String, dynamic>>[];

    int originalLine = 0;
    for (final raw in lines) {
      originalLine++;
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      dynamic decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException catch (e) {
        throw FileFormatException(
          'Invalid JSON on line $originalLine: ${e.message}',
          line: originalLine,
          context: line.length > 60 ? '${line.substring(0, 60)}…' : line,
        );
      }

      if (decoded is! Map) {
        throw FileFormatException(
          'Line $originalLine is not a JSON object (found ${decoded.runtimeType}).',
          line: originalLine,
          context: line.length > 60 ? '${line.substring(0, 60)}…' : line,
        );
      }

      records.add(decoded.cast<String, dynamic>());
    }

    if (records.isEmpty) {
      throw const FileFormatException('JSONL content contains no records.');
    }

    return records;
  }
}
