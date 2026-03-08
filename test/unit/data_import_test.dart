// Tests for Data Import: Parser Architecture, Format Detection, and Compression.
//
// Covers:
//   - DataFormatDetector (extension + content-based fallback)
//   - FileFormatException (message, location, context)
//   - CsvImportParser (comma/tab/semicolon, quoted fields, error cases)
//   - JsonImportParser (JSON array → canonical maps)
//   - JsonlParser (JSONL → canonical maps)
//   - BinaryParser (stub throws FileFormatException)
//   - Decompressor (gzip + zip decompression)

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/services/data_import/binary_parser.dart';
import 'package:ride_metric_x/services/data_import/csv_import_parser.dart';
import 'package:ride_metric_x/services/data_import/data_format.dart';
import 'package:ride_metric_x/services/data_import/decompressor.dart';
import 'package:ride_metric_x/services/data_import/file_format_exception.dart';
import 'package:ride_metric_x/services/data_import/json_import_parser.dart';
import 'package:ride_metric_x/services/data_import/jsonl_parser.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Minimal valid CSV with one data row.
const _csvContent = '''
timestamp_ms,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,temp_c,sample_count
0,0.02,-0.01,1.00,0.5,-0.3,0.1,25.3,0
5,0.03,-0.02,1.01,0.6,-0.2,0.2,25.3,1
''';

/// Minimal valid JSON array.
const _jsonContent = '''
[
  {"timestamp_ms":0,"accel_x_g":0.02,"accel_y_g":-0.01,"accel_z_g":1.0,
   "gyro_x_dps":0.5,"gyro_y_dps":-0.3,"gyro_z_dps":0.1,"temp_c":25.3,"sample_count":0},
  {"timestamp_ms":5,"accel_x_g":0.03,"accel_y_g":-0.02,"accel_z_g":1.01,
   "gyro_x_dps":0.6,"gyro_y_dps":-0.2,"gyro_z_dps":0.2,"temp_c":25.3,"sample_count":1}
]
''';

/// Minimal valid JSONL.
const _jsonlContent = '''
{"timestamp_ms":0,"accel_x_g":0.02,"accel_y_g":-0.01,"accel_z_g":1.0,"gyro_x_dps":0.5,"gyro_y_dps":-0.3,"gyro_z_dps":0.1,"temp_c":25.3,"sample_count":0}
{"timestamp_ms":5,"accel_x_g":0.03,"accel_y_g":-0.02,"accel_z_g":1.01,"gyro_x_dps":0.6,"gyro_y_dps":-0.2,"gyro_z_dps":0.2,"temp_c":25.3,"sample_count":1}
''';

// ── FileFormatException ────────────────────────────────────────────────────────

