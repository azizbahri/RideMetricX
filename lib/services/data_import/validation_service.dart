import 'dart:math' as math;

import '../../models/imu_sample.dart';
import '../../models/validation_error.dart';
import '../../models/validation_metrics.dart';
import '../../models/validation_report.dart';
import '../../models/validation_warning.dart';
import 'validation_rules.dart';

/// Validates a list of [ImuSample] objects and produces a [ValidationReport].
///
/// Checks performed (in order):
/// 1. **Empty stream** – emits an error if the list is empty.
/// 2. **NaN / non-finite values** – errors for each affected sample/field.
/// 3. **Monotonic timestamps** – errors when a timestamp does not increase.
/// 4. **Timestamp gaps** – warnings for gaps exceeding [ValidationRules.maxTimestampGapMs].
/// 5. **Per-field range checks** – warnings for values outside configured bounds.
/// 6. **Effective sample-rate** – warning if rate deviates beyond tolerance.
/// 7. **Outlier detection (>N σ)** – warnings per field.
/// 8. **Stuck-sensor detection** – warnings for constant-signal fields.
/// 9. **Auto-correction** – optional linear interpolation across gaps
///    (only when [ValidationRules.autoCorrectGaps] is `true`).
class ValidationService {
  /// Rules controlling thresholds and optional auto-correction.
  final ValidationRules rules;

  const ValidationService({this.rules = const ValidationRules()});

  // ── Canonical IMU field accessors ─────────────────────────────────────────

  static const _numericFields = [
    'accel_x_g',
    'accel_y_g',
    'accel_z_g',
    'gyro_x_dps',
    'gyro_y_dps',
    'gyro_z_dps',
    'temp_c',
  ];

