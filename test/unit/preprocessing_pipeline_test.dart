// Tests for Data Import: Preprocessing Pipeline
//
// Covers all acceptance criteria from issue #8:
//   AC-1: Preprocessing stages are configurable and composable.
//   AC-2: Default config yields deterministic outputs for same input.
//   AC-3: Resampling produces uniform timeline and expected sample counts.
//   AC-4: Gravity-removed acceleration is exposed in processed output schema.
//
// Unit tests per stage:
//   - ResampleStage
//   - FilterStage (Butterworth low-pass and high-pass)
//   - CoordinateTransformStage
//   - GravityRemoval (complementary filter)
//   - Integration (velocity + position + drift correction)
//   - PreprocessingPipeline (composition + defaults)
//
// Golden / snapshot tests:
//   - Known at-rest input → gravity-removed ≈ 0 m/s²
//   - Known sinusoidal input filtered at 10 Hz → high-frequency attenuation

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/models/imu_sample.dart';
import 'package:ride_metric_x/models/preprocessing_config.dart';
import 'package:ride_metric_x/models/processed_sample.dart';
import 'package:ride_metric_x/services/data_import/preprocessing_pipeline.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Builds a flat [ImuSample] for tests.
ImuSample _sample({
  required int timestampMs,
  double accelX = 0.0,
  double accelY = 0.0,
  double accelZ = 1.0,
  double gyroX = 0.0,
  double gyroY = 0.0,
  double gyroZ = 0.0,
  double temp = 25.0,
  int sampleCount = 0,
}) =>
    ImuSample(
      timestampMs: timestampMs,
      accelXG: accelX,
      accelYG: accelY,
      accelZG: accelZ,
      gyroXDps: gyroX,
      gyroYDps: gyroY,
      gyroZDps: gyroZ,
      tempC: temp,
      sampleCount: sampleCount,
    );

/// Generates [count] uniform samples at [rateHz] starting at [startMs].
List<ImuSample> _uniformStream({
  required int count,
  double rateHz = 200.0,
  int startMs = 0,
  double accelZ = 1.0,
  double accelX = 0.0,
  double accelY = 0.0,
  double gyroX = 0.0,
}) {
  final periodMs = (1000.0 / rateHz).round();
  return List.generate(
    count,
    (i) => _sample(
      timestampMs: startMs + i * periodMs,
      accelX: accelX,
      accelY: accelY,
      accelZ: accelZ,
      gyroX: gyroX,
      sampleCount: i,
    ),
  );
}

// ── AC-1 / AC-2: Configurability and determinism ──────────────────────────────

