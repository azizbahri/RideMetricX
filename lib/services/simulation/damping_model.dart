import '../../models/damping_config.dart';
import '../../models/damping_force_result.dart';

/// Computes velocity-dependent damping forces for the supported damping
/// models (FR-SM-002).
///
/// All coefficient values in [DampingConfig] are in **N·s/mm**; velocity
/// is supplied in **m/s** and converted internally to mm/s before
/// calculating the force.
///
/// Sign convention for [velocityMps] and the returned force:
/// - **Positive** velocity → suspension compressing; force is positive
///   (opposes compression).
/// - **Negative** velocity → suspension extending (rebound); force is
///   negative (opposes extension).
///
/// Usage:
/// ```dart
/// const config = DampingConfig(
///   type: DampingType.linear,
///   lowSpeedCoefficientNsPerMm: 10.0,
/// );
/// final result = DampingModel.calculateForce(config, velocityMps: 0.3);
/// print(result.forceN); // 3000.0 N  (10 N·s/mm × 300 mm/s)
/// ```
class DampingModel {
  const DampingModel._();

  /// Calculates the damping force at [velocityMps].
  ///
  /// [velocityMps] is the signed suspension velocity in m/s:
  /// - Positive = suspension compressing.
  /// - Negative = suspension extending (rebound).
  ///
  /// Throws [ArgumentError] if:
  /// - [DampingConfig.lowSpeedCoefficientNsPerMm] ≤ 0, or
  /// - [DampingConfig.type] is [DampingType.biLinear] and
  ///   [DampingConfig.highSpeedCoefficientNsPerMm] ≤ 0, or
  /// - [DampingConfig.type] is [DampingType.biLinear] and
  ///   [DampingConfig.velocityThresholdMps] ≤ 0.
  static DampingForceResult calculateForce(
    DampingConfig config, {
    required double velocityMps,
  }) {
    _validate(config);

    return switch (config.type) {
      DampingType.linear => _linear(config, velocityMps),
      DampingType.biLinear => _biLinear(config, velocityMps),
      DampingType.nonLinear => _nonLinear(config, velocityMps),
    };
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static void _validate(DampingConfig config) {
    if (config.lowSpeedCoefficientNsPerMm <= 0) {
      throw ArgumentError.value(
        config.lowSpeedCoefficientNsPerMm,
        'lowSpeedCoefficientNsPerMm',
        'Damping coefficient must be positive.',
      );
    }
    if (config.type == DampingType.biLinear) {
      if (config.highSpeedCoefficientNsPerMm <= 0) {
        throw ArgumentError.value(
          config.highSpeedCoefficientNsPerMm,
          'highSpeedCoefficientNsPerMm',
          'High-speed damping coefficient must be positive for bi-linear damping.',
        );
      }
      if (config.velocityThresholdMps <= 0) {
        throw ArgumentError.value(
          config.velocityThresholdMps,
          'velocityThresholdMps',
          'Velocity threshold must be positive for bi-linear damping.',
        );
      }
    }
  }

  /// Linear damping: F = c × v
  ///
  /// where v is in mm/s (velocityMps × 1000) and c is in N·s/mm,
  /// yielding force in N.
  static DampingForceResult _linear(
    DampingConfig config,
    double velocityMps,
  ) {
    final c = config.lowSpeedCoefficientNsPerMm; // N·s/mm
    final v = velocityMps * 1000.0; // mm/s

    return DampingForceResult(forceN: c * v);
  }

  /// Bi-linear damping (low-speed / high-speed):
  /// ```
  /// F = c_low × v                      if |v| < v_threshold
  /// F = c_high × v + offset × sign(v)  if |v| ≥ v_threshold
  /// ```
  /// where offset = (c_low − c_high) × v_threshold ensures continuity.
  static DampingForceResult _biLinear(
    DampingConfig config,
    double velocityMps,
  ) {
    final cLow = config.lowSpeedCoefficientNsPerMm; // N·s/mm
    final cHigh = config.highSpeedCoefficientNsPerMm; // N·s/mm
    final threshMmS = config.velocityThresholdMps * 1000.0; // mm/s
    final v = velocityMps * 1000.0; // mm/s
    final absV = v.abs();

    final double forceN;
    if (absV < threshMmS) {
      forceN = cLow * v;
    } else {
      // Continuity offset: ensures F is continuous at ±threshold.
      final offset = (cLow - cHigh) * threshMmS;
      final sign = v >= 0 ? 1.0 : -1.0;
      forceN = cHigh * v + offset * sign;
    }

    return DampingForceResult(forceN: forceN);
  }

  /// Non-linear damping (extension hook):
  /// ```
  /// F = c × v + d × v² × sign(v)
  /// ```
  /// where v is in mm/s, c is in N·s/mm, and d is in N·s²/mm².
  static DampingForceResult _nonLinear(
    DampingConfig config,
    double velocityMps,
  ) {
    final c = config.lowSpeedCoefficientNsPerMm; // N·s/mm
    final d = config.nonLinearDCoefficientNs2PerMm2; // N·s²/mm²
    final v = velocityMps * 1000.0; // mm/s
    final sign = v >= 0 ? 1.0 : -1.0;

    final forceN = c * v + d * v * v * sign;

    return DampingForceResult(forceN: forceN);
  }
}
