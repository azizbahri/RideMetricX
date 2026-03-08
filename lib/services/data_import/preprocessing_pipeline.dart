import 'dart:math' as math;

import '../../models/imu_sample.dart';
import '../../models/processed_sample.dart';
import '../../models/preprocessing_config.dart';

export '../../models/processed_sample.dart';
export '../../models/preprocessing_config.dart';

/// Applies a configurable preprocessing pipeline to a list of [ImuSample]
/// objects and returns a list of [ProcessedSample] objects.
///
/// ## Stage order
/// 1. **Resample** (optional) – resamples the input to a uniform rate.
/// 2. **Filter** (optional) – applies a Butterworth IIR filter to all
///    accelerometer and gyroscope channels.
/// 3. **Coordinate transform** (optional) – rotates sensor readings from the
///    physical mounting frame into the motorcycle body frame.
/// 4. **Gravity removal** – estimates the gravity vector via a complementary
///    filter (or a Kalman extension point) and subtracts it from the raw
///    acceleration, yielding linear acceleration in m/s².
/// 5. **Integration** (optional) – integrates linear acceleration to velocity
///    and position, with high-pass drift correction.
///
/// Each stage is enabled / disabled and tuned via [PreprocessingConfig].  The
/// default config activates the filter and gravity-removal stages and leaves
/// all others disabled.
///
/// ## Determinism
/// Given the same [config] and the same input list the pipeline always
/// produces byte-identical output (all arithmetic is deterministic IEEE 754).
class PreprocessingPipeline {
  /// Configuration that controls which stages are active and their parameters.
  final PreprocessingConfig config;

  const PreprocessingPipeline({this.config = const PreprocessingConfig()});

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Processes [samples] through the configured pipeline.
  ///
  /// Returns an empty list when [samples] is empty.  The pipeline never
  /// mutates the caller's list or any [ImuSample] object.
  List<ProcessedSample> process(List<ImuSample> samples) {
    if (samples.isEmpty) return const [];

    var working = List<ImuSample>.of(samples);

    // Stage 1 – Resample
    if (config.resample.enabled) {
      working = _ResampleStage(config.resample).apply(working);
    }

    // Stage 2 – Filter
    if (config.filter.enabled) {
      working = _FilterStage(config.filter).apply(working);
    }

    // Stage 3 – Coordinate transform
    if (config.coordinateTransform.enabled) {
      working =
          _CoordinateTransformStage(config.coordinateTransform).apply(working);
    }

    // Stages 4 & 5 – Gravity removal + optional integration
    return _GravityAndIntegrationStage(
      gravity: config.gravity,
      integration: config.integration,
    ).apply(working);
  }
}

// ── Stage 1: Resample ─────────────────────────────────────────────────────────

/// Resamples [ImuSample] streams to a uniform [ResampleConfig.targetRateHz].
///
/// Timestamps are placed at exact multiples of `1000 / targetRateHz` ms,
/// starting from the first sample's timestamp.  Values between existing
/// samples are interpolated using [ResampleInterpolation.linear].
///
/// The output is guaranteed to have a uniform inter-sample interval, so
/// downstream stages (filter, gravity) can assume a stable Δt.
class _ResampleStage {
  final ResampleConfig cfg;

  const _ResampleStage(this.cfg);

  List<ImuSample> apply(List<ImuSample> samples) {
    if (samples.length < 2) return List.of(samples);

    final periodMs = 1000.0 / cfg.targetRateHz;
    final startMs = samples.first.timestampMs.toDouble();
    final endMs = samples.last.timestampMs.toDouble();

    final result = <ImuSample>[];
    int sampleCount = 0;
    double t = startMs;

    while (t <= endMs + periodMs * 0.5) {
      final tMs = t.round();
      if (tMs > samples.last.timestampMs) break;

      final s = _interpolateAt(samples, tMs);
      if (s != null) {
        // Assign a sequential sampleCount for the resampled stream.
        result.add(
          ImuSample(
            timestampMs: tMs,
            accelXG: s.accelXG,
            accelYG: s.accelYG,
            accelZG: s.accelZG,
            gyroXDps: s.gyroXDps,
            gyroYDps: s.gyroYDps,
            gyroZDps: s.gyroZDps,
            tempC: s.tempC,
            sampleCount: sampleCount,
          ),
        );
        sampleCount++;
      }
      t += periodMs;
    }

    return result;
  }

