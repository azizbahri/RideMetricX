import '../../models/linkage_config.dart';

/// Suspension geometry and rear linkage ratio transforms (FR-SM-003).
///
/// Implements the wheel ↔ shock displacement / velocity / force conversions
/// required by the solver and metrics modules.  All transforms are driven by
/// the instantaneous linkage ratio r(x), where x is the current wheel
/// displacement in mm.
///
/// **Linkage models** (see [LinkageConfig]):
///
/// | Type              | r(x) formula                            |
/// |-------------------|-----------------------------------------|
/// | `constant`        | r₀                                      |
/// | `progressive`     | r₀ + r₁·x + r₂·x²                      |
/// | `lookupTable`     | linear interpolation of sample pairs    |
///
/// **Transforms**:
///
/// ```
/// shock_displacement = wheel_displacement / r(x)
/// shock_velocity     = wheel_velocity     / r(x)
/// wheel_force        = shock_force        × r(x)
/// ```
///
/// Usage:
/// ```dart
/// final cfg = LinkageConfig.constant(ratio: 2.8, wheelTravelMaxMm: 200.0);
/// final shockDisp = SuspensionGeometry.wheelToShockDisplacement(cfg, 100.0);
/// // shockDisp == 100.0 / 2.8 ≈ 35.7 mm
/// ```
class SuspensionGeometry {
  const SuspensionGeometry._();

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Returns the instantaneous linkage ratio at [wheelDisplacementMm].
  ///
  /// The wheel displacement is clamped to [0, wheelTravelMaxMm] before
  /// the ratio is evaluated to guard against boundary overrun.
  ///
  /// Throws [ArgumentError] if the [LinkageConfig] is invalid (e.g. non-positive
  /// constant ratio, non-positive r₀ for progressive, or lookup table with
  /// fewer than two points).
  static double linkageRatioAt(
    LinkageConfig config,
    double wheelDisplacementMm,
  ) {
    _validate(config);
    final x = wheelDisplacementMm.clamp(0.0, config.wheelTravelMaxMm);
    return _ratio(config, x);
  }

  /// Converts wheel displacement to shock displacement using the linkage ratio.
  ///
  /// ```
  /// shockDisplacementMm = wheelDisplacementMm / r(wheelDisplacementMm)
  /// ```
  ///
  /// [wheelDisplacementMm] is clamped to the valid travel range before
  /// evaluation.  Throws [ArgumentError] for an invalid [config].
  static double wheelToShockDisplacement(
    LinkageConfig config,
    double wheelDisplacementMm,
  ) {
    final r = linkageRatioAt(config, wheelDisplacementMm);
    final x = wheelDisplacementMm.clamp(0.0, config.wheelTravelMaxMm);
    return x / r;
  }

  /// Converts wheel velocity to shock velocity at [wheelDisplacementMm].
  ///
  /// ```
  /// shockVelocityMps = wheelVelocityMps / r(wheelDisplacementMm)
  /// ```
  ///
  /// The sign of [wheelVelocityMps] is preserved (positive = compression).
  /// Throws [ArgumentError] for an invalid [config].
  static double wheelToShockVelocity(
    LinkageConfig config,
    double wheelVelocityMps,
    double wheelDisplacementMm,
  ) {
    final r = linkageRatioAt(config, wheelDisplacementMm);
    return wheelVelocityMps / r;
  }

  /// Converts shock force to wheel force using the linkage ratio.
  ///
  /// ```
  /// wheelForceN = shockForceN × r(wheelDisplacementMm)
  /// ```
  ///
  /// Throws [ArgumentError] for an invalid [config].
  static double shockToWheelForce(
    LinkageConfig config,
    double shockForceN,
    double wheelDisplacementMm,
  ) {
    final r = linkageRatioAt(config, wheelDisplacementMm);
    return shockForceN * r;
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  /// Evaluates r(x) for the given [config] without clamping or validation.
  static double _ratio(LinkageConfig config, double x) {
    switch (config.type) {
      case LinkageType.constant:
        return config.constantRatio;

      case LinkageType.progressive:
        return config.r0 + config.r1 * x + config.r2 * x * x;

      case LinkageType.lookupTable:
        return _interpolate(config.travelPoints, config.ratioPoints, x);
    }
  }

  /// Linear interpolation / clamped extrapolation for lookup-table ratios.
  static double _interpolate(
    List<double> xs,
    List<double> ys,
    double x,
  ) {
    if (x <= xs.first) return ys.first;
    if (x >= xs.last) return ys.last;

    // Binary search for the surrounding interval.
    var lo = 0;
    var hi = xs.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (xs[mid] <= x) {
        lo = mid;
      } else {
        hi = mid;
      }
    }

    final t = (x - xs[lo]) / (xs[hi] - xs[lo]);
    return ys[lo] + t * (ys[hi] - ys[lo]);
  }

  /// Validates [config] and throws [ArgumentError] on the first failure found.
  static void _validate(LinkageConfig config) {
    if (config.wheelTravelMaxMm <= 0) {
      throw ArgumentError.value(
        config.wheelTravelMaxMm,
        'wheelTravelMaxMm',
        'Wheel travel must be positive.',
      );
    }

    switch (config.type) {
      case LinkageType.constant:
        if (config.constantRatio <= 0) {
          throw ArgumentError.value(
            config.constantRatio,
            'constantRatio',
            'Linkage ratio must be positive.',
          );
        }
        break;

      case LinkageType.progressive:
        if (config.r0 <= 0) {
          throw ArgumentError.value(
            config.r0,
            'r0',
            'Base linkage ratio r0 must be positive.',
          );
        }
        break;

      case LinkageType.lookupTable:
        if (config.travelPoints.length < 2) {
          throw ArgumentError(
            'Lookup-table linkage requires at least two sample points.',
          );
        }
        if (config.travelPoints.length != config.ratioPoints.length) {
          throw ArgumentError(
            'travelPoints and ratioPoints must have the same length.',
          );
        }
        for (var i = 1; i < config.travelPoints.length; i++) {
          if (config.travelPoints[i] <= config.travelPoints[i - 1]) {
            throw ArgumentError(
              'travelPoints must be strictly ascending.',
            );
          }
        }
        for (final r in config.ratioPoints) {
          if (r <= 0) {
            throw ArgumentError.value(
              r,
              'ratioPoints',
              'All linkage ratios must be positive.',
            );
          }
        }
        break;
    }
  }
}
