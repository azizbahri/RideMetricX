// Tests for the Data Collection MVP (TC-DC-001..TC-DC-007).
//
// TC-DC-001 – Sampling-rate accuracy
// TC-DC-002 – Accelerometer static 1 G test
// TC-DC-003 – Gyroscope range validation
// TC-DC-004 – Data integrity / dropped-sample detection
// TC-DC-005 – Timestamp monotonicity (data-integrity marker)
// TC-DC-006 – Sensor range validation (reflects mounting / shock limits)
// TC-DC-007 – Front/rear time-synchronisation offset

import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/models/imu_sample.dart';
import 'package:ride_metric_x/models/session_metadata.dart';
import 'package:ride_metric_x/services/data_collection/csv_parser.dart';
import 'package:ride_metric_x/services/data_collection/imu_validator.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Builds [count] clean samples at [rateHz] starting at timestamp 0.
List<ImuSample> makeSamples({
  int count = 20,
  double rateHz = 200.0,
  double accelZ = 1.0,
}) {
  final intervalMs = (1000.0 / rateHz).round();
  return List.generate(
    count,
    (i) => ImuSample(
      timestampMs: i * intervalMs,
      accelXG: 0.02,
      accelYG: -0.01,
      accelZG: accelZ,
      gyroXDps: 0.5,
      gyroYDps: -0.3,
      gyroZDps: 0.1,
      tempC: 25.0,
      sampleCount: i,
    ),
  );
}

/// Convenience: a single valid sample.
ImuSample validSample({
  int t = 0,
  int n = 0,
  double ax = 0.0,
  double ay = 0.0,
  double az = 1.0,
  double gx = 0.0,
  double gy = 0.0,
  double gz = 0.0,
  double temp = 25.0,
}) => ImuSample(
  timestampMs: t,
  accelXG: ax,
  accelYG: ay,
  accelZG: az,
  gyroXDps: gx,
  gyroYDps: gy,
  gyroZDps: gz,
  tempC: temp,
  sampleCount: n,
);

// ── TC-DC-001: Sampling-rate accuracy ─────────────────────────────────────────