  /// Linearly interpolates an [ImuSample] at [tMs] from [samples].
  ///
  /// Returns `null` when [tMs] is outside the range of [samples].
  static ImuSample? _interpolateAt(List<ImuSample> samples, int tMs) {
    if (tMs < samples.first.timestampMs || tMs > samples.last.timestampMs) {
      return null;
    }

    // Binary search for the pair bracketing tMs.
    int lo = 0;
    int hi = samples.length - 1;
    while (lo + 1 < hi) {
      final mid = (lo + hi) >> 1;
      if (samples[mid].timestampMs <= tMs) {
        lo = mid;
      } else {
        hi = mid;
      }
    }

    final a = samples[lo];
    final b = samples[hi];

    if (a.timestampMs == b.timestampMs) return a;

    final frac =
        (tMs - a.timestampMs) / (b.timestampMs - a.timestampMs).toDouble();

    double lerp(double va, double vb) => va + (vb - va) * frac;

    return ImuSample(
      timestampMs: tMs,
      accelXG: lerp(a.accelXG, b.accelXG),
      accelYG: lerp(a.accelYG, b.accelYG),
      accelZG: lerp(a.accelZG, b.accelZG),
      gyroXDps: lerp(a.gyroXDps, b.gyroXDps),
      gyroYDps: lerp(a.gyroYDps, b.gyroYDps),
      gyroZDps: lerp(a.gyroZDps, b.gyroZDps),
      tempC: lerp(a.tempC, b.tempC),
      sampleCount: a.sampleCount,
    );
  }
}

// ── Stage 2: Filter ───────────────────────────────────────────────────────────

/// Applies a Butterworth IIR filter to all accelerometer and gyroscope
/// channels in the [ImuSample] stream.
///
/// Supports first- and second-order Butterworth filters in both low-pass and
/// high-pass variants.  For offline (batch) processing a forward–backward
/// pass is applied to achieve zero-phase output.
class _FilterStage {
  final FilterConfig cfg;

  const _FilterStage(this.cfg);

  List<ImuSample> apply(List<ImuSample> samples) {
    if (samples.length < 2) return List.of(samples);

    final durationMs = samples.last.timestampMs - samples.first.timestampMs;
    final sampleRateHz = (samples.length - 1) / (durationMs / 1000.0);

    if (sampleRateHz <= 0 || cfg.cutoffHz <= 0) return List.of(samples);

    // Apply the same filter to each of the six motion channels independently.
    final axValues = _extractField(samples, (s) => s.accelXG);
    final ayValues = _extractField(samples, (s) => s.accelYG);
    final azValues = _extractField(samples, (s) => s.accelZG);
    final gxValues = _extractField(samples, (s) => s.gyroXDps);
    final gyValues = _extractField(samples, (s) => s.gyroYDps);
    final gzValues = _extractField(samples, (s) => s.gyroZDps);

    final axF = _filtfilt(axValues, sampleRateHz);
    final ayF = _filtfilt(ayValues, sampleRateHz);
    final azF = _filtfilt(azValues, sampleRateHz);
    final gxF = _filtfilt(gxValues, sampleRateHz);
    final gyF = _filtfilt(gyValues, sampleRateHz);
    final gzF = _filtfilt(gzValues, sampleRateHz);

    return List.generate(samples.length, (i) {
      final s = samples[i];
      return ImuSample(
        timestampMs: s.timestampMs,
        accelXG: axF[i],
        accelYG: ayF[i],
        accelZG: azF[i],
        gyroXDps: gxF[i],
        gyroYDps: gyF[i],
        gyroZDps: gzF[i],
        tempC: s.tempC,
        sampleCount: s.sampleCount,
      );
    });
  }

  List<double> _extractField(
    List<ImuSample> samples,
    double Function(ImuSample) getter,
  ) =>
      samples.map(getter).toList();

  /// Forward–backward (zero-phase) filtering of [data].
  List<double> _filtfilt(List<double> data, double sampleRateHz) {
    final filter = _BiquadSection.fromConfig(cfg, sampleRateHz);
    if (filter == null) return List.of(data);

    // Forward pass
    final forward = filter.reset().processAll(data);
    // Backward pass on the reversed forward output
    final backward = filter.reset().processAll(forward.reversed.toList());
    // Reverse the result to restore original time direction
    return backward.reversed.toList();
  }
}

