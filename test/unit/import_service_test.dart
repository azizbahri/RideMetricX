// Tests for ImportService: pipeline orchestration, progress stream,
// and error paths.
//
// Covers:
//   - FileSelection model
//   - ImportState sealed hierarchy
//   - ImportService.importFile:
//     * CSV – valid content → progress events + ImportSuccess
//     * JSON – valid content → ImportSuccess
//     * JSONL – valid content → ImportSuccess
//     * empty content → ImportError (parser error)
//     * no records after parse → ImportError
//     * unknown file extension → ImportError (format detection)
//     * malformed CSV → ImportError
//     * validation errors surfaced in ImportSuccess.report
//     * record-mapping type coercion (int, double, string fields)
//     * progress milestones emitted in order

import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/models/session_metadata.dart';
import 'package:ride_metric_x/services/data_import/import_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Minimal valid CSV with two data rows (matches canonical IMU schema).
const _validCsv = '''
timestamp_ms,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,temp_c,sample_count
0,0.02,-0.01,1.00,0.5,-0.3,0.1,25.3,0
5,0.03,-0.02,1.01,0.6,-0.2,0.2,25.3,1
''';

/// Minimal valid JSON array with two IMU objects.
const _validJson = '''
[
  {"timestamp_ms":0,"accel_x_g":0.02,"accel_y_g":-0.01,"accel_z_g":1.0,
   "gyro_x_dps":0.5,"gyro_y_dps":-0.3,"gyro_z_dps":0.1,"temp_c":25.3,"sample_count":0},
  {"timestamp_ms":5,"accel_x_g":0.03,"accel_y_g":-0.02,"accel_z_g":1.01,
   "gyro_x_dps":0.6,"gyro_y_dps":-0.2,"gyro_z_dps":0.2,"temp_c":25.3,"sample_count":1}
]
''';

/// Minimal valid JSONL with two IMU objects.
const _validJsonl = '''
{"timestamp_ms":0,"accel_x_g":0.02,"accel_y_g":-0.01,"accel_z_g":1.0,"gyro_x_dps":0.5,"gyro_y_dps":-0.3,"gyro_z_dps":0.1,"temp_c":25.3,"sample_count":0}
{"timestamp_ms":5,"accel_x_g":0.03,"accel_y_g":-0.02,"accel_z_g":1.01,"gyro_x_dps":0.6,"gyro_y_dps":-0.2,"gyro_z_dps":0.2,"temp_c":25.3,"sample_count":1}
''';

/// Collects all [ImportState] events emitted by the service into a list.
Future<List<ImportState>> _collect(
  ImportService svc,
  FileSelection sel,
  SensorPosition pos,
) async {
  final events = <ImportState>[];
  await for (final s in svc.importFile(sel, pos)) {
    events.add(s);
  }
  return events;
}