void main() {
  group('TC-DC-001: Sampling-rate accuracy (200 Hz)', () {
    test('passes for clean 200 Hz data', () {
      final samples = makeSamples(count: 20, rateHz: 200.0);
      final result = ImuValidator.validate(samples, expectedRateHz: 200.0);
      expect(result.isValid, isTrue);
      expect(result.warnings, isEmpty);
    });

    test(
      'raises a warning when observed rate is ≈100 Hz instead of 200 Hz',
      () {
        // 100 Hz → 10 ms intervals, but we claim 200 Hz → 5 ms expected.
        final samples = makeSamples(count: 20, rateHz: 100.0);
        final result = ImuValidator.validate(samples, expectedRateHz: 200.0);
        expect(
          result.warnings,
          isNotEmpty,
          reason: 'Rate mismatch should produce a warning',
        );
      },
    );

    test('no warnings when expectedRateHz is not supplied', () {
      final samples = makeSamples(count: 10, rateHz: 100.0);
      final result = ImuValidator.validate(samples);
      expect(result.warnings, isEmpty);
    });
  });

  // ── TC-DC-002: Accelerometer static 1 G test ──────────────────────────────

  group('TC-DC-002: Accelerometer static 1 G test', () {
    test('accepts static 1 G reading on the Z-axis', () {
      final samples = makeSamples(count: 10, accelZ: 1.0);
      final result = ImuValidator.validate(samples);
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('rejects accelerometer Z reading beyond +50 g', () {
      final sample = validSample(az: 55.0);
      final result = ImuValidator.validate([sample]);
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('Accelerometer')), isTrue);
    });

    test('rejects accelerometer X reading beyond -50 g', () {
      final sample = validSample(ax: -51.0);
      final result = ImuValidator.validate([sample]);
      expect(result.isValid, isFalse);
    });
  });

  // ── TC-DC-003: Gyroscope range validation ─────────────────────────────────

  group('TC-DC-003: Gyroscope range validation', () {
    test('accepts gyro readings within ±2000 dps', () {
      final sample = validSample(gx: 500.0, gy: -800.0, gz: 1500.0);
      final result = ImuValidator.validate([sample]);
      expect(result.isValid, isTrue);
    });

    test('accepts boundary value of exactly ±2000 dps', () {
      final sample = validSample(gx: 2000.0, gy: -2000.0);
      final result = ImuValidator.validate([sample]);
      expect(result.isValid, isTrue);
    });

    test('rejects gyro X beyond +2000 dps', () {
      final sample = validSample(gx: 2001.0);
      final result = ImuValidator.validate([sample]);
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('Gyroscope')), isTrue);
    });

    test('rejects gyro Z below -2000 dps', () {
      final sample = validSample(gz: -2500.0);
      final result = ImuValidator.validate([sample]);
      expect(result.isValid, isFalse);
    });
  });

  // ── TC-DC-004: Data integrity – dropped-sample detection ──────────────────

  group('TC-DC-004: Data integrity – dropped-sample detection', () {
    test('passes when sample_count is continuous', () {
      final samples = makeSamples(count: 50);
      final result = ImuValidator.validate(samples);
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('detects a single dropped sample', () {
      // sample_count sequence: 0,1,2,3,4, 6 (skipped 5)
      final samples = [
        ...List.generate(5, (i) => validSample(t: i * 5, n: i)),
        validSample(t: 25, n: 6),
      ];
      final result = ImuValidator.validate(samples);
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('Dropped sample')), isTrue);
    });

    test('detects multiple dropped samples', () {
      // Jump from n=2 to n=5 (dropped 3 and 4)
      final samples = [
        validSample(t: 0, n: 0),
        validSample(t: 5, n: 1),
        validSample(t: 10, n: 2),
        validSample(t: 15, n: 5),
      ];
      final result = ImuValidator.validate(samples);
      expect(result.isValid, isFalse);
    });

    test('returns invalid for an empty sample list', () {
      final result = ImuValidator.validate([]);
      expect(result.isValid, isFalse);
      expect(result.errors, isNotEmpty);
    });
  });

  // ── TC-DC-005: Timestamp monotonicity ─────────────────────────────────────

  group('TC-DC-005: Timestamp monotonicity (data-integrity marker)', () {
    test('passes for monotonically increasing timestamps', () {
      final samples = makeSamples(count: 20);
      final result = ImuValidator.validate(samples);
      expect(result.isValid, isTrue);
    });

    test('fails when a timestamp goes backward', () {
      final samples = [
        validSample(t: 0, n: 0),
        validSample(t: 5, n: 1),
        validSample(t: 3, n: 2), // backward
      ];
      final result = ImuValidator.validate(samples);
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('Non-monotonic')), isTrue);
    });

    test('fails when two consecutive timestamps are equal', () {
      final samples = [
        validSample(t: 0, n: 0),
        validSample(t: 5, n: 1),
        validSample(t: 5, n: 2), // duplicate
      ];
      final result = ImuValidator.validate(samples);
      expect(result.isValid, isFalse);
    });
  });

  // ── TC-DC-006: Sensor range validation ────────────────────────────────────

  group('TC-DC-006: Sensor range validation (mounting / shock limits)', () {
    test('accepts readings within all sensor limits', () {
      final samples = makeSamples(count: 5);
      final result = ImuValidator.validate(samples);
      expect(result.isValid, isTrue);
    });

    test('rejects board temperature above operating range', () {
      final sample = validSample(temp: 120.0);
      final result = ImuValidator.validate([sample]);
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('Temperature')), isTrue);
    });

    test('rejects board temperature below operating range', () {
      final sample = validSample(temp: -50.0);
      final result = ImuValidator.validate([sample]);
      expect(result.isValid, isFalse);
    });

    test('accepts boundary temperatures at -40 °C and +85 °C', () {
      final lo = validSample(t: 0, n: 0, temp: -40.0);
      final hi = validSample(t: 5, n: 1, temp: 85.0);
      final result = ImuValidator.validate([lo, hi]);
      expect(result.isValid, isTrue);
    });
  });

  // ── TC-DC-007: Front/rear time synchronisation ────────────────────────────

  group('TC-DC-007: Front/rear time synchronisation (<100 ms)', () {
    test('passes when relative sync offset is within limit (50 ms)', () {
      final front = SessionMetadata(
        sessionId: 'front-001',
        position: SensorPosition.front,
        syncOffsetMs: 50,
        pairedSessionId: 'rear-001',
      );
      final rear = SessionMetadata(
        sessionId: 'rear-001',
        position: SensorPosition.rear,
        syncOffsetMs: 0,
        pairedSessionId: 'front-001',
      );
      final result = ImuValidator.validateSync(front, rear);
      expect(result.isValid, isTrue);
    });

    test('passes when relative sync offset is exactly 99 ms', () {
      final front = SessionMetadata(
        sessionId: 'front-002',
        position: SensorPosition.front,
        syncOffsetMs: 99,
        pairedSessionId: 'rear-002',
      );
      final rear = SessionMetadata(
        sessionId: 'rear-002',
        position: SensorPosition.rear,
        syncOffsetMs: 0,
        pairedSessionId: 'front-002',
      );
      final result = ImuValidator.validateSync(front, rear);
      expect(result.isValid, isTrue);
    });

    test('fails when relative sync offset is exactly 100 ms', () {
      final front = SessionMetadata(
        sessionId: 'front-003',
        position: SensorPosition.front,
        syncOffsetMs: 100,
        pairedSessionId: 'rear-003',
      );
      final rear = SessionMetadata(
        sessionId: 'rear-003',
        position: SensorPosition.rear,
        syncOffsetMs: 0,
        pairedSessionId: 'front-003',
      );
      final result = ImuValidator.validateSync(front, rear);
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('TC-DC-007')), isTrue);
    });

    test('fails when relative sync offset exceeds limit (250 ms)', () {
      final front = SessionMetadata(
        sessionId: 'front-004',
        position: SensorPosition.front,
        syncOffsetMs: 250,
        pairedSessionId: 'rear-004',
      );
      final rear = SessionMetadata(
        sessionId: 'rear-004',
        position: SensorPosition.rear,
        pairedSessionId: 'front-004',
      );
      final result = ImuValidator.validateSync(front, rear);
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('TC-DC-007')), isTrue);
    });

    test('fails when combined offsets exceed limit '
        '(front=+80ms, rear=−80ms → relative=160ms)', () {
      final front = SessionMetadata(
        sessionId: 'front-005',
        position: SensorPosition.front,
        syncOffsetMs: 80,
      );
      final rear = SessionMetadata(
        sessionId: 'rear-005',
        position: SensorPosition.rear,
        syncOffsetMs: -80,
      );
      final result = ImuValidator.validateSync(front, rear);
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('TC-DC-007')), isTrue);
    });

    test('fails when positions are swapped', () {
      final a = SessionMetadata(
        sessionId: 'a',
        position: SensorPosition.rear, // wrong
      );
      final b = SessionMetadata(
        sessionId: 'b',
        position: SensorPosition.front, // wrong
      );
      final result = ImuValidator.validateSync(a, b);
      expect(result.isValid, isFalse);
    });

    test('fails when pairedSessionId does not match peer sessionId', () {
      final front = SessionMetadata(
        sessionId: 'front-006',
        position: SensorPosition.front,
        pairedSessionId: 'rear-999', // wrong
      );
      final rear = SessionMetadata(
        sessionId: 'rear-006',
        position: SensorPosition.rear,
      );
      final result = ImuValidator.validateSync(front, rear);
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('pairedSessionId')), isTrue);
    });
  });

  // ── CsvParser ─────────────────────────────────────────────────────────────

  group('CsvParser', () {
    const validCsv = '''
timestamp_ms,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,temp_c,sample_count
0,0.02,-0.01,1.00,0.5,-0.3,0.1,25.3,0
5,0.03,-0.02,1.01,0.6,-0.2,0.2,25.3,1
10,0.15,0.20,1.35,5.2,3.1,1.5,25.4,2
''';

    test('parses a valid CSV with header', () {
      final samples = CsvParser.parse(validCsv);
      expect(samples.length, 3);
      expect(samples[0].timestampMs, 0);
      expect(samples[0].accelZG, closeTo(1.0, 1e-6));
      expect(samples[2].sampleCount, 2);
    });

    test('skips comment lines starting with #', () {
      const csv = '''
# RideMetricX front sensor
timestamp_ms,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,temp_c,sample_count
# second comment
0,0.02,-0.01,1.00,0.5,-0.3,0.1,25.3,0
''';
      final samples = CsvParser.parse(csv);
      expect(samples.length, 1);
    });

    test('throws FormatException on empty content', () {
      expect(() => CsvParser.parse(''), throwsFormatException);
    });

    test('throws FormatException when required column is missing', () {
      const csv = '''
timestamp_ms,accel_x_g,accel_y_g
0,0.02,-0.01
''';
      expect(() => CsvParser.parse(csv), throwsFormatException);
    });

    test('throws FormatException when column order is wrong', () {
      // accel_y_g and accel_x_g are swapped.
      const csv = '''
timestamp_ms,accel_y_g,accel_x_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,temp_c,sample_count
0,0.02,-0.01,1.00,0.5,-0.3,0.1,25.3,0
''';
      expect(() => CsvParser.parse(csv), throwsFormatException);
    });

    test('throws FormatException when header has extra columns', () {
      const csv = '''
timestamp_ms,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,temp_c,sample_count,extra_col
0,0.02,-0.01,1.00,0.5,-0.3,0.1,25.3,0,99
''';
      expect(() => CsvParser.parse(csv), throwsFormatException);
    });

    test('parsed samples pass ImuValidator', () {
      final samples = CsvParser.parse(validCsv);
      final result = ImuValidator.validate(samples, expectedRateHz: 200.0);
      expect(result.isValid, isTrue);
    });
  });

  // ── ImuSample model ───────────────────────────────────────────────────────

  group('ImuSample', () {
    test('fromCsvRow parses all nine fields correctly', () {
      final row = [
        '0',
        '0.02',
        '-0.01',
        '1.00',
        '0.5',
        '-0.3',
        '0.1',
        '25.3',
        '0',
      ];
      final s = ImuSample.fromCsvRow(row);
      expect(s.timestampMs, 0);
      expect(s.accelXG, closeTo(0.02, 1e-9));
      expect(s.accelZG, closeTo(1.0, 1e-9));
      expect(s.tempC, closeTo(25.3, 1e-9));
      expect(s.sampleCount, 0);
    });

    test('fromCsvRow throws FormatException when too few columns', () {
      expect(
        () => ImuSample.fromCsvRow(['0', '1.0', '0.5']),
        throwsFormatException,
      );
    });

    test('fromCsvRow throws FormatException when too many columns', () {
      expect(
        () => ImuSample.fromCsvRow([
          '0',
          '0.02',
          '-0.01',
          '1.00',
          '0.5',
          '-0.3',
          '0.1',
          '25.3',
          '0',
          'extra',
        ]),
        throwsFormatException,
      );
    });

    test('toMap returns all canonical field names', () {
      final s = validSample(t: 5, n: 1, az: 1.01, temp: 25.3);
      final m = s.toMap();
      expect(m.keys, containsAll(CsvParser.expectedHeaders));
      expect(m['timestamp_ms'], 5);
      expect(m['sample_count'], 1);
    });

    test('equality is based on timestampMs and sampleCount', () {
      final a = validSample(t: 0, n: 0, az: 1.0);
      final b = validSample(t: 0, n: 0, az: 9.9); // different az, same key
      expect(a, equals(b));
    });
  });

  // ── SessionMetadata model ─────────────────────────────────────────────────

  group('SessionMetadata', () {
    test('hasPair is true when pairedSessionId is set', () {
      final meta = SessionMetadata(
        sessionId: 'front-001',
        position: SensorPosition.front,
        pairedSessionId: 'rear-001',
      );
      expect(meta.hasPair, isTrue);
    });

    test('hasPair is false without pairedSessionId', () {
      final meta = SessionMetadata(
        sessionId: 'front-001',
        position: SensorPosition.front,
      );
      expect(meta.hasPair, isFalse);
    });

    test('default samplingRateHz is 200 Hz', () {
      final meta = SessionMetadata(
        sessionId: 's1',
        position: SensorPosition.rear,
      );
      expect(meta.samplingRateHz, 200.0);
    });

    test('default syncOffsetMs is 0', () {
      final meta = SessionMetadata(
        sessionId: 's1',
        position: SensorPosition.front,
      );
      expect(meta.syncOffsetMs, 0);
    });
  });
}