void main() {
  group('FileFormatException', () {
    test('toString contains the message', () {
      const e = FileFormatException('bad format');
      expect(e.toString(), contains('bad format'));
    });

    test('toString includes line and column when provided', () {
      const e = FileFormatException('oops', line: 3, column: 12);
      expect(e.toString(), contains('line 3'));
      expect(e.toString(), contains('col 12'));
    });

    test('toString includes context snippet when provided', () {
      const e = FileFormatException('oops', context: 'near here');
      expect(e.toString(), contains('near here'));
    });

    test('toString omits location fields when not provided', () {
      const e = FileFormatException('simple error');
      expect(e.toString(), isNot(contains('line')));
      expect(e.toString(), isNot(contains('col')));
    });
  });

  // ── DataFormatDetector ─────────────────────────────────────────────────────

  group('DataFormatDetector – extension detection', () {
    test('detects .csv as csv', () {
      expect(DataFormatDetector.detect('session.csv'), DataFormat.csv);
    });

    test('detects .tsv as csv', () {
      expect(DataFormatDetector.detect('session.tsv'), DataFormat.csv);
    });

    test('detects .json as json', () {
      expect(DataFormatDetector.detect('data.json'), DataFormat.json);
    });

    test('detects .jsonl as jsonl', () {
      expect(DataFormatDetector.detect('data.jsonl'), DataFormat.jsonl);
    });

    test('detects .ndjson as jsonl', () {
      expect(DataFormatDetector.detect('data.ndjson'), DataFormat.jsonl);
    });

    test('detects .bin as binary', () {
      expect(DataFormatDetector.detect('data.bin'), DataFormat.binary);
    });

    test('detects .hdf5 as binary', () {
      expect(DataFormatDetector.detect('data.hdf5'), DataFormat.binary);
    });

    test('detects session.csv.gz inner extension as csv', () {
      expect(DataFormatDetector.detect('session.csv.gz'), DataFormat.csv);
    });

    test('detects session.json.zip inner extension as json', () {
      expect(DataFormatDetector.detect('session.json.zip'), DataFormat.json);
    });

    test('throws FileFormatException for unknown extension without bytes', () {
      expect(
        () => DataFormatDetector.detect('data.xyz'),
        throwsA(isA<FileFormatException>()),
      );
    });

    test('throws FileFormatException for no extension without bytes', () {
      expect(
        () => DataFormatDetector.detect('datafile'),
        throwsA(isA<FileFormatException>()),
      );
    });
  });

  group('DataFormatDetector – content-based fallback', () {
    test('sniffs JSON array from leading [', () {
      final bytes = utf8.encode('[{"a":1}]');
      expect(
        DataFormatDetector.detect('data.xyz', bytes: bytes),
        DataFormat.json,
      );
    });

    test('sniffs JSONL from leading {', () {
      final bytes = utf8.encode('{"a":1}\n{"b":2}');
      expect(
        DataFormatDetector.detect('data', bytes: bytes),
        DataFormat.jsonl,
      );
    });

    test('sniffs CSV from leading digit', () {
      final bytes = utf8.encode('0,1,2,3');
      expect(
        DataFormatDetector.detect('data', bytes: bytes),
        DataFormat.csv,
      );
    });

    test('sniffs CSV from leading letter', () {
      final bytes = utf8.encode('timestamp_ms,value\n0,1.0');
      expect(
        DataFormatDetector.detect('data', bytes: bytes),
        DataFormat.csv,
      );
    });

    test('throws FileFormatException for empty bytes', () {
      expect(
        () => DataFormatDetector.detect('data', bytes: []),
        throwsA(isA<FileFormatException>()),
      );
    });

    test('throws FileFormatException for bytes with only whitespace', () {
      final bytes = utf8.encode('   \n\t  ');
      expect(
        () => DataFormatDetector.detect('data', bytes: bytes),
        throwsA(isA<FileFormatException>()),
      );
    });
  });

  // ── CsvImportParser ────────────────────────────────────────────────────────

  group('CsvImportParser – comma delimiter', () {
    const parser = CsvImportParser();

    test('parses valid CSV with header', () {
      final records = parser.parse(_csvContent);
      expect(records.length, 2);
      expect(records[0]['timestamp_ms'], 0);
      expect(records[0]['accel_z_g'], closeTo(1.0, 1e-6));
      expect(records[1]['sample_count'], 1);
    });

    test('skips comment lines starting with #', () {
      const csv = '''
# sensor: front
timestamp_ms,value
# another comment
0,1.0
5,2.0
''';
      final records = parser.parse(csv);
      expect(records.length, 2);
    });

    test('throws FileFormatException on empty content', () {
      expect(
        () => parser.parse(''),
        throwsA(isA<FileFormatException>()),
      );
    });

    test('throws FileFormatException when row has too few fields', () {
      const csv = 'a,b,c\n1,2';
      expect(() => parser.parse(csv), throwsA(isA<FileFormatException>()));
    });

    test('throws FileFormatException when row has too many fields', () {
      const csv = 'a,b\n1,2,3';
      expect(() => parser.parse(csv), throwsA(isA<FileFormatException>()));
    });

    test('coerces integer fields to int', () {
      const csv = 'n\n42';
      final records = parser.parse(csv);
      expect(records[0]['n'], isA<int>());
      expect(records[0]['n'], 42);
    });

    test('coerces decimal fields to double', () {
      const csv = 'v\n3.14';
      final records = parser.parse(csv);
      expect(records[0]['v'], isA<double>());
      expect(records[0]['v'], closeTo(3.14, 1e-9));
    });

    test('keeps non-numeric fields as strings', () {
      const csv = 'label\nhello';
      final records = parser.parse(csv);
      expect(records[0]['label'], isA<String>());
      expect(records[0]['label'], 'hello');
    });
  });

  group('CsvImportParser – tab delimiter', () {
    const parser = CsvImportParser(delimiter: CsvDelimiter.tab);

    test('parses tab-separated values', () {
      const tsv = 'a\tb\tc\n1\t2.5\thello';
      final records = parser.parse(tsv);
      expect(records.length, 1);
      expect(records[0]['a'], 1);
      expect(records[0]['b'], closeTo(2.5, 1e-9));
      expect(records[0]['c'], 'hello');
    });
  });

  group('CsvImportParser – semicolon delimiter', () {
    const parser = CsvImportParser(delimiter: CsvDelimiter.semicolon);

    test('parses semicolon-separated values', () {
      const csv = 'x;y\n10;20';
      final records = parser.parse(csv);
      expect(records.length, 1);
      expect(records[0]['x'], 10);
      expect(records[0]['y'], 20);
    });
  });

  group('CsvImportParser – auto-detect delimiter', () {
    const parser = CsvImportParser();

    test('auto-detects tab when tab is most frequent', () {
      const tsv = 'a\tb\tc\n1\t2\t3';
      final records = parser.parse(tsv);
      expect(records.length, 1);
      expect(records[0]['b'], 2);
    });

    test('auto-detects semicolon when semicolon is most frequent', () {
      const csv = 'a;b;c\n1;2;3';
      final records = parser.parse(csv);
      expect(records.length, 1);
      expect(records[0]['c'], 3);
    });
  });

  group('CsvImportParser – quoted fields', () {
    const parser = CsvImportParser();

    test('handles basic quoted field', () {
      const csv = 'a,b\n"hello world",2';
      final records = parser.parse(csv);
      expect(records[0]['a'], 'hello world');
    });

    test('handles quoted field with embedded comma', () {
      const csv = 'label,value\n"foo,bar",42';
      final records = parser.parse(csv);
      expect(records[0]['label'], 'foo,bar');
      expect(records[0]['value'], 42);
    });

    test('handles quoted field with escaped double-quote', () {
      const csv = 'msg\n"say ""hello"""';
      final records = parser.parse(csv);
      expect(records[0]['msg'], 'say "hello"');
    });

    test('throws FileFormatException for unterminated quoted field', () {
      const csv = 'a,b\n"unclosed,2';
      expect(() => parser.parse(csv), throwsA(isA<FileFormatException>()));
    });
  });

  // ── JsonImportParser ───────────────────────────────────────────────────────

  group('JsonImportParser', () {
    const parser = JsonImportParser();

    test('parses valid JSON array', () {
      final records = parser.parse(_jsonContent);
      expect(records.length, 2);
      expect(records[0]['timestamp_ms'], 0);
      expect(records[1]['sample_count'], 1);
    });

    test('returns canonical field names from JSON keys', () {
      const json = '[{"timestamp_ms":0,"accel_x_g":0.02}]';
      final records = parser.parse(json);
      expect(records[0].containsKey('timestamp_ms'), isTrue);
      expect(records[0].containsKey('accel_x_g'), isTrue);
    });

    test('throws FileFormatException on empty content', () {
      expect(
        () => parser.parse(''),
        throwsA(isA<FileFormatException>()),
      );
    });

    test('throws FileFormatException on invalid JSON', () {
      expect(
        () => parser.parse('{not valid json'),
        throwsA(isA<FileFormatException>()),
      );
    });

    test('throws FileFormatException when top-level is not an array', () {
      const json = '{"timestamp_ms":0}';
      expect(
        () => parser.parse(json),
        throwsA(isA<FileFormatException>()),
      );
    });

    test('throws FileFormatException when array element is not an object', () {
      const json = '[1, 2, 3]';
      expect(
        () => parser.parse(json),
        throwsA(isA<FileFormatException>()),
      );
    });

    test('returns empty list for empty JSON array', () {
      final records = parser.parse('[]');
      expect(records, isEmpty);
    });
  });

  // ── JsonlParser ────────────────────────────────────────────────────────────

  group('JsonlParser', () {
    const parser = JsonlParser();

    test('parses valid JSONL', () {
      final records = parser.parse(_jsonlContent);
      expect(records.length, 2);
      expect(records[0]['timestamp_ms'], 0);
      expect(records[1]['accel_z_g'], closeTo(1.01, 1e-9));
    });

    test('skips empty lines', () {
      const jsonl = '{"a":1}\n\n{"b":2}\n';
      final records = parser.parse(jsonl);
      expect(records.length, 2);
    });

    test('skips comment lines starting with #', () {
      const jsonl = '# header comment\n{"a":1}\n# another\n{"b":2}';
      final records = parser.parse(jsonl);
      expect(records.length, 2);
    });

    test('throws FileFormatException when all lines are empty', () {
      expect(
        () => parser.parse('\n\n\n'),
        throwsA(isA<FileFormatException>()),
      );
    });

    test('throws FileFormatException on invalid JSON line', () {
      const jsonl = '{"a":1}\nnot json\n{"b":2}';
      expect(() => parser.parse(jsonl), throwsA(isA<FileFormatException>()));
    });

    test('throws FileFormatException when line is not a JSON object', () {
      const jsonl = '[1,2,3]';
      expect(() => parser.parse(jsonl), throwsA(isA<FileFormatException>()));
    });

    test('includes line number in error', () {
      const jsonl = '{"a":1}\nbad line';
      try {
        parser.parse(jsonl);
        fail('Expected FileFormatException');
      } on FileFormatException catch (e) {
        expect(e.line, 2);
      }
    });
  });

  // ── BinaryParser ───────────────────────────────────────────────────────────

  group('BinaryParser', () {
    test('always throws FileFormatException', () {
      expect(
        () => const BinaryParser().parse(''),
        throwsA(isA<FileFormatException>()),
      );
    });

    test('error message mentions binary format', () {
      try {
        const BinaryParser().parse('');
        fail('Expected FileFormatException');
      } on FileFormatException catch (e) {
        expect(e.message.toLowerCase(), contains('binary'));
      }
    });
  });

  // ── Decompressor ───────────────────────────────────────────────────────────

  group('Decompressor – gzip', () {
    test('decompresses gzip-encoded UTF-8 content', () {
      final original = 'timestamp_ms,value\n0,1.0\n5,2.0\n';
      final compressed = GZipEncoder().encode(utf8.encode(original));
      final result = Decompressor.decompress(compressed, CompressionFormat.gzip);
      expect(result, original);
    });

    test('throws FileFormatException on invalid gzip bytes', () {
      expect(
        () => Decompressor.decompress([0x00, 0x01, 0x02], CompressionFormat.gzip),
        throwsA(isA<FileFormatException>()),
      );
    });
  });

  group('Decompressor – zip', () {
    test('decompresses a single-file ZIP archive', () {
      final original = 'timestamp_ms,value\n0,1.0\n5,2.0\n';
      final archive = Archive()
        ..addFile(ArchiveFile('data.csv', original.length, utf8.encode(original)));
      final zipBytes = ZipEncoder().encode(archive);
      final result = Decompressor.decompress(zipBytes, CompressionFormat.zip);
      expect(result, original);
    });

    test('returns first non-directory entry from multi-file ZIP', () {
      final first = 'first file content';
      final second = 'second file content';
      final archive = Archive()
        ..addFile(ArchiveFile('a.csv', first.length, utf8.encode(first)))
        ..addFile(ArchiveFile('b.csv', second.length, utf8.encode(second)));
      final zipBytes = ZipEncoder().encode(archive);
      final result = Decompressor.decompress(zipBytes, CompressionFormat.zip);
      expect(result, first);
    });

    test('throws FileFormatException for empty ZIP archive', () {
      final archive = Archive();
      final zipBytes = ZipEncoder().encode(archive);
      expect(
        () => Decompressor.decompress(zipBytes, CompressionFormat.zip),
        throwsA(isA<FileFormatException>()),
      );
    });

    test('throws FileFormatException on invalid zip bytes', () {
      expect(
        () => Decompressor.decompress([0x00, 0x01, 0x02], CompressionFormat.zip),
        throwsA(isA<FileFormatException>()),
      );
    });
  });

  group('Decompressor – formatFromFileName', () {
    test('detects gzip from .gz extension', () {
      expect(
        Decompressor.formatFromFileName('session.csv.gz'),
        CompressionFormat.gzip,
      );
    });

    test('detects zip from .zip extension', () {
      expect(
        Decompressor.formatFromFileName('session.json.zip'),
        CompressionFormat.zip,
      );
    });

    test('throws FileFormatException for unsupported extension', () {
      expect(
        () => Decompressor.formatFromFileName('data.bz2'),
        throwsA(isA<FileFormatException>()),
      );
    });
  });
}
