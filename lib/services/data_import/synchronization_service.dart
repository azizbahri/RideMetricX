import 'dart:math' as math;

import '../../models/imu_sample.dart';
import '../../models/sync_result.dart';

/// Aligns a front and rear IMU sample stream so that they share a common time
/// reference.
///
/// Two modes are supported:
/// - **Manual** ([alignManual]): the caller provides the exact offset in
///   milliseconds.
/// - **Auto** ([alignAuto]): the offset is computed by maximising the
///   normalised cross-correlation of the [ImuSample.accelZG] channel.
///
/// Both methods return a [SyncResult] containing the trimmed, aligned streams,
/// the applied [SyncResult.offsetMs], and a [SyncResult.correlationCoefficient]
/// quality metric.  The result's [SyncResult.toMap] method serialises all
/// synchronisation parameters for reproducibility.
///
/// ## Offset convention
/// [SyncResult.offsetMs] > 0 means the front sensor started that many
/// milliseconds *after* the rear sensor (rear was already recording).
/// This matches the SessionMetadata.syncOffsetMs convention.
class SynchronizationService {
  /// Nominal sampling rate in Hz used to convert between sample lag and
  /// millisecond offset.  Must be positive.
  final double sampleRateHz;

  const SynchronizationService({this.sampleRateHz = 200.0});

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Aligns [front] and [rear] using the caller-supplied [offsetMs].
  ///
  /// The rear stream's timestamps are shifted by −[offsetMs] to bring them
  /// into the front stream's time frame, then both streams are trimmed to
  /// their overlapping interval.
  ///
  /// Returns a [SyncResult] with [SyncMode.manual] and the Pearson
  /// correlation of the aligned [ImuSample.accelZG] channels.
  ///
  /// **Note:** if [offsetMs] is not an exact multiple of the nominal sample
  /// period (`1000 / sampleRateHz` ms), the two resulting aligned lists may
  /// have different lengths and non-matching per-index timestamps because each
  /// stream is clipped independently.  In that case the returned
  /// [SyncResult.correlationCoefficient] is still computed by pairing elements
  /// at the same index, which may not reflect true time-aligned pairs.  For
  /// best results pass an offset that is a multiple of the sample period (e.g.
  /// multiples of 5 ms at 200 Hz).
  SyncResult alignManual(
    List<ImuSample> front,
    List<ImuSample> rear,
    int offsetMs,
  ) {
    final (frontAligned, rearAligned) = _applyOffsetAndClip(
      front,
      rear,
      offsetMs,
    );
    final corr = _pearsonCorrelation(
      frontAligned.map((s) => s.accelZG).toList(),
      rearAligned.map((s) => s.accelZG).toList(),
    );
    return SyncResult(
      frontAligned: List.unmodifiable(frontAligned),
      rearAligned: List.unmodifiable(rearAligned),
      offsetMs: offsetMs,
      correlationCoefficient: corr,
      mode: SyncMode.manual,
    );
  }