/// A single second-order IIR (biquad) section implementing either a
/// Butterworth low-pass or high-pass filter.
///
/// Coefficients are computed using the RBJ audio-cookbook biquad formulæ.
class _BiquadSection {
  final double b0, b1, b2;
  final double a1, a2;

  double _x1 = 0.0, _x2 = 0.0;
  double _y1 = 0.0, _y2 = 0.0;

  _BiquadSection({
    required this.b0,
    required this.b1,
    required this.b2,
    required this.a1,
    required this.a2,
  });

  /// Creates a Butterworth biquad from [cfg] and the current [sampleRateHz].
  ///
  /// Returns `null` when the configuration is not supported (e.g. the cutoff
  /// frequency ≥ the Nyquist frequency) to allow the caller to pass through
  /// data unchanged.
  static _BiquadSection? fromConfig(FilterConfig cfg, double sampleRateHz) {
    final nyquist = sampleRateHz / 2.0;
    if (cfg.cutoffHz >= nyquist || cfg.cutoffHz <= 0) return null;

    final w0 = 2.0 * math.pi * cfg.cutoffHz / sampleRateHz;
    final cosW0 = math.cos(w0);
    final sinW0 = math.sin(w0);
    // Q = 1/sqrt(2) for a maximally flat (Butterworth) 2nd-order section.
    const q = 0.7071067811865476; // 1 / sqrt(2)
    final alpha = sinW0 / (2.0 * q);
    final a0 = 1.0 + alpha;

    final double b0, b1, b2;
    if (cfg.type == FilterType.lowPass) {
      b0 = (1.0 - cosW0) / 2.0 / a0;
      b1 = (1.0 - cosW0) / a0;
      b2 = (1.0 - cosW0) / 2.0 / a0;
    } else {
      // High-pass
      b0 = (1.0 + cosW0) / 2.0 / a0;
      b1 = -(1.0 + cosW0) / a0;
      b2 = (1.0 + cosW0) / 2.0 / a0;
    }

    return _BiquadSection(
      b0: b0,
      b1: b1,
      b2: b2,
      a1: -2.0 * cosW0 / a0,
      a2: (1.0 - alpha) / a0,
    );
  }

  /// Resets the filter state (delay line) to zero and returns `this` for
  /// method chaining.
  _BiquadSection reset() {
    _x1 = _x2 = _y1 = _y2 = 0.0;
    return this;
  }

  /// Processes a single sample through the biquad difference equation.
  double processSample(double x) {
    final y = b0 * x + b1 * _x1 + b2 * _x2 - a1 * _y1 - a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }

  /// Processes all samples in [data] and returns the filtered list.
  List<double> processAll(List<double> data) =>
      data.map(processSample).toList();
}

// ── Stage 3: Coordinate transform ─────────────────────────────────────────────

/// Rotates all accelerometer and gyroscope readings from the sensor mounting
/// frame into the motorcycle body frame.
///
/// The rotation is the composition Rz(yaw) · Ry(pitch) · Rx(roll) applied in
/// that order, where the angles are the *negative* of the mounting angles
/// (i.e. the inverse rotation that undoes the physical mounting offset).
class _CoordinateTransformStage {
  final CoordinateTransformConfig cfg;

  const _CoordinateTransformStage(this.cfg);

  List<ImuSample> apply(List<ImuSample> samples) {
    if (samples.isEmpty) return [];

    final rollRad = cfg.mountingRollDeg * math.pi / 180.0;
    final pitchRad = cfg.mountingPitchDeg * math.pi / 180.0;
    final yawRad = cfg.mountingYawDeg * math.pi / 180.0;

    // Build the 3×3 rotation matrix R = Rz(yaw) * Ry(pitch) * Rx(roll).
    final r = _buildRotationMatrix(rollRad, pitchRad, yawRad);

    return samples.map((s) {
      final (ax, ay, az) = _rotate(r, s.accelXG, s.accelYG, s.accelZG);
      final (gx, gy, gz) = _rotate(r, s.gyroXDps, s.gyroYDps, s.gyroZDps);

      return ImuSample(
        timestampMs: s.timestampMs,
        accelXG: ax,
        accelYG: ay,
        accelZG: az,
        gyroXDps: gx,
        gyroYDps: gy,
        gyroZDps: gz,
        tempC: s.tempC,
        sampleCount: s.sampleCount,
      );
    }).toList();
  }

