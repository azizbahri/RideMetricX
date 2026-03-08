import 'imu_sample.dart';

/// Synchronization mode used to align front and rear IMU streams.
enum SyncMode {
  /// Offset supplied directly by the caller.
  manual,

  /// Offset computed automatically via cross-correlation.
  auto,
}

/// Result of a front/rear IMU stream synchronization operation.
///
/// Contains the aligned sample streams, the applied offset, a quality metric,
/// and the synchronization mode.  Call [toMap] to persist the synchronization
/// parameters for reproducibility.
class SyncResult {
  /// Front IMU samples trimmed to the overlap window.
  ///
  /// Timestamps are in the front stream's original time frame.
  final List<ImuSample> frontAligned;

  /// Rear IMU samples trimmed to the overlap window, with timestamps
  /// shifted by [offsetMs] into the front stream's time frame.
  final List<ImuSample> rearAligned;

  /// Milliseconds that the front stream started *after* the rear stream.
  ///
  /// A positive value means the rear sensor was already recording when the
  /// front sensor started.  A negative value means the front sensor started
  /// first.  Matches the [SessionMetadata.syncOffsetMs] convention and can
  /// be persisted directly into session metadata for reproducibility.
  final int offsetMs;

  /// Pearson correlation coefficient of the aligned [accelZG] signals
  /// in the overlap window, in the range [−1, 1].
  ///
  /// Values close to 1.0 indicate a high-quality alignment.
  final double correlationCoefficient;

  /// Whether the offset was provided manually or computed automatically.
  final SyncMode mode;

  const SyncResult({
    required this.frontAligned,
    required this.rearAligned,
    required this.offsetMs,
    required this.correlationCoefficient,
    required this.mode,
  });

  /// Returns the synchronization parameters as a [Map] suitable for
  /// persistence (e.g., embedded into session metadata).
  ///
  /// The map contains:
  /// - `offset_ms` – applied offset in milliseconds.
  /// - `correlation_coefficient` – alignment quality metric.
  /// - `mode` – `"manual"` or `"auto"`.
  /// - `front_sample_count` – number of samples in [frontAligned].
  /// - `rear_sample_count` – number of samples in [rearAligned].
  Map<String, dynamic> toMap() => {
        'offset_ms': offsetMs,
        'correlation_coefficient': correlationCoefficient,
        'mode': mode.name,
        'front_sample_count': frontAligned.length,
        'rear_sample_count': rearAligned.length,
      };

  @override
  String toString() => 'SyncResult(mode=${mode.name}, offsetMs=$offsetMs, '
      'corr=${correlationCoefficient.toStringAsFixed(4)}, '
      'front=${frontAligned.length} samples, '
      'rear=${rearAligned.length} samples)';
}
