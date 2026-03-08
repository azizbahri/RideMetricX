/// Geometry parameters for a rear monoshock suspension (FR-SM-006).
///
/// These values describe the static geometry of the rear suspension linkage
/// and provide configuration for the quarter-car equations of motion.
class RearGeometryConfig {
  const RearGeometryConfig({
    required this.wheelTravelMaxMm,
    this.unsprungMassKg = 0.0,
    this.leverRatio = 1.0,
  });

  /// Maximum rear wheel travel in mm (e.g. 200 mm for Yamaha Ténéré 700).
  final double wheelTravelMaxMm;

  /// Estimated unsprung mass (wheel assembly + swingarm) in kg.
  ///
  /// Used by quarter-car equations of motion.
  /// Typical value for an adventure motorcycle rear: ~28 kg.
  final double unsprungMassKg;

  /// Suspension lever (motion) ratio at mid-stroke (dimensionless).
  ///
  /// Relates wheel displacement to shock displacement:
  /// ```
  /// shock_displacement = wheel_displacement / leverRatio
  /// ```
  /// Typical value for an adventure motorcycle: ~2.8.
  final double leverRatio;

  /// Returns a copy with any provided fields replaced.
  RearGeometryConfig copyWith({
    double? wheelTravelMaxMm,
    double? unsprungMassKg,
    double? leverRatio,
  }) {
    return RearGeometryConfig(
      wheelTravelMaxMm: wheelTravelMaxMm ?? this.wheelTravelMaxMm,
      unsprungMassKg: unsprungMassKg ?? this.unsprungMassKg,
      leverRatio: leverRatio ?? this.leverRatio,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RearGeometryConfig &&
          wheelTravelMaxMm == other.wheelTravelMaxMm &&
          unsprungMassKg == other.unsprungMassKg &&
          leverRatio == other.leverRatio;

  @override
  int get hashCode => Object.hash(wheelTravelMaxMm, unsprungMassKg, leverRatio);

  @override
  String toString() =>
      'RearGeometryConfig(wheelTravelMaxMm: $wheelTravelMaxMm, '
      'unsprungMassKg: $unsprungMassKg, leverRatio: $leverRatio)';
}
