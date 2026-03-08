/// Geometry parameters for a front telescopic fork.
///
/// These values describe the static geometry of the front suspension and serve
/// as placeholders for higher-level models (FR-SM-003).  The fields are
/// informational/configuration only – they do not drive calculations in the
/// current implementation but provide a stable interface for the solver and
/// metrics modules that depend on this issue.
class FrontGeometryConfig {
  const FrontGeometryConfig({
    required this.wheelTravelMaxMm,
    this.rakeDeg = 0.0,
    this.trailMm = 0.0,
    this.unsprungMassKg = 0.0,
  });

  /// Maximum front wheel travel in mm (e.g. 210 mm for Yamaha Ténéré 700).
  final double wheelTravelMaxMm;

  /// Fork rake (caster) angle in degrees.
  ///
  /// Typical value for an adventure motorcycle: ~27°.
  /// Placeholder – reserved for steering-geometry calculations.
  final double rakeDeg;

  /// Trail in mm.
  ///
  /// Affects steering stability; derived from rake, wheel radius, and offset.
  /// Placeholder – reserved for steering-geometry calculations.
  final double trailMm;

  /// Estimated unsprung mass (wheel assembly + lower fork) in kg.
  ///
  /// Used by quarter-car equations of motion.
  final double unsprungMassKg;

  /// Returns a copy with any provided fields replaced.
  FrontGeometryConfig copyWith({
    double? wheelTravelMaxMm,
    double? rakeDeg,
    double? trailMm,
    double? unsprungMassKg,
  }) {
    return FrontGeometryConfig(
      wheelTravelMaxMm: wheelTravelMaxMm ?? this.wheelTravelMaxMm,
      rakeDeg: rakeDeg ?? this.rakeDeg,
      trailMm: trailMm ?? this.trailMm,
      unsprungMassKg: unsprungMassKg ?? this.unsprungMassKg,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FrontGeometryConfig &&
          wheelTravelMaxMm == other.wheelTravelMaxMm &&
          rakeDeg == other.rakeDeg &&
          trailMm == other.trailMm &&
          unsprungMassKg == other.unsprungMassKg;

  @override
  int get hashCode =>
      Object.hash(wheelTravelMaxMm, rakeDeg, trailMm, unsprungMassKg);

  @override
  String toString() =>
      'FrontGeometryConfig(wheelTravelMaxMm: $wheelTravelMaxMm, '
      'rakeDeg: $rakeDeg, trailMm: $trailMm, '
      'unsprungMassKg: $unsprungMassKg)';
}