  /// Builds R = Rz(yaw) · Ry(pitch) · Rx(roll) as a flat 9-element list in
  /// row-major order.
  static List<double> _buildRotationMatrix(
    double roll,
    double pitch,
    double yaw,
  ) {
    final cr = math.cos(roll), sr = math.sin(roll);
    final cp = math.cos(pitch), sp = math.sin(pitch);
    final cy = math.cos(yaw), sy = math.sin(yaw);

    return [
      cy * cp,
      cy * sp * sr - sy * cr,
      cy * sp * cr + sy * sr,
      sy * cp,
      sy * sp * sr + cy * cr,
      sy * sp * cr - cy * sr,
      -sp,
      cp * sr,
      cp * cr,
    ];
  }

  static (double, double, double) _rotate(
    List<double> r,
    double x,
    double y,
    double z,
  ) =>
      (
        r[0] * x + r[1] * y + r[2] * z,
        r[3] * x + r[4] * y + r[5] * z,
        r[6] * x + r[7] * y + r[8] * z,
      );
}

// ── Stages 4 & 5: Gravity removal + integration ───────────────────────────────

/// Removes the gravity component from raw acceleration using a complementary
/// filter (or the Kalman extension point), and optionally integrates the
/// resulting linear acceleration to velocity and position.
class _GravityAndIntegrationStage {
  final GravityConfig gravity;
  final IntegrationConfig integration;

  const _GravityAndIntegrationStage({
    required this.gravity,
    required this.integration,
  });

