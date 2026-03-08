import 'data_parser.dart';
import 'file_format_exception.dart';

/// Delimiter variants supported by [CsvImportParser].
enum CsvDelimiter {
  /// Comma (`,`) — RFC 4180 default.
  comma,

  /// Horizontal tab (`\t`) — TSV format.
  tab,

  /// Semicolon (`;`) — common in European locales.
  semicolon,
}

/// Parses CSV / TSV data into canonical record maps.
///
/// Features:
/// - Comma, tab, and semicolon delimiter variants.
/// - RFC 4180-style quoted fields (`"value"`) including embedded quotes
///   escaped as `""`.
/// - Comment lines starting with `#` are skipped.
/// - The first non-comment, non-empty line is treated as the header row.
/// - Auto-detection of delimiter when [delimiter] is `null`.
///
/// Throws [FileFormatException] on structural errors (empty content,
/// missing header, row/column count mismatch, invalid quoted field).
class CsvImportParser extends DataParser {
  /// The delimiter to use.  Pass `null` to auto-detect from the header line.
  final CsvDelimiter? delimiter;

  const CsvImportParser({this.delimiter});

  @override
  List<Map<String, dynamic>> parse(String content) {
    final lines = content
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();

    if (lines.isEmpty) {
      throw const FileFormatException('CSV content is empty.');
    }

    final sep = _resolveSeparator(lines.first);
    final headers = _splitLine(lines.first, sep, lineNumber: 1);

    if (headers.isEmpty) {
      throw const FileFormatException('CSV header row is empty.');
    }

    final records = <Map<String, dynamic>>[];
    for (int i = 1; i < lines.length; i++) {
      final lineNumber = i + 1;
      final fields = _splitLine(lines[i], sep, lineNumber: lineNumber);

      if (fields.length != headers.length) {
        throw FileFormatException(
          'Row $lineNumber has ${fields.length} field(s) but header has '
          '${headers.length}.',
          line: lineNumber,
          context:
              lines[i].length > 60 ? '${lines[i].substring(0, 60)}…' : lines[i],
        );
      }

      final record = <String, dynamic>{};
      for (int j = 0; j < headers.length; j++) {
        record[headers[j]] = _coerce(fields[j]);
      }
      records.add(record);
    }
    return records;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  String _resolveSeparator(String headerLine) {
    if (delimiter != null) return _charFor(delimiter!);

    // Auto-detect: pick the delimiter that produces the most fields.
    const candidates = [',', '\t', ';'];
    String best = ',';
    int bestCount = 0;
    for (final c in candidates) {
      final count = c.allMatches(headerLine).length;
      if (count > bestCount) {
        bestCount = count;
        best = c;
      }
    }
    return best;
  }

  static String _charFor(CsvDelimiter d) {
    switch (d) {
      case CsvDelimiter.comma:
        return ',';
      case CsvDelimiter.tab:
        return '\t';
      case CsvDelimiter.semicolon:
        return ';';
    }
  }

  /// Splits [line] on [sep], honouring RFC 4180-style quoted fields.
  static List<String> _splitLine(
    String line,
    String sep, {
    required int lineNumber,
  }) {
    final fields = <String>[];
    final buf = StringBuffer();
    bool inQuotes = false;
    int i = 0;

    while (i < line.length) {
      final ch = line[i];

      if (inQuotes) {
        if (ch == '"') {
          // Peek at next character.
          if (i + 1 < line.length && line[i + 1] == '"') {
            // Escaped quote inside quoted field.
            buf.write('"');
            i += 2;
          } else {
            // Closing quote.
            inQuotes = false;
            i++;
          }
        } else {
          buf.write(ch);
          i++;
        }
      } else {
        if (ch == '"' && buf.isEmpty) {
          inQuotes = true;
          i++;
        } else if (line.startsWith(sep, i)) {
          _flushField(buf, fields);
          i += sep.length;
        } else {
          buf.write(ch);
          i++;
        }
      }
    }

    if (inQuotes) {
      throw FileFormatException(
        'Unterminated quoted field.',
        line: lineNumber,
        context: line.length > 60 ? '${line.substring(0, 60)}…' : line,
      );
    }

    _flushField(buf, fields);
    return fields;
  }

  /// Trims [buf], appends the result to [fields], and clears [buf].
  static void _flushField(StringBuffer buf, List<String> fields) {
    fields.add(buf.toString().trim());
    buf.clear();
  }

  /// Tries to coerce [raw] to a number; falls back to a trimmed string.
  static dynamic _coerce(String raw) {
    final trimmed = raw.trim();
    final asInt = int.tryParse(trimmed);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(trimmed);
    if (asDouble != null) return asDouble;
    return trimmed;
  }
}
