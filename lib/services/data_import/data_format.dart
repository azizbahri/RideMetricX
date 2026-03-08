import 'file_format_exception.dart';

/// Recognised data formats for import.
enum DataFormat {
  /// Comma / tab / semicolon-separated values.
  csv,

  /// JSON array of objects (`[{...}, ...]`).
  json,

  /// Newline-delimited JSON (one object per line).
  jsonl,

  /// Fixed-width binary, HDF5, or other binary container (extension point).
  binary,
}

/// Detects the [DataFormat] of an import file.
///
/// Detection order:
/// 1. File extension (case-insensitive).
/// 2. Content-based sniff of the first non-whitespace bytes when the
///    extension is absent or not conclusive.
///
/// Throws [FileFormatException] when the format cannot be determined.
class DataFormatDetector {
  const DataFormatDetector._();

  /// Returns the [DataFormat] for [fileName].
  ///
  /// [bytes] is the raw (possibly compressed) file content and is used as
  /// a fallback when the extension is not conclusive.
  ///
  /// Throws [FileFormatException] when the format cannot be determined.
  static DataFormat detect(String fileName, {List<int>? bytes}) {
    final ext = _extension(fileName).toLowerCase();

    switch (ext) {
      case 'csv':
      case 'tsv':
        return DataFormat.csv;
      case 'json':
        return DataFormat.json;
      case 'jsonl':
      case 'ndjson':
        return DataFormat.jsonl;
      case 'bin':
      case 'dat':
      case 'hdf5':
      case 'h5':
        return DataFormat.binary;
      case 'gz':
      case 'zip':
        // Compressed wrapper – format determined from inner extension.
        final inner = _innerExtension(fileName);
        if (inner.isNotEmpty) {
          return detect(inner);
        }
        // Fall through to content sniff if inner extension is absent.
        break;
      case '':
        // No extension: fall through to content sniff.
        break;
      default:
        // Unknown extension: fall through to content sniff.
        break;
    }

    // Content-based fallback.
    if (bytes != null && bytes.isNotEmpty) {
      return _sniffContent(bytes, fileName);
    }

    throw FileFormatException(
      'Cannot determine data format for "$fileName". '
      'Provide a recognised extension (.csv, .json, .jsonl, .bin) or '
      'supply file bytes for content-based detection.',
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Returns the last dot-separated segment of [fileName] (without the dot).
  static String _extension(String fileName) {
    final name = fileName.split('/').last.split('\\').last;
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1) : '';
  }

  /// For compressed wrappers (e.g. `session.csv.gz`), returns the inner
  /// file name (e.g. `session.csv`) so that its extension can be detected.
  static String _innerExtension(String fileName) {
    final name = fileName.split('/').last.split('\\').last;
    // Strip outermost extension (e.g. `.gz` or `.zip`).
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : '';
  }

  /// Sniffs the first non-whitespace character of [bytes] to guess the format.
  static DataFormat _sniffContent(List<int> bytes, String fileName) {
    // Find the first non-whitespace byte.
    int? first;
    for (final b in bytes) {
      if (b != 0x20 && b != 0x09 && b != 0x0A && b != 0x0D) {
        first = b;
        break;
      }
    }

    if (first == null) {
      throw FileFormatException(
        'File "$fileName" appears to be empty; cannot detect format.',
      );
    }

    // `[` → JSON array.
    if (first == 0x5B) return DataFormat.json;

    // `{` → JSONL (first line is a JSON object).
    if (first == 0x7B) return DataFormat.jsonl;

    // Digits, minus, letters → likely CSV / text.
    if ((first >= 0x30 && first <= 0x39) || // 0-9
        first == 0x2D || // -
        (first >= 0x41 && first <= 0x5A) || // A-Z
        (first >= 0x61 && first <= 0x7A)) {
      // a-z
      return DataFormat.csv;
    }

    throw FileFormatException(
      'Content of "$fileName" does not match any supported format.',
    );
  }
}
