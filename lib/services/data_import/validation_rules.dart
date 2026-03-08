/// Configurable thresholds and toggles for [ValidationService].
///
/// All parameters have sensible defaults matching the FR-DC-004 hardware
/// specification (200 Hz IMU, ±16 g accelerometer, ±2000 dps gyroscope).
class ValidationRules {
  // ── Timestamp checks ──────────────────────────────────────────────────────

  /// Maximum allowed gap between consecutive sample timestamps (ms).
  ///
  /// A gap larger than this value generates a [ValidationWarning].
  /// Defaults to 50 ms (10× the nominal 5 ms period at 200 Hz).
  final int maxTimestampGapMs;

  // ── Sample-rate tolerance ─────────────────────────────────────────────────

  /// Expected (nominal) sample rate in Hz.
  ///
  /// Used to compute the allowed deviation band.
  /// Defaults to 200 Hz (FR-DC-001).
  final double expectedSampleRateHz;

  /// Fractional tolerance on [expectedSampleRateHz] (0–1).
  ///
  /// A rate outside `expectedSampleRateHz ± tolerance × expectedSampleRateHz`
  /// generates a [ValidationWarning].  Defaults to 0.05 (5%).
  final double sampleRateTolerance;

  // ── Accelerometer range ───────────────────────────────────────────────────

  /// Minimum valid accelerometer reading in g.  Defaults to −16 g.
  final double accelMinG;

  /// Maximum valid accelerometer reading in g.  Defaults to +16 g.
  final double accelMaxG;

  // ── Gyroscope range ───────────────────────────────────────────────────────

  /// Minimum valid gyroscope reading in deg/s.  Defaults to −2000 dps.
  final double gyroMinDps;

  /// Maximum valid gyroscope reading in deg/s.  Defaults to +2000 dps.
  final double gyroMaxDps;

  // ── Temperature range ─────────────────────────────────────────────────────

  /// Minimum valid board temperature in °C.  Defaults to −40 °C.
  final double tempMinC;

  /// Maximum valid board temperature in °C.  Defaults to +85 °C.
  final double tempMaxC;

  // ── Outlier detection ─────────────────────────────────────────────────────

  /// Number of standard deviations beyond which a sample is considered an
  /// outlier.  Defaults to 5.0 (5 σ).
  final double outlierSigmaThreshold;

  // ── Stuck-sensor (constant signal) detection ──────────────────────────────

  /// Minimum number of consecutive identical values that triggers a
  /// stuck-sensor warning.  Defaults to 20 samples (100 ms at 200 Hz).
  final int stuckSensorWindowSamples;

  // ── Auto-correction ───────────────────────────────────────────────────────

  /// When `true`, [ValidationService] will linearly interpolate samples
  /// across detected gaps and record each correction in
  /// [ValidationReport.corrections].
  ///
  /// Defaults to `false`.
  final bool autoCorrectGaps;

  /// Maximum number of samples to insert when auto-correcting a single gap.
  ///
  /// If a gap would require more interpolated samples than this limit, the
  /// correction is truncated and a [ValidationWarning] is emitted for that
  /// gap.  This prevents runaway CPU/memory usage on corrupted data with
  /// large timestamp jumps (minutes/hours).
  ///
  /// Defaults to 1000 (5 seconds at 200 Hz).
  final int maxInterpolatedSamplesPerGap;

  const ValidationRules({
    this.maxTimestampGapMs = 50,
    this.expectedSampleRateHz = 200.0,
    this.sampleRateTolerance = 0.05,
    this.accelMinG = -16.0,
    this.accelMaxG = 16.0,
    this.gyroMinDps = -2000.0,
    this.gyroMaxDps = 2000.0,
    this.tempMinC = -40.0,
    this.tempMaxC = 85.0,
    this.outlierSigmaThreshold = 5.0,
    this.stuckSensorWindowSamples = 20,
    this.autoCorrectGaps = false,
    this.maxInterpolatedSamplesPerGap = 1000,
  });
}
