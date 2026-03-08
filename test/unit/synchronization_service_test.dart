// Tests for Data Import: SynchronizationService.
//
// Covers:
//   - SyncMode enum
//   - SyncResult model (toMap, toString)
//   - SynchronizationService.alignManual
//     * zero offset → full overlap, no timestamp mutation
//     * positive offset → correct overlap window
//     * negative offset → correct overlap window
//     * determinism (same call twice → identical result)
//     * empty stream handling
//   - SynchronizationService.alignAuto (cross-correlation)
//     * zero-offset identical streams → offsetMs == 0
//     * known synthetic offset → detected within ±5 ms (< 10 ms target)
//     * correlation coefficient > 0.9 for well-aligned streams
//     * empty stream handling
//   - Integration: paired front/rear CSV sample data

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/models/imu_sample.dart';
import 'package:ride_metric_x/models/sync_result.dart';
import 'package:ride_metric_x/services/data_import/synchronization_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Builds an [ImuSample] with timestamp and a configurable accelZ value.
ImuSample _sample({
  required int timestampMs,
  double accelZ = 1.0,
  int sampleCount = 0,
}) =>
    ImuSample(
      timestampMs: timestampMs,
      accelXG: 0.0,
      accelYG: 0.0,
      accelZG: accelZ,
      gyroXDps: 0.0,
      gyroYDps: 0.0,
      gyroZDps: 0.0,
      tempC: 25.0,
      sampleCount: sampleCount,
    );

/// Generates [count] regular samples at 200 Hz with a sinusoidal accelZ
/// signal of the specified [amplitude] and [periodSamples].
List<ImuSample> _sineStream({
  required int count,
  int startTimestampMs = 0,
  double amplitude = 1.0,
  int periodSamples = 40, // one full cycle per 40 samples = 5 Hz at 200 Hz
}) {
  return List.generate(count, (i) {
    final angle = 2 * math.pi * i / periodSamples;
    return _sample(
      timestampMs: startTimestampMs + i * 5,
      accelZ: amplitude * math.sin(angle),
      sampleCount: i,
    );
  });
}

// ── SyncMode ──────────────────────────────────────────────────────────────────