  static double _fieldValue(ImuSample s, String field) {
    switch (field) {
      case 'accel_x_g':
        return s.accelXG;
      case 'accel_y_g':
        return s.accelYG;
      case 'accel_z_g':
        return s.accelZG;
      case 'gyro_x_dps':
        return s.gyroXDps;
      case 'gyro_y_dps':
        return s.gyroYDps;
      case 'gyro_z_dps':
        return s.gyroZDps;
      case 'temp_c':
        return s.tempC;
      default:
        throw ArgumentError('Unknown field: $field');
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Validates [samples] and returns a [ValidationReport].
  ///
  /// If [ValidationRules.autoCorrectGaps] is `true`, the returned
  /// [ValidationReport.corrections] list describes each interpolated sample.
  /// Auto-correction is only attempted when there are no structural errors
  /// (e.g. non-monotonic timestamps), since interpolation requires ordering.
  /// [validate] never modifies the caller's list — it works on an internal copy.
  ValidationReport validate(List<ImuSample> samples) {
    final errors = <ValidationError>[];
    final warnings = <ValidationWarning>[];
    final corrections = <String>[];

    // ── 1. Empty stream ───────────────────────────────────────────────────
    if (samples.isEmpty) {
      errors.add(const ValidationError(
        message: 'Sample list is empty.',
      ));
      return ValidationReport(
        errors: errors,
        warnings: warnings,
        metrics: ValidationMetrics.empty,
        wasCorrected: false,
        corrections: corrections,
      );
    }

    // Work on a mutable copy so auto-correction does not mutate caller data.
    var workingSamples = List<ImuSample>.of(samples);

    // ── 2. NaN / non-finite checks ────────────────────────────────────────
    int nanCount = 0;
    for (int i = 0; i < workingSamples.length; i++) {
      final s = workingSamples[i];
      for (final field in _numericFields) {
        final v = _fieldValue(s, field);
        if (v.isNaN || v.isInfinite) {
          nanCount++;
          errors.add(ValidationError(
            message: 'Non-finite value (${v.isNaN ? 'NaN' : 'Inf'}) '
                'in field $field.',
            field: field,
            sampleIndex: i,
          ));
        }
      }
    }

    // ── 3. Monotonic timestamps ───────────────────────────────────────────
    for (int i = 1; i < workingSamples.length; i++) {
      final prev = workingSamples[i - 1].timestampMs;
      final curr = workingSamples[i].timestampMs;
      if (curr <= prev) {
        errors.add(ValidationError(
          message: 'Timestamp is not monotonically increasing: '
              'sample[$i]=$curr ms ≤ sample[${i - 1}]=$prev ms.',
          field: 'timestamp_ms',
          sampleIndex: i,
        ));
      }
    }

    // ── 4. Timestamp gaps ────────────────────────────────────────────────
    int gapCount = 0;
    for (int i = 1; i < workingSamples.length; i++) {
      final gap =
          workingSamples[i].timestampMs - workingSamples[i - 1].timestampMs;
      if (gap > rules.maxTimestampGapMs) {
        gapCount++;
        warnings.add(ValidationWarning(
          message: 'Timestamp gap of $gap ms between sample[${i - 1}] '
              'and sample[$i] exceeds threshold of '
              '${rules.maxTimestampGapMs} ms.',
          field: 'timestamp_ms',
          sampleIndex: i,
        ));
      }
    }

    // ── 5. Per-field range checks ─────────────────────────────────────────
    for (int i = 0; i < workingSamples.length; i++) {
      final s = workingSamples[i];
      _checkRange(warnings, i, 'accel_x_g', s.accelXG, rules.accelMinG,
          rules.accelMaxG);
      _checkRange(warnings, i, 'accel_y_g', s.accelYG, rules.accelMinG,
          rules.accelMaxG);
      _checkRange(warnings, i, 'accel_z_g', s.accelZG, rules.accelMinG,
          rules.accelMaxG);
      _checkRange(warnings, i, 'gyro_x_dps', s.gyroXDps, rules.gyroMinDps,
          rules.gyroMaxDps);
      _checkRange(warnings, i, 'gyro_y_dps', s.gyroYDps, rules.gyroMinDps,
          rules.gyroMaxDps);
      _checkRange(warnings, i, 'gyro_z_dps', s.gyroZDps, rules.gyroMinDps,
          rules.gyroMaxDps);
      _checkRange(
          warnings, i, 'temp_c', s.tempC, rules.tempMinC, rules.tempMaxC);
    }

    // ── 6. Effective sample-rate check ───────────────────────────────────
    final durationMs =
        workingSamples.last.timestampMs - workingSamples.first.timestampMs;
    double effectiveRateHz = 0.0;
    if (durationMs > 0) {
      effectiveRateHz = (workingSamples.length - 1) / (durationMs / 1000.0);
      final lowerBound =
          rules.expectedSampleRateHz * (1.0 - rules.sampleRateTolerance);
      final upperBound =
          rules.expectedSampleRateHz * (1.0 + rules.sampleRateTolerance);
      if (effectiveRateHz < lowerBound || effectiveRateHz > upperBound) {
        warnings.add(ValidationWarning(
          message: 'Effective sample rate '
              '${effectiveRateHz.toStringAsFixed(1)} Hz is outside the '
              'expected range '
              '[${lowerBound.toStringAsFixed(1)}, '
              '${upperBound.toStringAsFixed(1)}] Hz.',
        ));
      }
    }

    // ── 7. Outlier detection (> N σ) ─────────────────────────────────────
    int outlierCount = 0;
    for (final field in _numericFields) {
      final values = workingSamples
          .map((s) => _fieldValue(s, field))
          .where((v) => v.isFinite)
          .toList();
      if (values.length < 2) continue;

      final mean = values.reduce((a, b) => a + b) / values.length;
      final variance =
          values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
              values.length;
      final stdDev = math.sqrt(variance);

      if (stdDev == 0.0) continue; // Handled by stuck-sensor check.

      for (int i = 0; i < workingSamples.length; i++) {
        final v = _fieldValue(workingSamples[i], field);
        if (!v.isFinite) continue;
        final sigma = (v - mean).abs() / stdDev;
        if (sigma > rules.outlierSigmaThreshold) {
          outlierCount++;
          warnings.add(ValidationWarning(
            message: 'Outlier detected in $field: value=$v, '
                '${sigma.toStringAsFixed(1)} σ from mean '
                '(threshold=${rules.outlierSigmaThreshold} σ).',
            field: field,
            sampleIndex: i,
          ));
        }
      }
    }

    // ── 8. Stuck-sensor (constant signal) detection ───────────────────────
    int stuckFieldCount = 0;
    for (final field in _numericFields) {
      int runLength = 1;
      bool fieldFlagged = false;
      for (int i = 1; i < workingSamples.length && !fieldFlagged; i++) {
        final prev = _fieldValue(workingSamples[i - 1], field);
        final curr = _fieldValue(workingSamples[i], field);
        if (curr == prev) {
          runLength++;
          if (runLength >= rules.stuckSensorWindowSamples) {
            stuckFieldCount++;
            fieldFlagged = true;
            warnings.add(ValidationWarning(
              message: 'Constant (stuck) signal detected in $field: '
                  '$runLength consecutive identical values '
                  '(threshold=${rules.stuckSensorWindowSamples}).',
              field: field,
              sampleIndex: i - runLength + 1,
            ));
          }
        } else {
          runLength = 1;
        }
      }
    }

    // ── 9. Auto-correction: linear interpolation across gaps ─────────────
    bool wasCorrected = false;
    if (rules.autoCorrectGaps && errors.isEmpty) {
      // Only attempt correction when there are no structural errors (e.g.
      // non-monotonic timestamps), since interpolation requires ordering.
      final corrected = <ImuSample>[];
      corrected.add(workingSamples.first);

      for (int i = 1; i < workingSamples.length; i++) {
        final prev = workingSamples[i - 1];
        final curr = workingSamples[i];
        final gap = curr.timestampMs - prev.timestampMs;
        final nominalPeriodMs = (1000.0 / rules.expectedSampleRateHz).round();

        if (gap > rules.maxTimestampGapMs && nominalPeriodMs > 0) {
          // Insert linearly interpolated samples to fill the gap.
          int t = prev.timestampMs + nominalPeriodMs;
          int insertCount = 0;
          while (t < curr.timestampMs) {
            final frac = (t - prev.timestampMs) / gap.toDouble();
            final interp = _interpolate(
                prev, curr, t, frac, prev.sampleCount + insertCount + 1);
            corrected.add(interp);
            insertCount++;
            t += nominalPeriodMs;
          }
          if (insertCount > 0) {
            wasCorrected = true;
            corrections.add(
              'Interpolated $insertCount sample(s) across gap of $gap ms '
              'between sample[${i - 1}] (t=${prev.timestampMs} ms) '
              'and sample[$i] (t=${curr.timestampMs} ms).',
            );
          }
        }
        corrected.add(curr);
      }

      workingSamples = corrected;
    }

    // ── Metrics ───────────────────────────────────────────────────────────
    final finalDurationMs =
        workingSamples.last.timestampMs - workingSamples.first.timestampMs;
    final finalRateHz = finalDurationMs > 0
        ? (workingSamples.length - 1) / (finalDurationMs / 1000.0)
        : 0.0;

    final metrics = ValidationMetrics(
      sampleCount: workingSamples.length,
      durationMs: finalDurationMs,
      effectiveSampleRateHz: finalRateHz,
      nanCount: nanCount,
      gapCount: gapCount,
      outlierCount: outlierCount,
      stuckFieldCount: stuckFieldCount,
      correctedCount: wasCorrected ? workingSamples.length - samples.length : 0,
    );

    return ValidationReport(
      errors: List.unmodifiable(errors),
      warnings: List.unmodifiable(warnings),
      metrics: metrics,
      wasCorrected: wasCorrected,
      corrections: List.unmodifiable(corrections),
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _checkRange(
    List<ValidationWarning> warnings,
    int index,
    String field,
    double value,
    double min,
    double max,
  ) {
    if (!value.isFinite) return; // NaN/Inf caught elsewhere.
    if (value < min || value > max) {
      warnings.add(ValidationWarning(
        message: 'Field $field value $value is outside the allowed range '
            '[$min, $max].',
        field: field,
        sampleIndex: index,
      ));
    }
  }

  /// Linearly interpolates all IMU fields between [a] and [b] at fractional
  /// position [frac] ∈ [0, 1].
  static ImuSample _interpolate(
    ImuSample a,
    ImuSample b,
    int timestampMs,
    double frac,
    int sampleCount,
  ) {
    double lerp(double va, double vb) => va + (vb - va) * frac;

    return ImuSample(
      timestampMs: timestampMs,
      accelXG: lerp(a.accelXG, b.accelXG),
      accelYG: lerp(a.accelYG, b.accelYG),
      accelZG: lerp(a.accelZG, b.accelZG),
      gyroXDps: lerp(a.gyroXDps, b.gyroXDps),
      gyroYDps: lerp(a.gyroYDps, b.gyroYDps),
      gyroZDps: lerp(a.gyroZDps, b.gyroZDps),
      tempC: lerp(a.tempC, b.tempC),
      sampleCount: sampleCount,
    );
  }
}
