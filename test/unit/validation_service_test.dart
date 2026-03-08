// Tests for Data Import: ValidationService and Quality Metrics.
//
// Covers:
//   - ValidationError / ValidationWarning models
//   - ValidationMetrics model
//   - ValidationReport (passed / failed)
//   - ValidationRules configuration
//   - ValidationService:
//     * empty stream
//     * NaN / non-finite fields
//     * monotonic timestamp check
//     * timestamp gap detection
//     * per-field range checks
//     * effective sample-rate tolerance
//     * outlier detection (> N σ)
//     * stuck-sensor (constant signal) detection
//     * auto-correction (gap interpolation)
//   - Regression cases: empty stream, irregular intervals, NaN values

import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/models/imu_sample.dart';
import 'package:ride_metric_x/models/validation_error.dart';
import 'package:ride_metric_x/models/validation_metrics.dart';
import 'package:ride_metric_x/models/validation_report.dart';
import 'package:ride_metric_x/models/validation_warning.dart';
import 'package:ride_metric_x/services/data_import/validation_rules.dart';
import 'package:ride_metric_x/services/data_import/validation_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Builds a simple [ImuSample] with all fields set to [value].
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

/// Generates [count] regular samples at [rateHz] starting at t=0.
List<ImuSample> _regularStream(int count, {double rateHz = 200.0}) {
  final periodMs = (1000.0 / rateHz).round();
  return List.generate(
    count,
    (i) => _sample(timestampMs: i * periodMs, sampleCount: i),
  );
}

// ── ValidationError ───────────────────────────────────────────────────────────

