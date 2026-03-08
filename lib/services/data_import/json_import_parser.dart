import 'dart:convert';

import 'data_parser.dart';
import 'file_format_exception.dart';

/// Parses a JSON array of objects into canonical record maps.
///
/// Expected input shape:
/// ```json
/// [
///   { "timestamp_ms": 0, "accel_x_g": 0.02, ... },
///   { "timestamp_ms": 5, "accel_x_g": 0.03, ... }
/// ]
/// ```
///
/// Throws [FileFormatException] when:
/// - [content] is not valid JSON.
/// - The top-level value is not a JSON array.
/// - Any element is not a JSON object.
class JsonImportParser extends DataParser {
  const JsonImportParser();

  @override
  List<Map<String, dynamic>> parse(String content) {
    if (content.trim().isEmpty) {
      throw const FileFormatException('JSON content is empty.');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException catch (e) {
      throw FileFormatException(
        'Invalid JSON: ${e.message}',
        context: _snippet(content),
      );
    }

    if (decoded is! List) {
      throw FileFormatException(
        'Expected a JSON array at the top level, '
        'but found ${decoded.runtimeType}.',
        context: _snippet(content),
      );
    }

    final records = <Map<String, dynamic>>[];
    for (int i = 0; i < decoded.length; i++) {
      final element = decoded[i];
      if (element is! Map) {
        throw FileFormatException(
          'JSON array element $i is not an object (found ${element.runtimeType}).',
          line: i + 1,
        );
      }
      records.add(element.cast<String, dynamic>());
    }
    return records;
  }

  static String _snippet(String content) {
    final s = content.trim();
    return s.length > 60 ? '${s.substring(0, 60)}…' : s;
  }
}
