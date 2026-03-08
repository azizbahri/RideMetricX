/// Linkage type for a rear suspension element.
enum LinkageType {
  /// Constant linkage ratio: r(x) = r₀.
  constant,

  /// Progressive polynomial ratio: r(x) = r₀ + r₁·x + r₂·x².
  progressive,

  /// Lookup-table ratio: linearly interpolated from (travelMm, ratios) pairs.
  lookupTable,
}

/// Configuration for a rear suspension linkage (motion ratio).
///
/// The linkage ratio r(x) relates wheel travel to shock travel:
/// ```
/// shock_displacement = wheel_displacement / r(x)
/// shock_velocity     = wheel_velocity     / r(x)
/// wheel_force        = shock_force        × r(x)
/// ```
///
/// Supported models:
///
/// **Constant** – r(x) = [constantRatio].
///
/// **Progressive polynomial** – r(x) = [r0] + [r1]·x + [r2]·x²
/// where x is wheel displacement in mm.
///
/// **Lookup table** – r(x) is linearly interpolated between the
/// ([travelPoints], [ratioPoints]) sample pairs. Queries outside the defined
/// range are clamped to the nearest endpoint value.
class LinkageConfig {
  const LinkageConfig.constant({
    required double ratio,
    required this.wheelTravelMaxMm,
  })  : type = LinkageType.constant,
        constantRatio = ratio,
        r0 = 0.0,
        r1 = 0.0,
        r2 = 0.0,
        travelPoints = const [],
        ratioPoints = const [];

  const LinkageConfig.progressive({
    required this.r0,
    required this.wheelTravelMaxMm,
    this.r1 = 0.0,
    this.r2 = 0.0,
  })  : type = LinkageType.progressive,
        constantRatio = 0.0,
        travelPoints = const [],
        ratioPoints = const [];

  const LinkageConfig.lookupTable({
    required this.travelPoints,
    required this.ratioPoints,
    required this.wheelTravelMaxMm,
  })  : type = LinkageType.lookupTable,
        constantRatio = 0.0,
        r0 = 0.0,
        r1 = 0.0,
        r2 = 0.0;

  /// Linkage model type.
  final LinkageType type;

  /// Maximum wheel travel in mm (used for boundary clamping and validation).
  final double wheelTravelMaxMm;

  // ── Constant ────────────────────────────────────────────────────────────────

  /// Linkage ratio for [LinkageType.constant] models (dimensionless).
  final double constantRatio;

  // ── Progressive polynomial ──────────────────────────────────────────────────

  /// Base (zero-displacement) linkage ratio for [LinkageType.progressive].
  ///
  /// r(x) = r0 + r1·x + r2·x²
  final double r0;

  /// Linear coefficient (1/mm) for [LinkageType.progressive].
  final double r1;

  /// Quadratic coefficient (1/mm²) for [LinkageType.progressive].
  final double r2;

  // ── Lookup table ────────────────────────────────────────────────────────────

  /// Wheel displacement sample points in mm (must be strictly ascending).
  ///
  /// Used only when [type] is [LinkageType.lookupTable].
  final List<double> travelPoints;

  /// Linkage ratio values corresponding to each [travelPoints] entry.
  ///
  /// Used only when [type] is [LinkageType.lookupTable].
  final List<double> ratioPoints;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkageConfig &&
          type == other.type &&
          wheelTravelMaxMm == other.wheelTravelMaxMm &&
          constantRatio == other.constantRatio &&
          r0 == other.r0 &&
          r1 == other.r1 &&
          r2 == other.r2 &&
          _listEqual(travelPoints, other.travelPoints) &&
          _listEqual(ratioPoints, other.ratioPoints);

  @override
  int get hashCode => Object.hash(
        type,
        wheelTravelMaxMm,
        constantRatio,
        r0,
        r1,
        r2,
        Object.hashAll(travelPoints),
        Object.hashAll(ratioPoints),
      );

  @override
  String toString() {
    switch (type) {
      case LinkageType.constant:
        return 'LinkageConfig.constant(ratio: $constantRatio, '
            'wheelTravelMaxMm: $wheelTravelMaxMm)';
      case LinkageType.progressive:
        return 'LinkageConfig.progressive(r0: $r0, r1: $r1, r2: $r2, '
            'wheelTravelMaxMm: $wheelTravelMaxMm)';
      case LinkageType.lookupTable:
        return 'LinkageConfig.lookupTable(points: ${travelPoints.length}, '
            'wheelTravelMaxMm: $wheelTravelMaxMm)';
    }
  }

  static bool _listEqual(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
