/// Configuration models for the IMU data preprocessing pipeline.
///
/// Use [PreprocessingConfig] to control which stages are active and to set
/// their parameters.  All fields have sensible defaults, so the pipeline can
/// be used with `const PreprocessingConfig()` out of the box.

// ── Enumerations ──────────────────────────────────────────────────────────────

/// Type of frequency-selective filter to apply to the IMU data.
enum FilterType {
  /// Attenuates frequencies *above* [FilterConfig.cutoffHz].
  lowPass,

  /// Attenuates frequencies *below* [FilterConfig.cutoffHz].
  highPass,
}

/// Interpolation method used when resampling to a target rate.
enum ResampleInterpolation {
  /// Piecewise-linear interpolation between adjacent samples.
  linear,
}

/// Algorithm used to estimate and remove the gravity component from the raw
/// acceleration signal.
enum GravityRemovalMethod {
  /// Complementary filter blending gyroscope integration with the
  /// accelerometer gravity estimate.
  ///
  /// Use [GravityConfig.complementaryAlpha] to tune the blend ratio.
  complementary,

  /// Extension point for a future Kalman-filter implementation.
  ///
  /// Currently falls back to the complementary filter.
  kalman,
}

// ── Stage configurations ──────────────────────────────────────────────────────

/// Configuration for the Butterworth IIR filter stage.
class FilterConfig {
  /// Whether the filter stage is active. Defaults to `true`.
  final bool enabled;

  /// Type of filter: [FilterType.lowPass] or [FilterType.highPass].
  final FilterType type;

  /// −3 dB cutoff frequency in Hz. Defaults to 10 Hz.
  final double cutoffHz;

  /// Filter order (1 or 2). Defaults to 2 (second-order Butterworth biquad).
  final int order;

  const FilterConfig({
    this.enabled = true,
    this.type = FilterType.lowPass,
    this.cutoffHz = 10.0,
    this.order = 2,
  });
}

/// Configuration for the resampling stage.
class ResampleConfig {
  /// Whether the resample stage is active. Defaults to `false`.
  final bool enabled;

  /// Target sample rate in Hz (e.g. 100, 200, or a custom value).
  /// Defaults to 200 Hz.
  final double targetRateHz;

  /// Interpolation method. Defaults to [ResampleInterpolation.linear].
  final ResampleInterpolation interpolation;

  const ResampleConfig({
    this.enabled = false,
    this.targetRateHz = 200.0,
    this.interpolation = ResampleInterpolation.linear,
  });
}

/// Configuration for the mounting-angle coordinate transform stage.
///
/// Compensates for the physical sensor mounting orientation so that the
/// processed data is expressed in the motorcycle body frame.
class CoordinateTransformConfig {
  /// Whether the coordinate transform stage is active. Defaults to `false`.
  final bool enabled;

  /// Sensor mounting roll angle in degrees (rotation about the X-axis).
  final double mountingRollDeg;

  /// Sensor mounting pitch angle in degrees (rotation about the Y-axis).
  final double mountingPitchDeg;

  /// Sensor mounting yaw angle in degrees (rotation about the Z-axis).
  final double mountingYawDeg;

  const CoordinateTransformConfig({
    this.enabled = false,
    this.mountingRollDeg = 0.0,
    this.mountingPitchDeg = 0.0,
    this.mountingYawDeg = 0.0,
  });
}

/// Configuration for the gravity-removal stage.
class GravityConfig {
  /// Whether the gravity-removal stage is active. Defaults to `true`.
  final bool enabled;

  /// Algorithm used to estimate the gravity direction.
  /// Defaults to [GravityRemovalMethod.complementary].
  final GravityRemovalMethod method;

  /// Complementary filter blending coefficient α ∈ (0, 1).
  ///
  /// Higher values trust the gyroscope more; lower values trust the
  /// accelerometer more.  Typical value: 0.98.
  final double complementaryAlpha;

  const GravityConfig({
    this.enabled = true,
    this.method = GravityRemovalMethod.complementary,
    this.complementaryAlpha = 0.98,
  });
}

/// Configuration for the optional velocity/position integration stage.
class IntegrationConfig {
  /// Whether the integration stage is active. Defaults to `false`.
  final bool enabled;

  /// High-pass cutoff frequency (Hz) applied to integrated velocity to
  /// suppress accumulating DC drift.  Typical value: 0.1 Hz.
  final double driftCorrectionHz;

  const IntegrationConfig({
    this.enabled = false,
    this.driftCorrectionHz = 0.1,
  });
}

// ── Top-level pipeline configuration ─────────────────────────────────────────

/// Top-level configuration for the [PreprocessingPipeline].
///
/// Stages are executed in this fixed order when [enabled]:
/// 1. **Resample** → uniform timeline at [ResampleConfig.targetRateHz].
/// 2. **Filter**   → noise/drift reduction via Butterworth IIR.
/// 3. **Coordinate transform** → sensor-to-motorcycle-frame alignment.
/// 4. **Gravity removal** → linear acceleration extraction via complementary
///    filter (or Kalman extension point).
/// 5. **Integration** → velocity and position from linear acceleration
///    (optional, disabled by default).
///
/// All stage configs have sensible defaults, so
/// `const PreprocessingConfig()` can be used directly.
class PreprocessingConfig {
  /// Butterworth filter settings.
  final FilterConfig filter;

  /// Resampling settings.
  final ResampleConfig resample;

  /// Mounting-angle coordinate transform settings.
  final CoordinateTransformConfig coordinateTransform;

  /// Gravity-removal settings.
  final GravityConfig gravity;

  /// Velocity/position integration settings.
  final IntegrationConfig integration;

  const PreprocessingConfig({
    this.filter = const FilterConfig(),
    this.resample = const ResampleConfig(),
    this.coordinateTransform = const CoordinateTransformConfig(),
    this.gravity = const GravityConfig(),
    this.integration = const IntegrationConfig(),
  });
}
