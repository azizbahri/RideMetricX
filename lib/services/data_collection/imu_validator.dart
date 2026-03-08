import '../../models/imu_sample.dart';
import '../../models/session_metadata.dart';

/// Physical sensor range limits derived from FR-DC-001.
class ImuLimits {
  /// Maximum accelerometer magnitude in g (hardware ±50 g range).
  static const double maxAccelG = 50.0;

  /// Maximum gyroscope rate magnitude in degrees/s (hardware ±2000 dps range).
  static const double maxGyroDps = 2000.0;

  /// Minimum plausible board temperature in °C (sensor operating margin).
  static const double minTempC = -40.0;

  /// Maximum plausible board temperature in °C.
  static const double maxTempC = 85.0;

  /// Maximum tolerated absolute sync offset between front/rear sensors (ms).
  /// Requirement: <100 ms over a 2-hour session (TC-DC-007).
  static const int maxSyncOffsetMs = 100;

  /// Fraction of the nominal interval used as per-sample jitter tolerance.
  /// 10 % gives headroom for individual timing noise while still catching
  /// a true rate mismatch (TC-DC-001 calls for ±2 % system-level accuracy).
  static const double samplingJitterFraction = 0.10;
}

/// Immutable result of a validation run.
class ValidationResult {
  /// `true` when no validation errors were detected.
  final bool isValid;

  /// Human-readable error messages (hard failures).
  final List<String> errors;

  /// Human-readable warning messages (non-fatal anomalies).
  final List<String> warnings;

  const ValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
  });

  @override
  String toString() =>
      'ValidationResult(isValid=$isValid, '
      'errors=${errors.length}, warnings=${warnings.length})';
}

/// Validates a list of [ImuSample] records against the data-collection schema.
///
/// Rules applied:
/// - Non-empty sample list
/// - Monotonically increasing [ImuSample.timestampMs]
/// - Sequential [ImuSample.sampleCount] (no dropped samples)
/// - Sensor value range checks (accel, gyro, temperature)
/// - Sampling-rate consistency (optional; enabled when [expectedRateHz] > 0)
///
/// Front/rear synchronisation is validated separately via [validateSync].
class ImuValidator {
  const ImuValidator._();

  /// Validates [samples] and returns a [ValidationResult].
  ///
  /// Pass a positive [expectedRateHz] (e.g., 200.0) to also check that the
  /// observed sample intervals are consistent with the nominal rate.
  static ValidationResult validate(
    List<ImuSample> samples, {
    double expectedRateHz = 0,
  }) {
    final errors = <String>[];
    final warnings = <String>[];

    if (samples.isEmpty) {
      errors.add('Sample list is empty.');
      return ValidationResult(
        isValid: false,
        errors: List.unmodifiable(errors),
        warnings: List.unmodifiable(warnings),
      );
    }

    _checkMonotonicTimestamps(samples, errors);
    _checkDroppedSamples(samples, errors);
    _checkRanges(samples, errors);

    if (expectedRateHz > 0) {
      _checkSamplingRate(samples, warnings, expectedRateHz: expectedRateHz);
    }

    return ValidationResult(
      isValid: errors.isEmpty,
      errors: List.unmodifiable(errors),
      warnings: List.unmodifiable(warnings),
    );
  }

  /// Validates that front and rear [SessionMetadata] are properly paired and
  /// that the sync offset does not exceed [ImuLimits.maxSyncOffsetMs] (TC-DC-007).
  static ValidationResult validateSync(
    SessionMetadata front,
    SessionMetadata rear,
  ) {
    final errors = <String>[];
    final warnings = <String>[];

    if (front.position != SensorPosition.front) {
      errors.add('First argument must have position == SensorPosition.front.');
    }
    if (rear.position != SensorPosition.rear) {
      errors.add('Second argument must have position == SensorPosition.rear.');
    }

    final offsetMs = front.syncOffsetMs.abs();
    if (offsetMs > ImuLimits.maxSyncOffsetMs) {
      errors.add(
        'Sync offset ${offsetMs}ms exceeds maximum '
        '${ImuLimits.maxSyncOffsetMs}ms (TC-DC-007).',
      );
    }

    return ValidationResult(
      isValid: errors.isEmpty,
      errors: List.unmodifiable(errors),
      warnings: List.unmodifiable(warnings),
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static void _checkMonotonicTimestamps(
    List<ImuSample> samples,
    List<String> errors,
  ) {
    for (int i = 1; i < samples.length; i++) {
      if (samples[i].timestampMs <= samples[i - 1].timestampMs) {
        errors.add(
          'Non-monotonic timestamp at index $i: '
          '${samples[i].timestampMs}ms ≤ ${samples[i - 1].timestampMs}ms.',
        );
      }
    }
  }

  static void _checkDroppedSamples(
    List<ImuSample> samples,
    List<String> errors,
  ) {
    for (int i = 1; i < samples.length; i++) {
      final expected = samples[i - 1].sampleCount + 1;
      if (samples[i].sampleCount != expected) {
        errors.add(
          'Dropped sample(s) between index ${i - 1} and $i: '
          'expected sample_count $expected, got ${samples[i].sampleCount}.',
        );
      }
    }
  }

  static void _checkRanges(
    List<ImuSample> samples,
    List<String> errors,
  ) {
    for (int i = 0; i < samples.length; i++) {
      final s = samples[i];

      if (s.accelXG.abs() > ImuLimits.maxAccelG ||
          s.accelYG.abs() > ImuLimits.maxAccelG ||
          s.accelZG.abs() > ImuLimits.maxAccelG) {
        errors.add(
          'Accelerometer out of range at index $i '
          '(t=${s.timestampMs}ms): max |${ImuLimits.maxAccelG}|g.',
        );
      }

      if (s.gyroXDps.abs() > ImuLimits.maxGyroDps ||
          s.gyroYDps.abs() > ImuLimits.maxGyroDps ||
          s.gyroZDps.abs() > ImuLimits.maxGyroDps) {
        errors.add(
          'Gyroscope out of range at index $i '
          '(t=${s.timestampMs}ms): max |${ImuLimits.maxGyroDps}|dps.',
        );
      }

      if (s.tempC < ImuLimits.minTempC || s.tempC > ImuLimits.maxTempC) {
        errors.add(
          'Temperature out of range at index $i '
          '(t=${s.timestampMs}ms): ${s.tempC}°C '
          '(valid ${ImuLimits.minTempC}..${ImuLimits.maxTempC}°C).',
        );
      }
    }
  }

  static void _checkSamplingRate(
    List<ImuSample> samples,
    List<String> warnings, {
    required double expectedRateHz,
  }) {
    if (samples.length < 2) return;

    final expectedIntervalMs = 1000.0 / expectedRateHz;
    final toleranceMs = expectedIntervalMs * ImuLimits.samplingJitterFraction;
    int jitterCount = 0;

    for (int i = 1; i < samples.length; i++) {
      final intervalMs =
          (samples[i].timestampMs - samples[i - 1].timestampMs).toDouble();
      if ((intervalMs - expectedIntervalMs).abs() > toleranceMs) {
        jitterCount++;
      }
    }

    if (jitterCount > 0) {
      final pct =
          (jitterCount / (samples.length - 1) * 100).toStringAsFixed(1);
      warnings.add(
        '$jitterCount/${samples.length - 1} intervals ($pct%) deviate '
        'by more than ${toleranceMs.toStringAsFixed(1)}ms from '
        'expected ${expectedIntervalMs.toStringAsFixed(1)}ms '
        '(${expectedRateHz}Hz).',
      );
    }
  }
}