void main() {
  group('SyncMode', () {
    test('has manual and auto variants', () {
      expect(SyncMode.values, containsAll([SyncMode.manual, SyncMode.auto]));
    });

    test('name is lowercase string', () {
      expect(SyncMode.manual.name, 'manual');
      expect(SyncMode.auto.name, 'auto');
    });
  });

  // ── SyncResult ───────────────────────────────────────────────────────────────

  group('SyncResult', () {
    final front = [_sample(timestampMs: 0), _sample(timestampMs: 5)];
    final rear = [_sample(timestampMs: 0), _sample(timestampMs: 5)];

    test('toMap contains expected keys and values', () {
      final result = SyncResult(
        frontAligned: front,
        rearAligned: rear,
        offsetMs: 10,
        correlationCoefficient: 0.95,
        mode: SyncMode.auto,
      );
      final map = result.toMap();

      expect(map['offset_ms'], 10);
      expect(map['correlation_coefficient'], closeTo(0.95, 1e-9));
      expect(map['mode'], 'auto');
      expect(map['front_sample_count'], front.length);
      expect(map['rear_sample_count'], rear.length);
    });

    test('toString contains mode and offsetMs', () {
      final result = SyncResult(
        frontAligned: front,
        rearAligned: rear,
        offsetMs: -5,
        correlationCoefficient: 0.80,
        mode: SyncMode.manual,
      );
      expect(result.toString(), contains('manual'));
      expect(result.toString(), contains('-5'));
    });

    test('frontAligned and rearAligned are unmodifiable via service output',
        () {
      final service = SynchronizationService();
      final result = service.alignManual(front, rear, 0);
      expect(
        () => result.frontAligned.add(_sample(timestampMs: 99)),
        throwsUnsupportedError,
      );
    });
  });

  // ── SynchronizationService: alignManual ───────────────────────────────────

  group('SynchronizationService.alignManual', () {
    const service = SynchronizationService();

    test('zero offset: full overlap, timestamps unchanged', () {
      final front = _sineStream(count: 20);
      final rear = _sineStream(count: 20);

      final result = service.alignManual(front, rear, 0);

      expect(result.mode, SyncMode.manual);
      expect(result.offsetMs, 0);
      expect(result.frontAligned.length, 20);
      expect(result.rearAligned.length, 20);
      // Rear timestamps should remain the same (offset = 0 → no shift)
      for (int i = 0; i < 20; i++) {
        expect(result.rearAligned[i].timestampMs,
            result.frontAligned[i].timestampMs);
      }
    });

    test(
        'positive offset (front started 25 ms after rear): '
        'rear is trimmed to overlap', () {
      // rear:  t = 0..99ms (20 samples at 5 ms apart)
      // front: t = 0..99ms (20 samples at 5 ms apart)
      // offsetMs = 25 → rear shifted to t = -25..74ms
      // overlap: t = 0..74ms → front has 15 samples, rear has 15 samples
      final front = _sineStream(count: 20);
      final rear = _sineStream(count: 20);

      final result = service.alignManual(front, rear, 25);

      expect(result.offsetMs, 25);
      // Overlap is t=0..74ms → 15 samples (t=0,5,10,...,70; step 5ms)
      expect(result.frontAligned.length, 15);
      expect(result.rearAligned.length, 15);
      // Both aligned streams share the same timestamps in the overlap
      for (int i = 0; i < result.frontAligned.length; i++) {
        expect(result.frontAligned[i].timestampMs,
            result.rearAligned[i].timestampMs);
      }
    });

    test(
        'negative offset (front started 25 ms before rear): '
        'front is trimmed to overlap', () {
      final front = _sineStream(count: 20);
      final rear = _sineStream(count: 20);

      // offsetMs = -25 → rear shifted to t = 25..124ms
      // front covers 0..99ms; overlap is 25..99ms → 15 front samples
      final result = service.alignManual(front, rear, -25);

      expect(result.offsetMs, -25);
      expect(result.frontAligned.length, 15);
      expect(result.rearAligned.length, 15);
    });

    test('offset larger than stream duration → empty aligned streams', () {
      final front = _sineStream(count: 10); // t = 0..45ms
      final rear = _sineStream(count: 10); // t = 0..45ms

      // offset = 100 shifts rear to t = -100..-55 → no overlap with front
      final result = service.alignManual(front, rear, 100);

      expect(result.frontAligned, isEmpty);
      expect(result.rearAligned, isEmpty);
    });

    test('empty front stream → empty result', () {
      final result = service.alignManual([], _sineStream(count: 10), 0);
      expect(result.frontAligned, isEmpty);
      expect(result.rearAligned, isEmpty);
      expect(result.offsetMs, 0);
    });

    test('empty rear stream → empty result', () {
      final result = service.alignManual(_sineStream(count: 10), [], 0);
      expect(result.frontAligned, isEmpty);
      expect(result.rearAligned, isEmpty);
    });

    test('is deterministic: same inputs → identical results', () {
      final front = _sineStream(count: 40);
      final rear = _sineStream(count: 40);

      final r1 = service.alignManual(front, rear, 15);
      final r2 = service.alignManual(front, rear, 15);

      expect(r1.offsetMs, r2.offsetMs);
      expect(r1.correlationCoefficient, r2.correlationCoefficient);
      expect(r1.frontAligned.length, r2.frontAligned.length);
    });

    test('correlation coefficient is in [-1, 1]', () {
      final front = _sineStream(count: 40);
      final rear = _sineStream(count: 40);
      final result = service.alignManual(front, rear, 0);

      expect(result.correlationCoefficient, greaterThanOrEqualTo(-1.0));
      expect(result.correlationCoefficient, lessThanOrEqualTo(1.0));
    });

    test('identical streams → correlation coefficient ≈ 1.0', () {
      final stream = _sineStream(count: 100);
      final result = service.alignManual(stream, stream, 0);

      expect(result.correlationCoefficient, closeTo(1.0, 1e-6));
    });
  });

  // ── SynchronizationService: alignAuto ─────────────────────────────────────

  group('SynchronizationService.alignAuto', () {
    const service = SynchronizationService();

    test('identical streams → offsetMs == 0 and correlation ≈ 1.0', () {
      // Use maxSearchMs = 100 ms (±20 samples) so the search window is
      // narrower than one sine period (40 samples = 200 ms), preventing
      // spurious perfect-correlation matches at lag = ±period.
      final stream = _sineStream(count: 200);
      final result = service.alignAuto(stream, stream, maxSearchMs: 100);

      expect(result.mode, SyncMode.auto);
      expect(result.offsetMs, 0);
      expect(result.correlationCoefficient, closeTo(1.0, 1e-6));
    });

    test(
        'known offset of +25 ms (front started 25 ms after rear): '
        'detected within ±5 ms (< 10 ms target)', () {
      // Construct streams where front[i] == rear[i + 5] (5 samples = 25 ms).
      // rear has 5 extra samples at the start.
      const n = 200;
      const lagSamples = 5; // 5 × 5 ms = 25 ms
      // Build a common base of n + lagSamples samples.
      final base = _sineStream(count: n + lagSamples);

      // front: base[5..n+4], renumbered t = 0..n-1 * 5ms
      final front = List<ImuSample>.generate(n, (i) {
        final src = base[i + lagSamples];
        return _sample(
          timestampMs: i * 5,
          accelZ: src.accelZG,
          sampleCount: i,
        );
      });

      // rear: base[0..n-1], t = 0..(n-1)*5ms
      final rear = List<ImuSample>.generate(n, (i) {
        return _sample(
          timestampMs: i * 5,
          accelZ: base[i].accelZG,
          sampleCount: i,
        );
      });

      // front[i] == rear[i + 5] → front started 25 ms after rear.
      // maxSearchMs = 100 ms (±20 samples) keeps the search range below one
      // sine period (40 samples = 200 ms), ensuring a unique correlation peak.
      final result = service.alignAuto(front, rear, maxSearchMs: 100);

      // Offset should be 25 ms (or within one sample period = 5 ms).
      expect(result.offsetMs, closeTo(25, 5));
      expect(result.correlationCoefficient, greaterThan(0.9));
    });

    test(
        'known offset of +50 ms (front started 50 ms after rear): '
        'detected within ±5 ms', () {
      const n = 200;
      const lagSamples = 10; // 10 × 5 ms = 50 ms
      final base = _sineStream(count: n + lagSamples);

      final front = List<ImuSample>.generate(n, (i) {
        final src = base[i + lagSamples];
        return _sample(
          timestampMs: i * 5,
          accelZ: src.accelZG,
          sampleCount: i,
        );
      });
      final rear = List<ImuSample>.generate(n, (i) {
        return _sample(
          timestampMs: i * 5,
          accelZ: base[i].accelZG,
          sampleCount: i,
        );
      });

      // maxSearchMs = 100 ms (±20 samples) keeps the search range below one
      // sine period (40 samples = 200 ms), ensuring a unique correlation peak.
      final result = service.alignAuto(front, rear, maxSearchMs: 100);

      expect(result.offsetMs, closeTo(50, 5));
      expect(result.correlationCoefficient, greaterThan(0.9));
    });

    test('empty front stream → offsetMs == 0, empty aligned streams', () {
      final result = service.alignAuto([], _sineStream(count: 10));
      expect(result.offsetMs, 0);
      expect(result.frontAligned, isEmpty);
      expect(result.rearAligned, isEmpty);
    });

    test('empty rear stream → offsetMs == 0, empty aligned streams', () {
      final result = service.alignAuto(_sineStream(count: 10), []);
      expect(result.offsetMs, 0);
      expect(result.frontAligned, isEmpty);
      expect(result.rearAligned, isEmpty);
    });

    test('toMap is populated with auto mode', () {
      final stream = _sineStream(count: 40);
      final result = service.alignAuto(stream, stream);
      final map = result.toMap();

      expect(map['mode'], 'auto');
      expect(map['offset_ms'], isA<int>());
      expect(map['correlation_coefficient'], isA<double>());
    });
  });

  // ── Integration: paired front/rear sample data ─────────────────────────────

  group('SynchronizationService integration (paired front/rear streams)', () {
    /// Parses the 9-column IMU CSV lines (skipping comment and header rows).
    List<ImuSample> _parseCsvLines(String csv) {
      final samples = <ImuSample>[];
      for (final line in csv.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final parts = trimmed.split(',');
        if (parts.length != 9) continue;
        try {
          samples.add(ImuSample.fromCsvRow(parts));
        } catch (_) {
          // Skip header row
        }
      }
      return samples;
    }

    // Inline sample data mirrors assets/data/front_imu_sample.csv and
    // assets/data/rear_imu_sample.csv so the test has no asset dependency.
    const _frontCsv = '''
# RideMetricX – Front Suspension IMU Sample Data
timestamp_ms,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,temp_c,sample_count
0,0.02,-0.01,1.00,0.50,-0.30,0.10,25.3,0
5,0.03,-0.02,1.01,0.60,-0.20,0.20,25.3,1
10,0.15,0.20,1.35,5.20,3.10,1.50,25.4,2
15,0.22,0.35,1.62,9.10,6.50,2.30,25.4,3
20,0.18,0.28,1.45,7.40,5.20,1.80,25.5,4
25,0.10,0.15,1.22,3.50,2.40,1.10,25.5,5
30,0.05,0.08,1.08,1.20,0.90,0.40,25.5,6
35,0.03,0.04,1.02,0.70,0.50,0.20,25.6,7
40,0.02,0.02,1.00,0.50,0.30,0.10,25.6,8
45,0.04,0.06,1.05,1.50,1.10,0.50,25.6,9
50,0.12,0.18,1.28,6.30,4.80,1.70,25.7,10
55,0.25,0.40,1.72,12.50,9.20,3.10,25.7,11
60,0.30,0.48,1.85,15.20,11.30,3.80,25.7,12
65,0.28,0.44,1.78,13.80,10.10,3.40,25.8,13
70,0.20,0.32,1.55,8.90,6.70,2.20,25.8,14
75,0.12,0.19,1.30,4.60,3.50,1.20,25.8,15
80,0.06,0.10,1.10,2.10,1.60,0.60,25.9,16
85,0.03,0.05,1.03,0.80,0.60,0.25,25.9,17
90,0.02,0.02,1.00,0.50,0.30,0.10,25.9,18
95,0.02,0.02,1.00,0.50,0.30,0.10,26.0,19
''';

    const _rearCsv = '''
# RideMetricX – Rear Suspension IMU Sample Data
timestamp_ms,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,temp_c,sample_count
0,0.01,-0.01,0.98,0.30,-0.20,0.08,26.1,0
5,0.02,-0.01,0.99,0.40,-0.15,0.12,26.1,1
10,0.08,0.12,1.18,3.10,2.20,0.90,26.2,2
15,0.14,0.22,1.40,6.80,4.90,1.80,26.2,3
20,0.11,0.17,1.28,5.20,3.80,1.40,26.3,4
25,0.07,0.10,1.12,2.80,2.00,0.75,26.3,5
30,0.03,0.05,1.04,1.10,0.80,0.30,26.3,6
35,0.02,0.03,1.01,0.50,0.35,0.15,26.4,7
40,0.01,0.01,0.98,0.30,0.20,0.08,26.4,8
45,0.03,0.04,1.03,1.20,0.85,0.35,26.4,9
50,0.09,0.14,1.22,4.80,3.50,1.30,26.5,10
55,0.18,0.30,1.52,9.80,7.20,2.50,26.5,11
60,0.22,0.36,1.65,11.80,8.70,2.90,26.5,12
65,0.20,0.32,1.58,10.40,7.80,2.60,26.6,13
70,0.15,0.24,1.42,7.20,5.40,1.85,26.6,14
75,0.09,0.15,1.22,3.80,2.80,0.95,26.6,15
80,0.04,0.07,1.07,1.60,1.20,0.45,26.7,16
85,0.02,0.03,1.01,0.60,0.45,0.18,26.7,17
90,0.01,0.01,0.98,0.30,0.20,0.08,26.7,18
95,0.01,0.01,0.98,0.30,0.20,0.08,26.8,19
''';

    test('manual zero-offset: both streams fully overlap (20 samples)', () {
      final front = _parseCsvLines(_frontCsv);
      final rear = _parseCsvLines(_rearCsv);
      const service = SynchronizationService();

      final result = service.alignManual(front, rear, 0);

      expect(result.frontAligned.length, 20);
      expect(result.rearAligned.length, 20);
      expect(result.offsetMs, 0);
    });

    test('manual +5 ms offset: overlap is 19 samples', () {
      final front = _parseCsvLines(_frontCsv);
      final rear = _parseCsvLines(_rearCsv);
      const service = SynchronizationService();

      // offsetMs = 5 → rear shifted to t = -5..90ms; overlap = 0..90ms → 19 samples
      final result = service.alignManual(front, rear, 5);

      expect(result.frontAligned.length, 19);
      expect(result.rearAligned.length, 19);
    });

    test('auto alignment on correlated sample data: sync quality is reported',
        () {
      final front = _parseCsvLines(_frontCsv);
      final rear = _parseCsvLines(_rearCsv);
      const service = SynchronizationService();

      final result = service.alignAuto(front, rear);

      // SyncResult is populated with quality metrics
      expect(result.mode, SyncMode.auto);
      expect(result.correlationCoefficient, greaterThanOrEqualTo(-1.0));
      expect(result.correlationCoefficient, lessThanOrEqualTo(1.0));
      expect(result.frontAligned, isNotEmpty);
      expect(result.rearAligned, isNotEmpty);
    });

    test('toMap persists synchronization parameters', () {
      final front = _parseCsvLines(_frontCsv);
      final rear = _parseCsvLines(_rearCsv);
      const service = SynchronizationService();

      final result = service.alignManual(front, rear, 10);
      final map = result.toMap();

      expect(map.containsKey('offset_ms'), isTrue);
      expect(map.containsKey('correlation_coefficient'), isTrue);
      expect(map.containsKey('mode'), isTrue);
      expect(map.containsKey('front_sample_count'), isTrue);
      expect(map.containsKey('rear_sample_count'), isTrue);
      expect(map['offset_ms'], 10);
    });
  });
}