const ImportService _svc = ImportService();

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── FileSelection model ──────────────────────────────────────────────────

  group('FileSelection', () {
    test('stores fileName and content', () {
      const sel = FileSelection(fileName: 'front.csv', content: 'data');
      expect(sel.fileName, 'front.csv');
      expect(sel.content, 'data');
    });
  });

  // ── ImportState hierarchy ────────────────────────────────────────────────

  group('ImportState', () {
    test('ImportIdle is an ImportState', () {
      expect(const ImportIdle(), isA<ImportState>());
    });

    test('ImportInProgress carries progress value', () {
      const s = ImportInProgress(0.5);
      expect(s, isA<ImportState>());
      expect(s.progress, 0.5);
    });

    test('ImportError carries message', () {
      const s = ImportError('oops');
      expect(s, isA<ImportState>());
      expect(s.message, 'oops');
    });

    test('ImportSuccess carries report, position, fileName, and samples',
        () async {
      // Import valid CSV to obtain a real ImportSuccess state.
      const sel = FileSelection(fileName: 'front.csv', content: _validCsv);
      final events = await _collect(_svc, sel, SensorPosition.front);
      final success = events.last as ImportSuccess;
      expect(success, isA<ImportState>());
      expect(success.position, SensorPosition.front);
      expect(success.fileName, 'front.csv');
      expect(success.samples, isNotEmpty);
      expect(success.report, isNotNull);
    });
  });

  // ── Progress stream – valid CSV ──────────────────────────────────────────

  group('ImportService – valid CSV import', () {
    test('emits at least one ImportInProgress event', () async {
      const sel = FileSelection(fileName: 'front.csv', content: _validCsv);
      final events = await _collect(_svc, sel, SensorPosition.front);
      expect(events.whereType<ImportInProgress>(), isNotEmpty);
    });

    test('progress values are in non-decreasing order', () async {
      const sel = FileSelection(fileName: 'front.csv', content: _validCsv);
      final events = await _collect(_svc, sel, SensorPosition.front);
      final progresses =
          events.whereType<ImportInProgress>().map((e) => e.progress).toList();
      for (int i = 1; i < progresses.length; i++) {
        expect(progresses[i], greaterThanOrEqualTo(progresses[i - 1]));
      }
    });

    test('first event has progress 0.0', () async {
      const sel = FileSelection(fileName: 'front.csv', content: _validCsv);
      final events = await _collect(_svc, sel, SensorPosition.front);
      expect(events.first, isA<ImportInProgress>());
      expect((events.first as ImportInProgress).progress, 0.0);
    });

    test('terminal event is ImportSuccess', () async {
      const sel = FileSelection(fileName: 'front.csv', content: _validCsv);
      final events = await _collect(_svc, sel, SensorPosition.front);
      expect(events.last, isA<ImportSuccess>());
    });

    test('ImportSuccess carries correct position and fileName', () async {
      const sel = FileSelection(fileName: 'session.csv', content: _validCsv);
      final events = await _collect(_svc, sel, SensorPosition.rear);
      final success = events.last as ImportSuccess;
      expect(success.position, SensorPosition.rear);
      expect(success.fileName, 'session.csv');
    });

    test('ImportSuccess contains parsed samples', () async {
      const sel = FileSelection(fileName: 'front.csv', content: _validCsv);
      final events = await _collect(_svc, sel, SensorPosition.front);
      final success = events.last as ImportSuccess;
      expect(success.samples, hasLength(2));
      expect(success.samples.first.timestampMs, 0);
      expect(success.samples.last.timestampMs, 5);
    });

    test('ImportSuccess validation report passed for clean data', () async {
      const sel = FileSelection(fileName: 'front.csv', content: _validCsv);
      final events = await _collect(_svc, sel, SensorPosition.front);
      final success = events.last as ImportSuccess;
      expect(success.report.passed, isTrue);
    });

    test('milestone progress 0.2 emitted after format detection', () async {
      const sel = FileSelection(fileName: 'front.csv', content: _validCsv);
      final events = await _collect(_svc, sel, SensorPosition.front);
      final progresses =
          events.whereType<ImportInProgress>().map((e) => e.progress).toSet();
      expect(progresses, contains(0.2));
    });

    test('milestone progress 1.0 emitted before terminal event', () async {
      const sel = FileSelection(fileName: 'front.csv', content: _validCsv);
      final events = await _collect(_svc, sel, SensorPosition.front);
      final progresses =
          events.whereType<ImportInProgress>().map((e) => e.progress).toList();
      expect(progresses.last, 1.0);
    });
  });

  // ── Valid JSON import ────────────────────────────────────────────────────

  group('ImportService – valid JSON import', () {
    test('succeeds and returns 2 samples', () async {
      const sel = FileSelection(fileName: 'data.json', content: _validJson);
      final events = await _collect(_svc, sel, SensorPosition.front);
      expect(events.last, isA<ImportSuccess>());
      expect((events.last as ImportSuccess).samples, hasLength(2));
    });
  });

  // ── Valid JSONL import ───────────────────────────────────────────────────

  group('ImportService – valid JSONL import', () {
    test('succeeds and returns 2 samples', () async {
      const sel = FileSelection(fileName: 'data.jsonl', content: _validJsonl);
      final events = await _collect(_svc, sel, SensorPosition.rear);
      expect(events.last, isA<ImportSuccess>());
      expect((events.last as ImportSuccess).samples, hasLength(2));
    });
  });

  // ── Error paths ──────────────────────────────────────────────────────────

  group('ImportService – error paths', () {
    test('unknown extension emits ImportError', () async {
      const sel = FileSelection(fileName: 'data.xyz', content: 'stuff');
      final events = await _collect(_svc, sel, SensorPosition.front);
      expect(events.last, isA<ImportError>());
    });

    test('empty CSV content emits ImportError', () async {
      const sel = FileSelection(fileName: 'empty.csv', content: '');
      final events = await _collect(_svc, sel, SensorPosition.front);
      expect(events.last, isA<ImportError>());
    });

    test('CSV with only comments emits ImportError', () async {
      const sel = FileSelection(
        fileName: 'comments.csv',
        content: '# just a comment\n# another comment\n',
      );
      final events = await _collect(_svc, sel, SensorPosition.front);
      expect(events.last, isA<ImportError>());
    });

    test('malformed CSV (column mismatch) emits ImportError', () async {
      const bad = 'timestamp_ms,accel_x_g\n0,0.02,extra_col\n';
      const sel = FileSelection(fileName: 'bad.csv', content: bad);
      final events = await _collect(_svc, sel, SensorPosition.front);
      expect(events.last, isA<ImportError>());
    });

    test('ImportError message is non-empty', () async {
      const sel = FileSelection(fileName: 'empty.csv', content: '');
      final events = await _collect(_svc, sel, SensorPosition.front);
      final error = events.last as ImportError;
      expect(error.message, isNotEmpty);
    });

    test('invalid JSON emits ImportError', () async {
      const sel = FileSelection(
        fileName: 'data.json',
        content: 'not-json',
      );
      final events = await _collect(_svc, sel, SensorPosition.front);
      expect(events.last, isA<ImportError>());
    });

    test('CSV missing required field emits ImportError', () async {
      // Has only 2 columns instead of 9.
      const bad = 'timestamp_ms,accel_x_g\n0,0.02\n5,0.03\n';
      const sel = FileSelection(fileName: 'short.csv', content: bad);
      final events = await _collect(_svc, sel, SensorPosition.front);
      expect(events.last, isA<ImportError>());
    });

    test('ImportError message includes field name when field is missing',
        () async {
      // CSV with correct structure but missing accel_z_g column (only 8
      // columns).  The error message should name the missing/mismatched field.
      const bad = 'timestamp_ms,accel_x_g,accel_y_g,'
          'gyro_x_dps,gyro_y_dps,gyro_z_dps,temp_c,sample_count\n'
          '0,0.02,-0.01,0.5,-0.3,0.1,25.3,0\n';
      const sel = FileSelection(fileName: 'missing_col.csv', content: bad);
      final events = await _collect(_svc, sel, SensorPosition.front);
      expect(events.last, isA<ImportError>());
      final error = events.last as ImportError;
      // The field name should appear in the error message.
      expect(error.message, contains('accel_z_g'));
    });
  });

  // ── Validation report in success ─────────────────────────────────────────

  group('ImportService – validation report', () {
    test('empty sample list in import produces ImportError', () async {
      // A CSV with a header but no data rows results in an ImportError
      // (no-records path in the service).
      const headerOnly = 'timestamp_ms,accel_x_g,accel_y_g,accel_z_g,'
          'gyro_x_dps,gyro_y_dps,gyro_z_dps,temp_c,sample_count\n';
      const sel = FileSelection(fileName: 'nodata.csv', content: headerOnly);
      final events = await _collect(_svc, sel, SensorPosition.front);
      expect(events.last, isA<ImportError>());
    });

    test('validation errors appear in report for non-monotonic timestamps',
        () async {
      // Reverse-order timestamps trigger a validation error.
      const bad = 'timestamp_ms,accel_x_g,accel_y_g,accel_z_g,'
          'gyro_x_dps,gyro_y_dps,gyro_z_dps,temp_c,sample_count\n'
          '10,0.0,0.0,1.0,0.0,0.0,0.0,25.0,0\n'
          '5,0.0,0.0,1.0,0.0,0.0,0.0,25.0,1\n';
      const sel = FileSelection(fileName: 'bad_ts.csv', content: bad);
      final events = await _collect(_svc, sel, SensorPosition.front);
      // Should still succeed (validation errors don't block success),
      // but the report should not pass.
      expect(events.last, isA<ImportSuccess>());
      final success = events.last as ImportSuccess;
      expect(success.report.passed, isFalse);
      expect(success.report.errors, isNotEmpty);
    });
  });
}