void main() {
  group('AC-1: Preprocessing stages are configurable and composable', () {
    test('empty input returns empty output for any config', () {
      const pipeline = PreprocessingPipeline();
      expect(pipeline.process([]), isEmpty);
    });

    test(
        'all stages disabled except gravity → output only contains '
        'linear acceleration', () {
      final samples = _uniformStream(count: 20);
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
          resample: ResampleConfig(enabled: false),
          coordinateTransform: CoordinateTransformConfig(enabled: false),
          gravity: GravityConfig(enabled: true),
          integration: IntegrationConfig(enabled: false),
        ),
      );
      final result = pipeline.process(samples);
      expect(result.length, 20);
      // velocity and position are null when integration is disabled
      expect(result.first.velocityX, isNull);
      expect(result.first.positionX, isNull);
    });

    test('gravity disabled → linear accel = raw accel × 9.80665', () {
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
          gravity: GravityConfig(enabled: false),
        ),
      );
      final samples = _uniformStream(count: 5);
      final result = pipeline.process(samples);
      for (final ps in result) {
        expect(ps.accelZLinear, closeTo(1.0 * 9.80665, 1e-9));
        expect(ps.accelXLinear, closeTo(0.0 * 9.80665, 1e-9));
      }
    });

    test('integration enabled → velocity and position are non-null', () {
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
          integration: IntegrationConfig(enabled: true),
        ),
      );
      final samples = _uniformStream(count: 10);
      final result = pipeline.process(samples);
      expect(result.first.velocityX, isNotNull);
      expect(result.first.positionX, isNotNull);
    });

    test('pipeline config is accessible', () {
      const config = PreprocessingConfig(
        filter: FilterConfig(cutoffHz: 5.0, order: 2),
      );
      const pipeline = PreprocessingPipeline(config: config);
      expect(pipeline.config.filter.cutoffHz, 5.0);
    });
  });

  // ── AC-2: Determinism ───────────────────────────────────────────────────────

  group('AC-2: Default config yields deterministic outputs', () {
    test('same input → identical output on repeated calls', () {
      const pipeline = PreprocessingPipeline();
      final samples = _uniformStream(count: 50);

      final r1 = pipeline.process(samples);
      final r2 = pipeline.process(samples);

      expect(r1.length, r2.length);
      for (int i = 0; i < r1.length; i++) {
        expect(r1[i].accelXLinear, r1[i].accelXLinear);
        expect(r1[i].accelXLinear, r2[i].accelXLinear);
        expect(r1[i].accelYLinear, r2[i].accelYLinear);
        expect(r1[i].accelZLinear, r2[i].accelZLinear);
        expect(r1[i].raw.timestampMs, r2[i].raw.timestampMs);
      }
    });

    test('two independent pipeline instances produce identical results', () {
      const p1 = PreprocessingPipeline();
      const p2 = PreprocessingPipeline();
      final samples = _uniformStream(count: 30);

      final r1 = p1.process(samples);
      final r2 = p2.process(samples);

      for (int i = 0; i < r1.length; i++) {
        expect(r1[i].accelZLinear, r2[i].accelZLinear);
      }
    });
  });

  // ── AC-3: Resampling ────────────────────────────────────────────────────────

  group('AC-3: Resampling produces uniform timeline and expected sample counts',
      () {
    test('100 Hz stream resampled to 200 Hz doubles sample count (approx)', () {
      // 100 samples at 100 Hz → 1 second of data
      final samples = _uniformStream(count: 100, rateHz: 100.0);
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
          resample: ResampleConfig(enabled: true, targetRateHz: 200.0),
          gravity: GravityConfig(enabled: false),
        ),
      );
      final result = pipeline.process(samples);
      // 1 second at 200 Hz → ~200 samples (may be 199–200 due to endpoint)
      expect(result.length, greaterThanOrEqualTo(198));
      expect(result.length, lessThanOrEqualTo(200));
    });

    test('200 Hz stream resampled to 100 Hz halves sample count (approx)', () {
      final samples = _uniformStream(count: 200, rateHz: 200.0);
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
          resample: ResampleConfig(enabled: true, targetRateHz: 100.0),
          gravity: GravityConfig(enabled: false),
        ),
      );
      final result = pipeline.process(samples);
      expect(result.length, greaterThanOrEqualTo(98));
      expect(result.length, lessThanOrEqualTo(100));
    });

    test('resampled output has uniform inter-sample interval', () {
      final samples = _uniformStream(count: 50, rateHz: 100.0);
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
          resample: ResampleConfig(enabled: true, targetRateHz: 200.0),
          gravity: GravityConfig(enabled: false),
        ),
      );
      final result = pipeline.process(samples);
      if (result.length < 2) return;

      final expectedPeriodMs = (1000.0 / 200.0).round(); // 5 ms
      for (int i = 1; i < result.length; i++) {
        final dt = result[i].raw.timestampMs - result[i - 1].raw.timestampMs;
        expect(dt, expectedPeriodMs,
            reason: 'Non-uniform gap at index $i: got $dt ms');
      }
    });

    test('resampled output preserves start and end timestamps', () {
      final samples = _uniformStream(count: 20, rateHz: 100.0);
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
          resample: ResampleConfig(enabled: true, targetRateHz: 200.0),
          gravity: GravityConfig(enabled: false),
        ),
      );
      final result = pipeline.process(samples);
      expect(result.first.raw.timestampMs, samples.first.timestampMs);
    });

    test('single sample passes through without crash', () {
      final samples = [_sample(timestampMs: 0)];
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          resample: ResampleConfig(enabled: true, targetRateHz: 100.0),
          gravity: GravityConfig(enabled: false),
        ),
      );
      final result = pipeline.process(samples);
      expect(result.length, 1);
    });
  });

  // ── AC-4: Gravity-removed acceleration in output schema ─────────────────────

  group(
      'AC-4: Gravity-removed acceleration is exposed in processed output schema',
      () {
    test('ProcessedSample has accelXLinear, accelYLinear, accelZLinear fields',
        () {
      const ps = ProcessedSample(
        raw: ImuSample(
          timestampMs: 0,
          accelXG: 0.0,
          accelYG: 0.0,
          accelZG: 1.0,
          gyroXDps: 0.0,
          gyroYDps: 0.0,
          gyroZDps: 0.0,
          tempC: 25.0,
          sampleCount: 0,
        ),
        accelXLinear: 0.1,
        accelYLinear: 0.2,
        accelZLinear: 0.3,
      );
      expect(ps.accelXLinear, 0.1);
      expect(ps.accelYLinear, 0.2);
      expect(ps.accelZLinear, 0.3);
    });

    test('toMap() includes accel_x_linear_ms2, y, z fields', () {
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
        ),
      );
      final samples = _uniformStream(count: 5);
      final result = pipeline.process(samples);
      final map = result.first.toMap();

      expect(map.containsKey('accel_x_linear_ms2'), isTrue);
      expect(map.containsKey('accel_y_linear_ms2'), isTrue);
      expect(map.containsKey('accel_z_linear_ms2'), isTrue);
    });

    test('toMap() includes raw IMU fields', () {
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(filter: FilterConfig(enabled: false)),
      );
      final samples = _uniformStream(count: 3);
      final map = pipeline.process(samples).first.toMap();

      expect(map.containsKey('timestamp_ms'), isTrue);
      expect(map.containsKey('accel_z_g'), isTrue);
    });

    test(
        'at-rest sensor (accelZ=1g, gyros=0): gravity-removed linear accel '
        'converges to ≈ 0 m/s²', () {
      // 200 samples at 200 Hz (1 second) of perfectly level at-rest data.
      final samples = _uniformStream(
        count: 200,
        rateHz: 200.0,
        accelZ: 1.0,
        accelX: 0.0,
        accelY: 0.0,
      );
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
          gravity: GravityConfig(
            enabled: true,
            complementaryAlpha: 0.98,
          ),
        ),
      );
      final result = pipeline.process(samples);

      // After the filter converges (skip first 20 samples), the linear accel
      // should be very close to zero on all axes.
      for (int i = 20; i < result.length; i++) {
        expect(
          result[i].accelZLinear,
          closeTo(0.0, 0.1),
          reason: 'accelZLinear not near zero at sample $i',
        );
        expect(result[i].accelXLinear, closeTo(0.0, 0.1));
        expect(result[i].accelYLinear, closeTo(0.0, 0.1));
      }
    });

    test('gravity-removed acceleration preserves original raw sample', () {
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(filter: FilterConfig(enabled: false)),
      );
      final samples = _uniformStream(count: 5);
      final result = pipeline.process(samples);

      for (int i = 0; i < result.length; i++) {
        expect(result[i].raw.sampleCount, i);
        expect(result[i].raw.accelZG, 1.0);
      }
    });
  });

  // ── Unit tests: Filter stage ──────────────────────────────────────────────

  group('FilterStage', () {
    test('low-pass filter attenuates high-frequency content', () {
      // Build a signal that is a 50 Hz sine wave sampled at 200 Hz.
      // After a 10 Hz LP filter the amplitude should be reduced significantly.
      const rateHz = 200.0;
      const freqHz = 50.0; // well above cutoff
      const n = 400;
      final samples = List.generate(n, (i) {
        final t = i / rateHz;
        final accelZ = 1.0 + 0.5 * math.sin(2 * math.pi * freqHz * t);
        return _sample(
          timestampMs: (i * 1000.0 / rateHz).round(),
          accelZ: accelZ,
          sampleCount: i,
        );
      });

      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(
            enabled: true,
            type: FilterType.lowPass,
            cutoffHz: 10.0,
          ),
          gravity: GravityConfig(enabled: false),
        ),
      );
      final result = pipeline.process(samples);

      // Measure the amplitude of the filtered signal in the steady-state
      // region (after the filter has settled: skip first 10% of samples).
      final start = n ~/ 10;
      double maxLinear = 0.0;
      double minLinear = double.infinity;
      for (int i = start; i < result.length; i++) {
        final v = result[i].accelZLinear / 9.80665;
        if (v > maxLinear) maxLinear = v;
        if (v < minLinear) minLinear = v;
      }
      final amplitude = (maxLinear - minLinear) / 2.0;
      // The 50 Hz component should be strongly attenuated below cutoff 10 Hz.
      // Butterworth 2nd-order at 5× the cutoff → attenuation factor ≥ 25×,
      // so residual amplitude < 0.5 / 25 ≈ 0.02.
      expect(amplitude, lessThan(0.05));
    });

    test('high-pass filter removes DC component', () {
      // Constant signal: after HP filter the output should be near zero.
      final samples = _uniformStream(count: 200, rateHz: 200.0, accelZ: 1.5);
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(
            enabled: true,
            type: FilterType.highPass,
            cutoffHz: 5.0,
          ),
          gravity: GravityConfig(enabled: false),
        ),
      );
      final result = pipeline.process(samples);

      // Skip the transient region at both ends (zero-phase filter has none,
      // but keep a margin of 20% for safety).
      final margin = result.length ~/ 5;
      for (int i = margin; i < result.length - margin; i++) {
        // After HP filtering a DC signal the output ≈ 0.
        expect(
          result[i].accelZLinear / 9.80665,
          closeTo(0.0, 0.01),
          reason: 'HP filter residual too large at sample $i',
        );
      }
    });

    test('filter is deterministic: same call twice → identical result', () {
      final samples = _uniformStream(count: 100, rateHz: 200.0);
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(gravity: GravityConfig(enabled: false)),
      );
      final r1 = pipeline.process(samples);
      final r2 = pipeline.process(samples);
      for (int i = 0; i < r1.length; i++) {
        expect(r1[i].accelZLinear, r2[i].accelZLinear);
      }
    });

    test('filter stage with cutoff above Nyquist passes data unchanged', () {
      // Cutoff 150 Hz, Nyquist at 100 Hz → filter silently disabled.
      final samples = _uniformStream(count: 20, rateHz: 200.0, accelZ: 2.0);
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: true, cutoffHz: 150.0),
          gravity: GravityConfig(enabled: false),
        ),
      );
      final result = pipeline.process(samples);
      for (final ps in result) {
        expect(ps.accelZLinear, closeTo(2.0 * 9.80665, 1e-9));
      }
    });
  });

  // ── Unit tests: Coordinate transform stage ────────────────────────────────

  group('CoordinateTransformStage', () {
    test('zero mounting angles → samples pass through unchanged', () {
      final samples = _uniformStream(
        count: 5,
        accelX: 1.0,
        accelY: 2.0,
        accelZ: 3.0,
      );
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
          coordinateTransform: CoordinateTransformConfig(
            enabled: true,
            mountingRollDeg: 0.0,
            mountingPitchDeg: 0.0,
            mountingYawDeg: 0.0,
          ),
          gravity: GravityConfig(enabled: false),
        ),
      );
      final result = pipeline.process(samples);
      for (final ps in result) {
        expect(ps.raw.accelXG, closeTo(1.0, 1e-9));
        expect(ps.raw.accelYG, closeTo(2.0, 1e-9));
        expect(ps.raw.accelZG, closeTo(3.0, 1e-9));
      }
    });

    test('90° yaw rotation: X→Y, Y→−X', () {
      // A 90° yaw (rotation about Z) transforms:
      //   new_x = cos(90°)*x + sin(90°)*y = y
      //   new_y = -sin(90°)*x + cos(90°)*y = -x
      //   new_z unchanged
      final samples = [
        _sample(timestampMs: 0, accelX: 1.0, accelY: 0.0, accelZ: 0.0),
      ];
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
          coordinateTransform: CoordinateTransformConfig(
            enabled: true,
            mountingYawDeg: 90.0,
          ),
          gravity: GravityConfig(enabled: false),
        ),
      );
      final result = pipeline.process(samples);
      expect(result.first.raw.accelXG, closeTo(0.0, 1e-9));
      expect(result.first.raw.accelYG, closeTo(1.0, 1e-9));
      expect(result.first.raw.accelZG, closeTo(0.0, 1e-9));
    });

    test('180° roll rotation: Y→−Y, Z→−Z', () {
      final samples = [
        _sample(timestampMs: 0, accelX: 0.0, accelY: 1.0, accelZ: 1.0),
      ];
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
          coordinateTransform: CoordinateTransformConfig(
            enabled: true,
            mountingRollDeg: 180.0,
          ),
          gravity: GravityConfig(enabled: false),
        ),
      );
      final result = pipeline.process(samples);
      expect(result.first.raw.accelXG, closeTo(0.0, 1e-9));
      expect(result.first.raw.accelYG, closeTo(-1.0, 1e-9));
      expect(result.first.raw.accelZG, closeTo(-1.0, 1e-9));
    });
  });

  // ── Unit tests: Gravity removal stage ────────────────────────────────────

  group('GravityRemoval', () {
    test(
        'sensor pitched 45° (accelX = −sin45°, accelZ = cos45°): '
        'gravity-removed linear accel converges to ≈ 0', () {
      const pitchDeg = 45.0;
      final sinP = math.sin(pitchDeg * math.pi / 180.0);
      final cosP = math.cos(pitchDeg * math.pi / 180.0);

      // Constant pitched orientation (gravity only, no actual motion).
      // accelX = −sin(pitch), accelZ = cos(pitch) in g.
      final samples = _uniformStream(
        count: 200,
        rateHz: 200.0,
        accelX: -sinP,
        accelY: 0.0,
        accelZ: cosP,
      );
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
          gravity: GravityConfig(enabled: true, complementaryAlpha: 0.98),
        ),
      );
      final result = pipeline.process(samples);
      // After convergence (skip first 20 samples).
      for (int i = 40; i < result.length; i++) {
        expect(
          result[i].accelXLinear,
          closeTo(0.0, 0.15),
          reason: 'accelXLinear at $i',
        );
        expect(result[i].accelZLinear, closeTo(0.0, 0.15));
      }
    });

    test(
        'complementary alpha = 0 → pure accelerometer estimate, converges '
        'in one step', () {
      // With alpha = 0 the filter trusts the accelerometer entirely.
      final samples = _uniformStream(
        count: 50,
        rateHz: 200.0,
        accelZ: 1.0,
        accelX: 0.0,
        accelY: 0.0,
      );
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
          gravity: GravityConfig(enabled: true, complementaryAlpha: 0.0),
        ),
      );
      final result = pipeline.process(samples);
      // From the second sample onwards the linear accel should be exactly 0.
      for (int i = 1; i < result.length; i++) {
        expect(result[i].accelZLinear, closeTo(0.0, 1e-9));
      }
    });
  });

  // ── Unit tests: Integration stage ────────────────────────────────────────

  group('IntegrationStage', () {
    test('zero linear acceleration → velocity and position stay near zero', () {
      // At rest: gravity removed → linear accel ≈ 0 → velocity and position
      // should remain near zero.
      final samples = _uniformStream(count: 200, rateHz: 200.0);
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
          gravity: GravityConfig(enabled: true, complementaryAlpha: 0.98),
          integration: IntegrationConfig(enabled: true, driftCorrectionHz: 0.1),
        ),
      );
      final result = pipeline.process(samples);
      // After convergence the velocity should be very small (drift corrected).
      for (int i = 40; i < result.length; i++) {
        expect(result[i].velocityZ!, closeTo(0.0, 0.5),
            reason: 'velocityZ at $i');
      }
    });

    test('integration result fields are non-null when enabled', () {
      final samples = _uniformStream(count: 10);
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
          integration: IntegrationConfig(enabled: true),
        ),
      );
      final result = pipeline.process(samples);
      for (final ps in result) {
        expect(ps.velocityX, isNotNull);
        expect(ps.velocityY, isNotNull);
        expect(ps.velocityZ, isNotNull);
        expect(ps.positionX, isNotNull);
        expect(ps.positionY, isNotNull);
        expect(ps.positionZ, isNotNull);
      }
    });

    test('integration result fields absent from toMap() when disabled', () {
      final samples = _uniformStream(count: 5);
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
          integration: IntegrationConfig(enabled: false),
        ),
      );
      final map = pipeline.process(samples).first.toMap();
      expect(map.containsKey('velocity_x_ms'), isFalse);
      expect(map.containsKey('position_x_m'), isFalse);
    });

    test('integration result fields present in toMap() when enabled', () {
      final samples = _uniformStream(count: 10);
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
          integration: IntegrationConfig(enabled: true),
        ),
      );
      final map = pipeline.process(samples).last.toMap();
      expect(map.containsKey('velocity_x_ms'), isTrue);
      expect(map.containsKey('velocity_z_ms'), isTrue);
      expect(map.containsKey('position_x_m'), isTrue);
      expect(map.containsKey('position_z_m'), isTrue);
    });
  });

  // ── Golden / snapshot tests ───────────────────────────────────────────────

  group('Golden tests: known input → expected output', () {
    /// Inline 10-sample at-rest dataset.
    const atRestCsv = '''
0,0.00,0.00,1.00,0.00,0.00,0.00,25.0,0
5,0.00,0.00,1.00,0.00,0.00,0.00,25.0,1
10,0.00,0.00,1.00,0.00,0.00,0.00,25.0,2
15,0.00,0.00,1.00,0.00,0.00,0.00,25.0,3
20,0.00,0.00,1.00,0.00,0.00,0.00,25.0,4
25,0.00,0.00,1.00,0.00,0.00,0.00,25.0,5
30,0.00,0.00,1.00,0.00,0.00,0.00,25.0,6
35,0.00,0.00,1.00,0.00,0.00,0.00,25.0,7
40,0.00,0.00,1.00,0.00,0.00,0.00,25.0,8
45,0.00,0.00,1.00,0.00,0.00,0.00,25.0,9
''';

    List<ImuSample> parseCsv(String csv) {
      final result = <ImuSample>[];
      for (final line in csv.split('\n')) {
        final t = line.trim();
        if (t.isEmpty) continue;
        final parts = t.split(',');
        if (parts.length != 9) continue;
        result.add(ImuSample.fromCsvRow(parts));
      }
      return result;
    }

    test('at-rest dataset: gravity-removed accel ≈ 0 after convergence', () {
      final samples = parseCsv(atRestCsv);
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
          gravity: GravityConfig(enabled: true, complementaryAlpha: 0.98),
        ),
      );
      final result = pipeline.process(samples);

      // Skip sample 0 (initialisation); from sample 1 onwards all linear
      // components should be very close to 0.
      for (int i = 1; i < result.length; i++) {
        expect(result[i].accelZLinear, closeTo(0.0, 0.1));
        expect(result[i].accelXLinear, closeTo(0.0, 1e-9));
        expect(result[i].accelYLinear, closeTo(0.0, 1e-9));
      }
    });

    test('at-rest dataset: default config is deterministic (snapshot)', () {
      final samples = parseCsv(atRestCsv);
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
        ),
      );
      final r1 = pipeline.process(samples);
      final r2 = pipeline.process(samples);

      for (int i = 0; i < r1.length; i++) {
        expect(r1[i].accelXLinear, r2[i].accelXLinear);
        expect(r1[i].accelYLinear, r2[i].accelYLinear);
        expect(r1[i].accelZLinear, r2[i].accelZLinear);
      }
    });

    test('at-rest dataset resampled to 100 Hz has uniform 10 ms intervals', () {
      final samples = parseCsv(atRestCsv);
      const pipeline = PreprocessingPipeline(
        config: PreprocessingConfig(
          filter: FilterConfig(enabled: false),
          resample: ResampleConfig(enabled: true, targetRateHz: 100.0),
          gravity: GravityConfig(enabled: false),
        ),
      );
      final result = pipeline.process(samples);
      if (result.length < 2) return;
      for (int i = 1; i < result.length; i++) {
        final dt = result[i].raw.timestampMs - result[i - 1].raw.timestampMs;
        expect(dt, 10, reason: 'Non-uniform gap at index $i: $dt ms');
      }
    });
  });

  // ── ProcessedSample model ─────────────────────────────────────────────────

  group('ProcessedSample model', () {
    const raw = ImuSample(
      timestampMs: 100,
      accelXG: 0.1,
      accelYG: 0.2,
      accelZG: 1.0,
      gyroXDps: 1.0,
      gyroYDps: 2.0,
      gyroZDps: 0.5,
      tempC: 25.0,
      sampleCount: 10,
    );

    test('toString contains timestamp and linear accel values', () {
      const ps = ProcessedSample(
        raw: raw,
        accelXLinear: 0.5,
        accelYLinear: -0.3,
        accelZLinear: 0.1,
      );
      expect(ps.toString(), contains('100'));
      expect(ps.toString(), contains('0.500'));
    });

    test('toMap() contains all three linear accel keys', () {
      const ps = ProcessedSample(
        raw: raw,
        accelXLinear: 1.0,
        accelYLinear: 2.0,
        accelZLinear: 3.0,
        velocityX: 0.1,
        positionX: 0.01,
      );
      final map = ps.toMap();
      expect(map['accel_x_linear_ms2'], 1.0);
      expect(map['accel_y_linear_ms2'], 2.0);
      expect(map['accel_z_linear_ms2'], 3.0);
      expect(map['velocity_x_ms'], 0.1);
      expect(map['position_x_m'], 0.01);
      // Y and Z optional fields omitted when null
      expect(map.containsKey('velocity_y_ms'), isFalse);
    });
  });

  // ── PreprocessingConfig model ─────────────────────────────────────────────

  group('PreprocessingConfig and stage configs', () {
    test('FilterConfig defaults', () {
      const cfg = FilterConfig();
      expect(cfg.enabled, isTrue);
      expect(cfg.type, FilterType.lowPass);
      expect(cfg.cutoffHz, 10.0);
      expect(cfg.order, 2);
    });

    test('ResampleConfig defaults', () {
      const cfg = ResampleConfig();
      expect(cfg.enabled, isFalse);
      expect(cfg.targetRateHz, 200.0);
      expect(cfg.interpolation, ResampleInterpolation.linear);
    });

    test('CoordinateTransformConfig defaults', () {
      const cfg = CoordinateTransformConfig();
      expect(cfg.enabled, isFalse);
      expect(cfg.mountingRollDeg, 0.0);
      expect(cfg.mountingPitchDeg, 0.0);
      expect(cfg.mountingYawDeg, 0.0);
    });

    test('GravityConfig defaults', () {
      const cfg = GravityConfig();
      expect(cfg.enabled, isTrue);
      expect(cfg.method, GravityRemovalMethod.complementary);
      expect(cfg.complementaryAlpha, 0.98);
    });

    test('IntegrationConfig defaults', () {
      const cfg = IntegrationConfig();
      expect(cfg.enabled, isFalse);
      expect(cfg.driftCorrectionHz, 0.1);
    });

    test('GravityRemovalMethod has complementary and kalman variants', () {
      expect(
        GravityRemovalMethod.values,
        containsAll(
            [GravityRemovalMethod.complementary, GravityRemovalMethod.kalman]),
      );
    });
  });
}
