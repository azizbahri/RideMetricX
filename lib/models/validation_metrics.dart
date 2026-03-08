/// Quality metrics computed over a validated telemetry stream.
class ValidationMetrics {
  /// Total number of samples in the stream.
  final int sampleCount;

  /// Duration of the recording in milliseconds
  /// (last timestamp − first timestamp).  Zero when [sampleCount] < 2.
  final int durationMs;

  /// Effective sample rate derived from the data (samples per second).
  ///
  /// Computed as `(sampleCount - 1) / (durationMs / 1000)`.
  /// Returns 0.0 when [durationMs] is zero.
  final double effectiveSampleRateHz;

  /// Total number of NaN or non-finite occurrences across all numeric fields
  /// in the stream.
  ///
  /// A single sample with multiple NaN fields contributes multiple counts.
  final int nanCount;

  /// Number of timestamp gaps that exceeded the configured threshold.
  final int gapCount;

  /// Number of samples flagged as statistical outliers (>5 σ by default).
  final int outlierCount;

  /// Number of fields flagged as having a constant (stuck) signal.
  final int stuckFieldCount;

  /// Number of samples that were automatically corrected (e.g. interpolated
  /// across gaps).  Zero when auto-correction is disabled.
  final int correctedCount;

  const ValidationMetrics({
    required this.sampleCount,
    required this.durationMs,
    required this.effectiveSampleRateHz,
    required this.nanCount,
    required this.gapCount,
    required this.outlierCount,
    required this.stuckFieldCount,
    required this.correctedCount,
  });

  /// A zero-valued metrics object used when the sample list is empty.
  static const empty = ValidationMetrics(
    sampleCount: 0,
    durationMs: 0,
    effectiveSampleRateHz: 0.0,
    nanCount: 0,
    gapCount: 0,
    outlierCount: 0,
    stuckFieldCount: 0,
    correctedCount: 0,
  );

  @override
  String toString() => 'ValidationMetrics(n=$sampleCount, dur=${durationMs}ms, '
      'rate=${effectiveSampleRateHz.toStringAsFixed(1)}Hz, '
      'nan=$nanCount, gaps=$gapCount, outliers=$outlierCount, '
      'stuck=$stuckFieldCount, corrected=$correctedCount)';
}