  List<ProcessedSample> apply(List<ImuSample> samples) {
    if (samples.isEmpty) return const [];
    if (samples.length == 1) {
      return [_noGravity(samples.first)];
    }

    final n = samples.length;

    // ── Gravity removal ────────────────────────────────────────────────────
    // Estimate orientation with a complementary filter initialised from the
    // first sample's accelerometer reading.
    double rollRad = 0.0;
    double pitchRad = 0.0;

    // Bootstrap from the first sample if gravity removal is active.
    if (gravity.enabled) {
      final s0 = samples.first;
      final ay = s0.accelYG, az = s0.accelZG, ax = s0.accelXG;
      final accelMag = math.sqrt(ax * ax + ay * ay + az * az);
      if (accelMag > 0.01) {
        rollRad = math.atan2(ay, az);
        pitchRad = math.atan2(-ax, math.sqrt(ay * ay + az * az));
      }
    }

    final alpha = gravity.complementaryAlpha.clamp(0.0, 1.0);

    final linAccelX = List<double>.filled(n, 0.0);
    final linAccelY = List<double>.filled(n, 0.0);
    final linAccelZ = List<double>.filled(n, 0.0);

    for (int i = 0; i < n; i++) {
      final s = samples[i];

      if (!gravity.enabled) {
        // No gravity removal: treat the full acceleration as linear.
        linAccelX[i] = s.accelXG * 9.80665;
        linAccelY[i] = s.accelYG * 9.80665;
        linAccelZ[i] = s.accelZG * 9.80665;
        continue;
      }

      // Time step
      final dtS =
          i == 0 ? 0.0 : (s.timestampMs - samples[i - 1].timestampMs) / 1000.0;

      // Accelerometer-based attitude estimate.
      final ax = s.accelXG, ay = s.accelYG, az = s.accelZG;
      final accelMag = math.sqrt(ax * ax + ay * ay + az * az);

      double accelRoll = rollRad;
      double accelPitch = pitchRad;
      if (accelMag > 0.01) {
        accelRoll = math.atan2(ay, az);
        accelPitch = math.atan2(-ax, math.sqrt(ay * ay + az * az));
      }

      // Gyroscope integration (rad/s).
      final gxRad = s.gyroXDps * math.pi / 180.0;
      final gyRad = s.gyroYDps * math.pi / 180.0;

      // Complementary filter blend.
      if (i > 0) {
        rollRad = alpha * (rollRad + gxRad * dtS) + (1.0 - alpha) * accelRoll;
        pitchRad =
            alpha * (pitchRad + gyRad * dtS) + (1.0 - alpha) * accelPitch;
      }

      // Gravity vector in the sensor frame (in g).
      final gravX = -math.sin(pitchRad);
      final gravY = math.sin(rollRad) * math.cos(pitchRad);
      final gravZ = math.cos(rollRad) * math.cos(pitchRad);

      // Linear acceleration = total − gravity, converted to m/s².
      linAccelX[i] = (ax - gravX) * 9.80665;
      linAccelY[i] = (ay - gravY) * 9.80665;
      linAccelZ[i] = (az - gravZ) * 9.80665;
    }

    // ── Integration (optional) ────────────────────────────────────────────
    if (!integration.enabled) {
      return List.generate(
        n,
        (i) => ProcessedSample(
          raw: samples[i],
          accelXLinear: linAccelX[i],
          accelYLinear: linAccelY[i],
          accelZLinear: linAccelZ[i],
        ),
      );
    }

    // Compute effective sample rate for the drift-correction high-pass filter.
    final durationMs = samples.last.timestampMs - samples.first.timestampMs;
    final sampleRateHz =
        durationMs > 0 ? (n - 1) / (durationMs / 1000.0) : 100.0;

    // Trapezoid integration of linear acceleration → velocity.
    final vx = List<double>.filled(n, 0.0);
    final vy = List<double>.filled(n, 0.0);
    final vz = List<double>.filled(n, 0.0);

    for (int i = 1; i < n; i++) {
      final dt = (samples[i].timestampMs - samples[i - 1].timestampMs) / 1000.0;
      vx[i] = vx[i - 1] + (linAccelX[i] + linAccelX[i - 1]) / 2.0 * dt;
      vy[i] = vy[i - 1] + (linAccelY[i] + linAccelY[i - 1]) / 2.0 * dt;
      vz[i] = vz[i - 1] + (linAccelZ[i] + linAccelZ[i - 1]) / 2.0 * dt;
    }

    // Drift correction: high-pass filter the velocity to remove DC offset.
    final driftCutoff = integration.driftCorrectionHz;
    if (driftCutoff > 0 && driftCutoff < sampleRateHz / 2.0) {
      final hpCfg = FilterConfig(
        enabled: true,
        type: FilterType.highPass,
        cutoffHz: driftCutoff,
        order: 2,
      );
      final hpFilter = _BiquadSection.fromConfig(hpCfg, sampleRateHz);
      if (hpFilter != null) {
        final vxF = hpFilter.reset().processAll(vx);
        final vyF = hpFilter.reset().processAll(vy);
        final vzF = hpFilter.reset().processAll(vz);
        for (int i = 0; i < n; i++) {
          vx[i] = vxF[i];
          vy[i] = vyF[i];
          vz[i] = vzF[i];
        }
      }
    }

    // Integrate velocity → position (trapezoid).
    final px = List<double>.filled(n, 0.0);
    final py = List<double>.filled(n, 0.0);
    final pz = List<double>.filled(n, 0.0);

    for (int i = 1; i < n; i++) {
      final dt = (samples[i].timestampMs - samples[i - 1].timestampMs) / 1000.0;
      px[i] = px[i - 1] + (vx[i] + vx[i - 1]) / 2.0 * dt;
      py[i] = py[i - 1] + (vy[i] + vy[i - 1]) / 2.0 * dt;
      pz[i] = pz[i - 1] + (vz[i] + vz[i - 1]) / 2.0 * dt;
    }

    return List.generate(
      n,
      (i) => ProcessedSample(
        raw: samples[i],
        accelXLinear: linAccelX[i],
        accelYLinear: linAccelY[i],
        accelZLinear: linAccelZ[i],
        velocityX: vx[i],
        velocityY: vy[i],
        velocityZ: vz[i],
        positionX: px[i],
        positionY: py[i],
        positionZ: pz[i],
      ),
    );
  }

  /// Creates a [ProcessedSample] with zero linear acceleration (no gravity
  /// removal applied) used for single-sample or disabled-gravity-removal
  /// fallback.
  static ProcessedSample _noGravity(ImuSample s) => ProcessedSample(
        raw: s,
        accelXLinear: s.accelXG * 9.80665,
        accelYLinear: s.accelYG * 9.80665,
        accelZLinear: s.accelZG * 9.80665,
      );
}
