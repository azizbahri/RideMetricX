import '../../models/spring_config.dart';
import '../../models/spring_force_result.dart';

/// Computes spring forces and stored elastic energy for the supported spring
/// models (FR-SM-001).
///
/// All displacement values are in **mm**; force results are in **Newtons**;
/// elastic energy results are in **Joules**.
///
/// Usage:
/// ```dart
/// const config = SpringConfig(
///   type: SpringType.linear,
///   springRateNPerMm: 9.0,
///   preloadMm: 10.0,
/// );
/// final result = SpringModel.calculateForce(config, displacementMm: 30.0);
/// print(result.forceN); // 360.0 N
/// ```
class SpringModel {
  const SpringModel._();

  /// Calculates the spring force and stored elastic energy at [displacementMm].
  ///
  /// The [displacementMm] is the **additional** compression from the free
  /// (unloaded) position.  [SpringConfig.preloadMm] is added internally to
  /// obtain the total spring compression used in the energy calculation, while
  /// the returned [SpringForceResult.forceN] represents only the restoring
  /// force at [displacementMm] (preload force is constant and handled by the
  /// caller's static equilibrium).
  ///
  /// Throws [ArgumentError] if [SpringConfig.springRateNPerMm] ≤ 0 or if a
  /// dual-rate config has a non-positive [SpringConfig.secondarySpringRateNPerMm].
  static SpringForceResult calculateForce(
    SpringConfig config, {
    required double displacementMm,
  }) {
    _validate(config);

    return switch (config.type) {
      SpringType.linear => _linear(config, displacementMm),
      SpringType.progressive => _progressive(config, displacementMm),
      SpringType.dualRate => _dualRate(config, displacementMm),
    };
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static void _validate(SpringConfig config) {
    if (config.springRateNPerMm <= 0) {
      throw ArgumentError.value(
        config.springRateNPerMm,
        'springRateNPerMm',
        'Spring rate must be positive.',
      );
    }
    if (config.type == SpringType.dualRate &&
        config.secondarySpringRateNPerMm <= 0) {
      throw ArgumentError.value(
        config.secondarySpringRateNPerMm,
        'secondarySpringRateNPerMm',
        'Secondary spring rate must be positive for dual-rate springs.',
      );
    }
  }

  /// Linear spring: F = k × x
  ///
  /// Elastic energy: E = ½ k × x²
  static SpringForceResult _linear(
    SpringConfig config,
    double displacementMm,
  ) {
    final k = config.springRateNPerMm; // N/mm
    final x = displacementMm; // mm

    // Force in N (k in N/mm, x in mm → N)
    final forceN = k * x;

    // Elastic energy: ½ k [N/mm] × x² [mm²] → N·mm = 1e-3 J → ÷1000 for J
    final elasticEnergyJ = 0.5 * k * x * x / 1000.0;

    return SpringForceResult(forceN: forceN, elasticEnergyJ: elasticEnergyJ);
  }

  /// Progressive spring: F = k₁ × x + k₂ × x²
  ///
  /// Elastic energy: E = ½ k₁ × x² + ⅓ k₂ × x³
  static SpringForceResult _progressive(
    SpringConfig config,
    double displacementMm,
  ) {
    final k1 = config.springRateNPerMm; // N/mm
    final k2 = config.progressiveRateNPerMm2; // N/mm²
    final x = displacementMm; // mm

    final forceN = k1 * x + k2 * x * x;

    // E = ½ k₁ x² + ⅓ k₂ x³  (units: N/mm × mm² = N·mm → ÷1000 for J)
    final elasticEnergyJ =
        (0.5 * k1 * x * x + k2 * x * x * x / 3.0) / 1000.0;

    return SpringForceResult(forceN: forceN, elasticEnergyJ: elasticEnergyJ);
  }

  /// Dual-rate spring: rate k₁ up to [SpringConfig.dualRateBreakpointMm],
  /// rate k₂ beyond the breakpoint.
  ///
  /// ```
  /// F(x) = k₁ × x                            for x ≤ bp
  ///       = k₁ × bp + k₂ × (x - bp)          for x > bp
  /// ```
  ///
  /// Elastic energy:
  /// ```
  /// E(x) = ½ k₁ × x²                               for x ≤ bp
  ///       = ½ k₁ × bp² + k₁ × bp × (x-bp)
  ///         + ½ k₂ × (x-bp)²                        for x > bp
  /// ```
  static SpringForceResult _dualRate(
    SpringConfig config,
    double displacementMm,
  ) {
    final k1 = config.springRateNPerMm; // N/mm
    final k2 = config.secondarySpringRateNPerMm; // N/mm
    final bp = config.dualRateBreakpointMm; // mm
    final x = displacementMm; // mm

    final double forceN;
    final double elasticEnergyJ;

    if (x <= bp) {
      forceN = k1 * x;
      elasticEnergyJ = 0.5 * k1 * x * x / 1000.0;
    } else {
      final overflow = x - bp;
      forceN = k1 * bp + k2 * overflow;
      // Energy = area under F(x) curve from 0 to x
      //        = ½ k₁ bp²  +  k₁ bp × overflow  +  ½ k₂ overflow²
      elasticEnergyJ =
          (0.5 * k1 * bp * bp + k1 * bp * overflow + 0.5 * k2 * overflow *
              overflow) /
          1000.0;
    }

    return SpringForceResult(forceN: forceN, elasticEnergyJ: elasticEnergyJ);
  }
}