  /// Aligns [front] and [rear] by searching for the offset that maximises the
  /// cross-correlation of the [ImuSample.accelZG] channel.
  ///
  /// The search range is ±[maxSearchMs] milliseconds (default 500 ms).
  /// Resolution equals one nominal sample period
  /// (`1000 / sampleRateHz` ms, e.g. 5 ms at 200 Hz).
  ///
  /// Returns a [SyncResult] with [SyncMode.auto] and the Pearson correlation
  /// at the best-found offset.
  SyncResult alignAuto(
    List<ImuSample> front,
    List<ImuSample> rear, {
    int maxSearchMs = 500,
  }) {
    final bestOffsetMs = _findBestOffsetMs(front, rear, maxSearchMs);
    final (frontAligned, rearAligned) = _applyOffsetAndClip(
      front,
      rear,
      bestOffsetMs,
    );
    final corr = _pearsonCorrelation(
      frontAligned.map((s) => s.accelZG).toList(),
      rearAligned.map((s) => s.accelZG).toList(),
    );
    return SyncResult(
      frontAligned: List.unmodifiable(frontAligned),
      rearAligned: List.unmodifiable(rearAligned),
      offsetMs: bestOffsetMs,
      correlationCoefficient: corr,
      mode: SyncMode.auto,
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Nominal sample period in milliseconds, rounded to the nearest integer.
  int get _nominalPeriodMs => math.max(1, (1000.0 / sampleRateHz).round());

  /// Finds the offset (in ms) that maximises the Pearson cross-correlation of
  /// the [ImuSample.accelZG] signals within a ±[maxSearchMs] search window.
  ///
  /// Offset convention: positive value → front started *after* rear.
  ///
  /// **Limitation:** the search treats both streams as uniform-sample arrays
  /// indexed by position, using [sampleRateHz] as the nominal rate to convert
  /// between sample lags and millisecond offsets.  If either stream has
  /// timestamp jitter or gaps the index-based cross-correlation may not
  /// correspond exactly to the timestamp-based clipping performed by
  /// [_applyOffsetAndClip].  This method is accurate for streams that were
  /// recorded at a steady rate close to [sampleRateHz].
  int _findBestOffsetMs(
    List<ImuSample> front,
    List<ImuSample> rear,
    int maxSearchMs,
  ) {
    if (front.isEmpty || rear.isEmpty) return 0;

    final frontZ = front.map((s) => s.accelZG).toList();
    final rearZ = rear.map((s) => s.accelZG).toList();

    final maxLagSamples = (maxSearchMs / _nominalPeriodMs).round();

    double bestCorr = double.negativeInfinity;
    int bestLag = 0; // in samples; positive → front leads rear

    for (int lag = -maxLagSamples; lag <= maxLagSamples; lag++) {
      // For lag L the comparison windows are:
      //   a = front[max(0, L) .. N - max(0, -L) - 1]
      //   b = rear [max(0,-L) .. N - max(0,  L) - 1]
      // so that a[i] and b[i] correspond to the same relative position.
      final int frontStart = math.max(0, lag);
      final int rearStart = math.max(0, -lag);
      final int len = math.min(
        frontZ.length - frontStart,
        rearZ.length - rearStart,
      );
      if (len < 2) continue;

      // Use index-range overload to avoid allocating intermediate sublists on
      // every iteration (can be O(N*lag) allocations for long streams).
      final corr = _pearsonCorrelationRange(
        frontZ,
        frontStart,
        rearZ,
        rearStart,
        len,
      );
      if (corr > bestCorr) {
        bestCorr = corr;
        bestLag = lag;
      }
    }

    // Convert sample lag to ms offset using the offset convention:
    //   offsetMs > 0  means front started after rear (rear leads front).
    // When lag < 0 the best match was front[0..] aligned with rear[-lag..],
    // meaning rear had extra samples at the start, i.e. rear started earlier,
    // so offsetMs = -lag * period > 0.
    return -bestLag * _nominalPeriodMs;
  }

  /// Shifts the rear stream's timestamps by −[offsetMs], clips both streams
  /// to their overlapping time interval, and returns the pair.
  ///
  /// Rear sample timestamps in the returned list are expressed in the front
  /// stream's time frame (rear.t − offsetMs).
  (List<ImuSample>, List<ImuSample>) _applyOffsetAndClip(
    List<ImuSample> front,
    List<ImuSample> rear,
    int offsetMs,
  ) {
    if (front.isEmpty || rear.isEmpty) {
      return (
        List.unmodifiable(<ImuSample>[]),
        List.unmodifiable(<ImuSample>[])
      );
    }

    // Bring rear timestamps into the front reference frame.
    final rearShifted = rear
        .map(
          (s) => ImuSample(
            timestampMs: s.timestampMs - offsetMs,
            accelXG: s.accelXG,
            accelYG: s.accelYG,
            accelZG: s.accelZG,
            gyroXDps: s.gyroXDps,
            gyroYDps: s.gyroYDps,
            gyroZDps: s.gyroZDps,
            tempC: s.tempC,
            sampleCount: s.sampleCount,
          ),
        )
        .toList();

    // Determine the overlapping interval.
    final overlapStart =
        math.max(front.first.timestampMs, rearShifted.first.timestampMs);
    final overlapEnd =
        math.min(front.last.timestampMs, rearShifted.last.timestampMs);

    if (overlapStart > overlapEnd) {
      return (
        List.unmodifiable(<ImuSample>[]),
        List.unmodifiable(<ImuSample>[])
      );
    }

    final frontAligned = front
        .where(
          (s) => s.timestampMs >= overlapStart && s.timestampMs <= overlapEnd,
        )
        .toList();
    final rearAligned = rearShifted
        .where(
          (s) => s.timestampMs >= overlapStart && s.timestampMs <= overlapEnd,
        )
        .toList();

    return (frontAligned, rearAligned);
  }

  /// Computes the Pearson correlation coefficient between [a] and [b].
  ///
  /// Returns 0.0 when either list has fewer than two elements or when the
  /// standard deviation of either signal is zero.
  static double _pearsonCorrelation(List<double> a, List<double> b) {
    final n = math.min(a.length, b.length);
    if (n < 2) return 0.0;

    double sumA = 0.0;
    double sumB = 0.0;
    for (int i = 0; i < n; i++) {
      sumA += a[i];
      sumB += b[i];
    }
    final meanA = sumA / n;
    final meanB = sumB / n;

    double cov = 0.0;
    double varA = 0.0;
    double varB = 0.0;
    for (int i = 0; i < n; i++) {
      final da = a[i] - meanA;
      final db = b[i] - meanB;
      cov += da * db;
      varA += da * da;
      varB += db * db;
    }

    final denom = math.sqrt(varA * varB);
    if (denom == 0.0) return 0.0;
    return cov / denom;
  }

  /// Computes the Pearson correlation coefficient over index ranges within
  /// [a] and [b], reading [len] elements starting at [aStart] and [bStart]
  /// respectively.
  ///
  /// Avoids allocating intermediate sublists, making it safe to call from a
  /// tight loop.  Returns 0.0 when [len] < 2 or when the standard deviation
  /// of either slice is zero.
  static double _pearsonCorrelationRange(
    List<double> a,
    int aStart,
    List<double> b,
    int bStart,
    int len,
  ) {
    if (len < 2) return 0.0;

    double sumA = 0.0;
    double sumB = 0.0;
    for (int i = 0; i < len; i++) {
      sumA += a[aStart + i];
      sumB += b[bStart + i];
    }
    final meanA = sumA / len;
    final meanB = sumB / len;

    double cov = 0.0;
    double varA = 0.0;
    double varB = 0.0;
    for (int i = 0; i < len; i++) {
      final da = a[aStart + i] - meanA;
      final db = b[bStart + i] - meanB;
      cov += da * db;
      varA += da * da;
      varB += db * db;
    }

    final denom = math.sqrt(varA * varB);
    if (denom == 0.0) return 0.0;
    return cov / denom;
  }
}