void main() {
  group('ValidationError', () {
    test('toString contains message', () {
      const e = ValidationError(message: 'bad data');
      expect(e.toString(), contains('bad data'));
    });

    test('toString includes field when provided', () {
      const e = ValidationError(message: 'oops', field: 'accel_x_g');
      expect(e.toString(), contains('accel_x_g'));
    });

    test('toString includes sampleIndex when provided', () {
      const e = ValidationError(message: 'oops', sampleIndex: 5);
      expect(e.toString(), contains('5'));
    });

    test('equality is value-based', () {
      const a = ValidationError(message: 'msg', field: 'f', sampleIndex: 1);
      const b = ValidationError(message: 'msg', field: 'f', sampleIndex: 1);
      expect(a, equals(b));
    });

    test('inequality when fields differ', () {
      const a = ValidationError(message: 'msg', field: 'accel_x_g');
      const b = ValidationError(message: 'msg', field: 'gyro_x_dps');
      expect(a, isNot(equals(b)));
    });
  });

  // ── ValidationWarning ──────────────────────────────────────────────────────

  group('ValidationWarning', () {
    test('toString contains message', () {
      const w = ValidationWarning(message: 'suspicious');
      expect(w.toString(), contains('suspicious'));
    });

    test('toString includes field when provided', () {
      const w = ValidationWarning(message: 'oops', field: 'temp_c');
      expect(w.toString(), contains('temp_c'));
    });

    test('toString includes sampleIndex when provided', () {
      const w = ValidationWarning(message: 'oops', sampleIndex: 3);
      expect(w.toString(), contains('3'));
    });

    test('equality is value-based', () {
      const a = ValidationWarning(message: 'msg', field: 'f', sampleIndex: 2);
      const b = ValidationWarning(message: 'msg', field: 'f', sampleIndex: 2);
      expect(a, equals(b));
    });
  });

  // ── ValidationMetrics ──────────────────────────────────────────────────────

  group('ValidationMetrics', () {
    test('empty constant has zero values', () {
      expect(ValidationMetrics.empty.sampleCount, 0);
      expect(ValidationMetrics.empty.effectiveSampleRateHz, 0.0);
      expect(ValidationMetrics.empty.nanCount, 0);
    });

    test('toString is human-readable', () {
      const m = ValidationMetrics(
        sampleCount: 100,
        durationMs: 500,
        effectiveSampleRateHz: 198.0,
        nanCount: 0,
        gapCount: 0,
        outlierCount: 0,
        stuckFieldCount: 0,
        correctedCount: 0,
      );
      expect(m.toString(), contains('100'));
      expect(m.toString(), contains('198'));
    });
  });

  // ── ValidationReport ──────────────────────────────────────────────────────

  group('ValidationReport', () {
    test('passed is true when errors list is empty', () {
      const r = ValidationReport(
        errors: [],
        warnings: [],
        metrics: ValidationMetrics.empty,
        wasCorrected: false,
        corrections: [],
      );
      expect(r.passed, isTrue);
    });

    test('passed is false when there are errors', () {
      const r = ValidationReport(
        errors: [ValidationError(message: 'error')],
        warnings: [],
        metrics: ValidationMetrics.empty,
        wasCorrected: false,
        corrections: [],
      );
      expect(r.passed, isFalse);
    });

    test('toString contains PASS for passing report', () {
      const r = ValidationReport(
        errors: [],
        warnings: [],
        metrics: ValidationMetrics.empty,
        wasCorrected: false,
        corrections: [],
      );
      expect(r.toString(), contains('PASS'));
    });

    test('toString contains FAIL for failing report', () {
      const r = ValidationReport(
        errors: [ValidationError(message: 'bad')],
        warnings: [],
        metrics: ValidationMetrics.empty,
        wasCorrected: false,
        corrections: [],
      );
      expect(r.toString(), contains('FAIL'));
    });
  });

  // ── ValidationRules defaults ──────────────────────────────────────────────

  group('ValidationRules defaults', () {
    const rules = ValidationRules();

    test('default maxTimestampGapMs is 50', () {
      expect(rules.maxTimestampGapMs, 50);
    });

    test('default expectedSampleRateHz is 200', () {
      expect(rules.expectedSampleRateHz, 200.0);
    });

    test('default sampleRateTolerance is 0.05', () {
      expect(rules.sampleRateTolerance, closeTo(0.05, 1e-9));
    });

    test('default accel range is ±16 g', () {
      expect(rules.accelMinG, -16.0);
      expect(rules.accelMaxG, 16.0);
    });

    test('default gyro range is ±2000 dps', () {
      expect(rules.gyroMinDps, -2000.0);
      expect(rules.gyroMaxDps, 2000.0);
    });

    test('default temp range is −40 to +85 °C', () {
      expect(rules.tempMinC, -40.0);
      expect(rules.tempMaxC, 85.0);
    });

    test('default outlierSigmaThreshold is 5.0', () {
      expect(rules.outlierSigmaThreshold, 5.0);
    });

    test('default stuckSensorWindowSamples is 20', () {
      expect(rules.stuckSensorWindowSamples, 20);
    });

    test('autoCorrectGaps is false by default', () {
      expect(rules.autoCorrectGaps, isFalse);
    });
  });

  // ── ValidationService: empty stream ──────────────────────────────────────

  group('ValidationService – empty stream', () {
    const service = ValidationService();

    test('fails with one error on empty list', () {
      final report = service.validate([]);
      expect(report.passed, isFalse);
      expect(report.errors.length, 1);
    });

    test('error message mentions empty', () {
      final report = service.validate([]);
      expect(report.errors.first.message.toLowerCase(), contains('empty'));
    });

    test('metrics are all zero for empty stream', () {
      final report = service.validate([]);
      expect(report.metrics.sampleCount, 0);
      expect(report.metrics.durationMs, 0);
    });

    test('no warnings for empty stream', () {
      expect(service.validate([]).warnings, isEmpty);
    });

    test('empty stream returns unmodifiable lists', () {
      final report = service.validate([]);
      expect(
        () => report.errors.add(const ValidationError(message: 'x')),
        throwsUnsupportedError,
      );
      expect(
        () => report.warnings.add(const ValidationWarning(message: 'x')),
        throwsUnsupportedError,
      );
    });
  });

  // ── ValidationService: single sample ─────────────────────────────────────

  group('ValidationService – single valid sample', () {
    const service = ValidationService();
    final singleSample = [_sample(timestampMs: 0, sampleCount: 0)];

    test('passes', () {
      expect(service.validate(singleSample).passed, isTrue);
    });

    test('no warnings', () {
      expect(service.validate(singleSample).warnings, isEmpty);
    });

    test('metrics sampleCount is 1', () {
      expect(service.validate(singleSample).metrics.sampleCount, 1);
    });

    test('metrics durationMs is 0', () {
      expect(service.validate(singleSample).metrics.durationMs, 0);
    });
  });

  // ── ValidationService: NaN / non-finite checks ────────────────────────────

  group('ValidationService – NaN / non-finite', () {
    const service = ValidationService();

    test('fails when accel_x_g is NaN', () {
      final samples = [
        _sample(timestampMs: 0, accelX: double.nan),
      ];
      final report = service.validate(samples);
      expect(report.passed, isFalse);
      expect(
        report.errors.any((e) => e.field == 'accel_x_g'),
        isTrue,
      );
    });

    test('fails when gyro_z_dps is Infinity', () {
      final samples = [
        _sample(timestampMs: 0, gyroZ: double.infinity),
      ];
      final report = service.validate(samples);
      expect(report.passed, isFalse);
      expect(
        report.errors.any((e) => e.field == 'gyro_z_dps'),
        isTrue,
      );
    });

    test('counts nanCount correctly', () {
      final samples = [
        _sample(timestampMs: 0, accelX: double.nan, accelY: double.nan),
        _sample(timestampMs: 5),
      ];
      final report = service.validate(samples);
      expect(report.metrics.nanCount, 2);
    });

    test('includes sampleIndex in error', () {
      final samples = [
        _sample(timestampMs: 0),
        _sample(timestampMs: 5, accelZ: double.nan),
      ];
      final report = service.validate(samples);
      final err = report.errors.firstWhere((e) => e.field == 'accel_z_g');
      expect(err.sampleIndex, 1);
    });
  });

  // ── ValidationService: monotonic timestamps ───────────────────────────────

  group('ValidationService – monotonic timestamps', () {
    const service = ValidationService();

    test('fails when timestamps are equal', () {
      final samples = [
        _sample(timestampMs: 0),
        _sample(timestampMs: 0, sampleCount: 1),
      ];
      final report = service.validate(samples);
      expect(report.passed, isFalse);
      expect(
        report.errors.any((e) => e.field == 'timestamp_ms'),
        isTrue,
      );
    });

    test('fails when timestamps decrease', () {
      final samples = [
        _sample(timestampMs: 10),
        _sample(timestampMs: 5, sampleCount: 1),
      ];
      final report = service.validate(samples);
      expect(report.passed, isFalse);
    });

    test('reports correct sampleIndex for non-monotonic entry', () {
      final samples = [
        _sample(timestampMs: 0),
        _sample(timestampMs: 5, sampleCount: 1),
        _sample(timestampMs: 3, sampleCount: 2), // goes back
      ];
      final report = service.validate(samples);
      final err = report.errors.firstWhere(
        (e) => e.field == 'timestamp_ms',
      );
      expect(err.sampleIndex, 2);
    });

    test('passes for strictly increasing timestamps', () {
      final samples = [
        _sample(timestampMs: 0),
        _sample(timestampMs: 5, sampleCount: 1),
        _sample(timestampMs: 10, sampleCount: 2),
      ];
      expect(service.validate(samples).passed, isTrue);
    });
  });

  // ── ValidationService: timestamp gaps ────────────────────────────────────

  group('ValidationService – timestamp gaps', () {
    test('warns when gap exceeds threshold', () {
      const service = ValidationService(
        rules: ValidationRules(maxTimestampGapMs: 50),
      );
      final samples = [
        _sample(timestampMs: 0),
        _sample(timestampMs: 200, sampleCount: 1), // 200 ms gap
      ];
      final report = service.validate(samples);
      expect(report.warnings.any((w) => w.field == 'timestamp_ms'), isTrue);
    });

    test('does not warn when gap is within threshold', () {
      const service = ValidationService(
        rules: ValidationRules(maxTimestampGapMs: 50),
      );
      final samples = [
        _sample(timestampMs: 0),
        _sample(timestampMs: 5, sampleCount: 1),
      ];
      final report = service.validate(samples);
      expect(
        report.warnings.any((w) => w.field == 'timestamp_ms'),
        isFalse,
      );
    });

    test('gapCount is incremented for each gap', () {
      const service = ValidationService(
        rules: ValidationRules(maxTimestampGapMs: 20),
      );
      final samples = [
        _sample(timestampMs: 0),
        _sample(timestampMs: 100, sampleCount: 1),
        _sample(timestampMs: 200, sampleCount: 2),
      ];
      final report = service.validate(samples);
      expect(report.metrics.gapCount, 2);
    });

    test('stream still passes despite gap warnings', () {
      const service = ValidationService(
        rules: ValidationRules(maxTimestampGapMs: 10),
      );
      final samples = [
        _sample(timestampMs: 0),
        _sample(timestampMs: 50, sampleCount: 1),
      ];
      // Gaps are warnings, not errors.
      expect(service.validate(samples).passed, isTrue);
    });
  });

  // ── ValidationService: per-field range checks ─────────────────────────────

  group('ValidationService – range checks', () {
    const service = ValidationService(
      rules: ValidationRules(accelMinG: -2.0, accelMaxG: 2.0),
    );

    test('warns when accel_x_g exceeds max', () {
      final samples = [_sample(timestampMs: 0, accelX: 3.0)];
      final report = service.validate(samples);
      expect(report.warnings.any((w) => w.field == 'accel_x_g'), isTrue);
    });

    test('warns when accel_y_g is below min', () {
      final samples = [_sample(timestampMs: 0, accelY: -5.0)];
      final report = service.validate(samples);
      expect(report.warnings.any((w) => w.field == 'accel_y_g'), isTrue);
    });

    test('does not warn when value is within bounds', () {
      final samples = [_sample(timestampMs: 0, accelX: 1.5)];
      final report = service.validate(samples);
      expect(
        report.warnings.any((w) => w.field == 'accel_x_g'),
        isFalse,
      );
    });

    test('warns for temperature out of range', () {
      const svc = ValidationService(
        rules: ValidationRules(tempMinC: 0.0, tempMaxC: 60.0),
      );
      final samples = [_sample(timestampMs: 0, temp: 90.0)];
      expect(
        svc.validate(samples).warnings.any((w) => w.field == 'temp_c'),
        isTrue,
      );
    });

    test('range warning includes sampleIndex', () {
      final samples = [_sample(timestampMs: 0, accelX: 100.0)];
      final report = service.validate(samples);
      final w = report.warnings.firstWhere((w) => w.field == 'accel_x_g');
      expect(w.sampleIndex, 0);
    });
  });

  // ── ValidationService: sample-rate check ─────────────────────────────────

  group('ValidationService – sample-rate check', () {
    test('warns when effective rate is below lower bound', () {
      // Build a stream at 100 Hz when 200 Hz is expected.
      final samples = _regularStream(201, rateHz: 100.0);
      const service = ValidationService(
        rules: ValidationRules(
          expectedSampleRateHz: 200.0,
          sampleRateTolerance: 0.05,
          // Disable outlier / stuck checks to isolate rate warning.
          stuckSensorWindowSamples: 9999,
        ),
      );
      final report = service.validate(samples);
      expect(
        report.warnings
            .any((w) => w.message.toLowerCase().contains('sample rate')),
        isTrue,
      );
    });

    test('does not warn when rate is within tolerance', () {
      // 200 Hz stream is exactly on target.
      final samples = _regularStream(201);
      const service = ValidationService(
        rules: ValidationRules(
          expectedSampleRateHz: 200.0,
          sampleRateTolerance: 0.05,
          stuckSensorWindowSamples: 9999,
          outlierSigmaThreshold: 999.0,
        ),
      );
      final report = service.validate(samples);
      expect(
        report.warnings
            .any((w) => w.message.toLowerCase().contains('sample rate')),
        isFalse,
      );
    });
  });

  // ── ValidationService: outlier detection ─────────────────────────────────

  group('ValidationService – outlier detection', () {
    test('warns for a single extreme value beyond 5 σ', () {
      // 200 normal samples + 1 outlier at 100 g.
      final samples = [
        ...List.generate(
          200,
          (i) => _sample(timestampMs: i * 5, accelX: 0.0, sampleCount: i),
        ),
        _sample(timestampMs: 200 * 5, accelX: 100.0, sampleCount: 200),
      ];
      const service = ValidationService(
        rules: ValidationRules(
          accelMinG: -200.0,
          accelMaxG: 200.0,
          outlierSigmaThreshold: 5.0,
          stuckSensorWindowSamples: 9999,
        ),
      );
      final report = service.validate(samples);
      expect(
        report.warnings.any((w) =>
            w.field == 'accel_x_g' &&
            w.message.toLowerCase().contains('outlier')),
        isTrue,
      );
    });

    test('outlierCount incremented for each flagged sample', () {
      final samples = [
        ...List.generate(
          200,
          (i) => _sample(timestampMs: i * 5, accelX: 0.0, sampleCount: i),
        ),
        _sample(timestampMs: 200 * 5, accelX: 100.0, sampleCount: 200),
      ];
      const service = ValidationService(
        rules: ValidationRules(
          accelMinG: -200.0,
          accelMaxG: 200.0,
          outlierSigmaThreshold: 5.0,
          stuckSensorWindowSamples: 9999,
        ),
      );
      final report = service.validate(samples);
      expect(report.metrics.outlierCount, greaterThanOrEqualTo(1));
    });

    test('no outlier warning when value is within sigma threshold', () {
      final samples = List.generate(
        100,
        (i) => _sample(timestampMs: i * 5, accelX: i * 0.001, sampleCount: i),
      );
      const service = ValidationService(
        rules: ValidationRules(
          outlierSigmaThreshold: 5.0,
          stuckSensorWindowSamples: 9999,
        ),
      );
      final report = service.validate(samples);
      expect(
        report.warnings.any((w) =>
            w.field == 'accel_x_g' &&
            w.message.toLowerCase().contains('outlier')),
        isFalse,
      );
    });
  });

  // ── ValidationService: stuck-sensor detection ────────────────────────────

  group('ValidationService – stuck-sensor detection', () {
    test('warns when a field is constant for the full window', () {
      // All 25 accel_z_g values are identical → stuck sensor (window = 20).
      final samples = List.generate(
        25,
        (i) => _sample(timestampMs: i * 5, accelZ: 9.81, sampleCount: i),
      );
      const service = ValidationService(
        rules: ValidationRules(
          stuckSensorWindowSamples: 20,
          outlierSigmaThreshold: 999.0,
        ),
      );
      final report = service.validate(samples);
      expect(
        report.warnings.any((w) =>
            w.field == 'accel_z_g' &&
            w.message.toLowerCase().contains('stuck')),
        isTrue,
      );
    });

    test('does not warn when run is shorter than window', () {
      // Only 10 identical samples; window threshold is 20.
      final samples = List.generate(
        10,
        (i) => _sample(timestampMs: i * 5, accelZ: 1.0, sampleCount: i),
      );
      const service = ValidationService(
        rules: ValidationRules(
          stuckSensorWindowSamples: 20,
          outlierSigmaThreshold: 999.0,
        ),
      );
      final report = service.validate(samples);
      expect(
        report.warnings.any((w) =>
            w.field == 'accel_z_g' &&
            w.message.toLowerCase().contains('stuck')),
        isFalse,
      );
    });

    test('stuckFieldCount incremented once per field', () {
      final samples = List.generate(
        30,
        (i) => _sample(
            timestampMs: i * 5, accelX: 1.0, accelZ: 1.0, sampleCount: i),
      );
      const service = ValidationService(
        rules: ValidationRules(
          stuckSensorWindowSamples: 20,
          outlierSigmaThreshold: 999.0,
        ),
      );
      final report = service.validate(samples);
      // accel_x_g and accel_z_g both stuck.
      expect(report.metrics.stuckFieldCount, greaterThanOrEqualTo(2));
    });

    test('does not warn for stuck when values are non-finite', () {
      // A run of Inf values is already flagged as non-finite errors;
      // stuck-sensor detection should not additionally warn.
      final samples = List.generate(
        25,
        (i) => _sample(
            timestampMs: i * 5, accelX: double.infinity, sampleCount: i),
      );
      const service = ValidationService(
        rules: ValidationRules(
          stuckSensorWindowSamples: 20,
          outlierSigmaThreshold: 999.0,
        ),
      );
      final report = service.validate(samples);
      expect(
        report.warnings.any((w) =>
            w.field == 'accel_x_g' &&
            w.message.toLowerCase().contains('stuck')),
        isFalse,
      );
    });
  });

  // ── ValidationService: auto-correction ───────────────────────────────────

  group('ValidationService – auto-correction (gap interpolation)', () {
    const rules = ValidationRules(
      maxTimestampGapMs: 20,
      expectedSampleRateHz: 200.0,
      autoCorrectGaps: true,
      stuckSensorWindowSamples: 9999,
      outlierSigmaThreshold: 999.0,
    );
    const service = ValidationService(rules: rules);

    test('inserts interpolated samples to fill gap', () {
      // t=0 (sc=0) and t=100 ms (sc=20): gap = 100 ms; period = 5 ms.
      // sampleCount gap allows 19 insertions (sc 1..19).
      final samples = [
        _sample(timestampMs: 0, accelX: 0.0),
        _sample(timestampMs: 100, accelX: 1.0, sampleCount: 20),
      ];
      final report = service.validate(samples);
      expect(report.wasCorrected, isTrue);
      expect(report.metrics.correctedCount, greaterThan(0));
    });

    test('correction is logged in corrections list', () {
      final samples = [
        _sample(timestampMs: 0),
        _sample(timestampMs: 100, sampleCount: 20),
      ];
      final report = service.validate(samples);
      expect(report.corrections, isNotEmpty);
      expect(report.corrections.first.toLowerCase(), contains('interpolat'));
    });

    test('interpolated sample has intermediate timestamp', () {
      // t=0 (sc=0) → t=10 ms (sc=2): period=5ms, gap=10ms > threshold=4ms.
      // sampleCount gap allows 1 insertion (sc=1 < 2).
      final samples = [
        _sample(timestampMs: 0, accelX: 0.0),
        _sample(timestampMs: 10, accelX: 1.0, sampleCount: 2),
      ];
      const rulesSmall = ValidationRules(
        maxTimestampGapMs: 4,
        expectedSampleRateHz: 200.0, // period = 5 ms
        autoCorrectGaps: true,
        stuckSensorWindowSamples: 9999,
        outlierSigmaThreshold: 999.0,
      );
      const svcSmall = ValidationService(rules: rulesSmall);
      final report = svcSmall.validate(samples);
      // A 10 ms gap at 200 Hz should produce one interpolated sample at t=5.
      expect(report.wasCorrected, isTrue);
    });

    test('no correction when gap is within threshold', () {
      final samples = [
        _sample(timestampMs: 0),
        _sample(timestampMs: 5, sampleCount: 1), // 5 ms < 20 ms threshold
      ];
      final report = service.validate(samples);
      expect(report.wasCorrected, isFalse);
    });

    test('auto-correction disabled by default', () {
      const defaultService = ValidationService();
      final samples = [
        _sample(timestampMs: 0),
        _sample(timestampMs: 500, sampleCount: 100),
      ];
      final report = defaultService.validate(samples);
      expect(report.wasCorrected, isFalse);
    });

    test('original list is not mutated by correction', () {
      final samples = [
        _sample(timestampMs: 0),
        _sample(timestampMs: 100, sampleCount: 20),
      ];
      final originalLength = samples.length;
      service.validate(samples);
      expect(samples.length, originalLength);
    });

    test('inserted samples have monotonically increasing sampleCount', () {
      // sc=0 → sc=20 with 100 ms gap; inserted samples get sc 1..19.
      final samples = [
        _sample(timestampMs: 0, sampleCount: 0),
        _sample(timestampMs: 100, sampleCount: 20),
      ];
      final report = service.validate(samples);
      expect(report.wasCorrected, isTrue);
      // 2 original + 19 inserted = 21 total samples.
      expect(report.metrics.sampleCount, 21);
      expect(report.metrics.correctedCount, 19);
    });

    test(
        'emits warning when interpolation is capped by maxInterpolatedSamplesPerGap',
        () {
      const cappedRules = ValidationRules(
        maxTimestampGapMs: 20,
        expectedSampleRateHz: 200.0, // period = 5 ms
        autoCorrectGaps: true,
        maxInterpolatedSamplesPerGap: 2, // cap at 2 insertions
        stuckSensorWindowSamples: 9999,
        outlierSigmaThreshold: 999.0,
      );
      const cappedService = ValidationService(rules: cappedRules);
      // gap = 100 ms would need 19 insertions; cap limits to 2.
      final samples = [
        _sample(timestampMs: 0, sampleCount: 0),
        _sample(timestampMs: 100, sampleCount: 20),
      ];
      final report = cappedService.validate(samples);
      expect(
        report.warnings.any((w) =>
            w.field == 'timestamp_ms' &&
            w.message.toLowerCase().contains('capped')),
        isTrue,
      );
      expect(report.metrics.correctedCount, 2);
    });

    test('emits warning and skips interpolation when expectedSampleRateHz <= 0',
        () {
      const badRules = ValidationRules(
        maxTimestampGapMs: 20,
        expectedSampleRateHz: 0.0, // invalid
        autoCorrectGaps: true,
        stuckSensorWindowSamples: 9999,
        outlierSigmaThreshold: 999.0,
      );
      const badService = ValidationService(rules: badRules);
      final samples = [
        _sample(timestampMs: 0),
        _sample(timestampMs: 100, sampleCount: 20),
      ];
      final report = badService.validate(samples);
      expect(
        report.warnings.any((w) =>
            w.message.toLowerCase().contains('positive') ||
            w.message.toLowerCase().contains('expectedsamplerateHz')),
        isTrue,
      );
      expect(report.wasCorrected, isFalse);
    });
  });

  // ── ValidationService: metrics ────────────────────────────────────────────

  group('ValidationService – metrics', () {
    const service = ValidationService(
      rules: ValidationRules(
        stuckSensorWindowSamples: 9999,
        outlierSigmaThreshold: 999.0,
      ),
    );

    test('sampleCount matches input length', () {
      final samples = _regularStream(50);
      expect(service.validate(samples).metrics.sampleCount, 50);
    });

    test('durationMs is last minus first timestamp', () {
      final samples = _regularStream(11); // t=0..50 ms at 200 Hz
      final report = service.validate(samples);
      expect(report.metrics.durationMs, 50);
    });

    test('effectiveSampleRateHz is close to 200 Hz', () {
      final samples = _regularStream(201);
      final report = service.validate(samples);
      expect(report.metrics.effectiveSampleRateHz, closeTo(200.0, 1.0));
    });
  });

  // ── Regression: irregular intervals ──────────────────────────────────────

  group('Regression – irregular intervals', () {
    test('handles irregular but monotonic timestamps without error', () {
      final samples = [
        _sample(timestampMs: 0),
        _sample(timestampMs: 3, sampleCount: 1),
        _sample(timestampMs: 9, sampleCount: 2),
        _sample(timestampMs: 10, sampleCount: 3),
        _sample(timestampMs: 20, sampleCount: 4),
      ];
      const service = ValidationService(
        rules: ValidationRules(
          maxTimestampGapMs: 100,
          stuckSensorWindowSamples: 9999,
          outlierSigmaThreshold: 999.0,
        ),
      );
      expect(service.validate(samples).passed, isTrue);
    });
  });

  // ── Regression: all NaN stream ────────────────────────────────────────────

  group('Regression – NaN values', () {
    test('reports one error per NaN field per sample', () {
      final samples = [
        const ImuSample(
          timestampMs: 0,
          accelXG: double.nan,
          accelYG: double.nan,
          accelZG: double.nan,
          gyroXDps: double.nan,
          gyroYDps: double.nan,
          gyroZDps: double.nan,
          tempC: double.nan,
          sampleCount: 0,
        ),
      ];
      const service = ValidationService();
      final report = service.validate(samples);
      expect(report.passed, isFalse);
      // All numeric fields (accel x/y/z, gyro x/y/z, temp) are NaN.
      expect(report.metrics.nanCount, 7);
    });

    test('NaN sample does not trigger range warnings for that field', () {
      // Range check skips non-finite values to avoid duplicate noise.
      final samples = [
        _sample(timestampMs: 0, accelX: double.nan),
      ];
      const service = ValidationService();
      final report = service.validate(samples);
      // Should have NaN error but no range warning for accel_x_g.
      expect(
        report.warnings.any((w) => w.field == 'accel_x_g'),
        isFalse,
      );
    });
  });
}
