/// Rider weight and gear configuration (FR-SM-006).
///
/// These values are used to compute static sag, sprung mass, and
/// total system weight for suspension tuning calculations.
class RiderConfig {
  const RiderConfig({
    required this.weightKg,
    this.gearWeightKg = 0.0,
  });

  /// Rider body weight in kg.
  ///
  /// Valid range: [[kMinWeightKg], [kMaxWeightKg]].
  final double weightKg;

  /// Combined weight of riding gear (helmet, jacket, boots, etc.) in kg.
  ///
  /// Valid range: [[kMinGearWeightKg], [kMaxGearWeightKg]].
  final double gearWeightKg;

  // ── Bounds ──────────────────────────────────────────────────────────────────

  /// Minimum rider body weight in kg.
  static const double kMinWeightKg = 30.0;

  /// Maximum rider body weight in kg.
  static const double kMaxWeightKg = 250.0;

  /// Minimum gear weight in kg.
  static const double kMinGearWeightKg = 0.0;

  /// Maximum gear weight in kg.
  static const double kMaxGearWeightKg = 50.0;

  // ── Derived ─────────────────────────────────────────────────────────────────

  /// Total rider system weight (body + gear) in kg.
  double get totalWeightKg => weightKg + gearWeightKg;

  // ── copyWith ────────────────────────────────────────────────────────────────

  /// Returns a copy with any provided fields replaced.
  RiderConfig copyWith({
    double? weightKg,
    double? gearWeightKg,
  }) {
    return RiderConfig(
      weightKg: weightKg ?? this.weightKg,
      gearWeightKg: gearWeightKg ?? this.gearWeightKg,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiderConfig &&
          weightKg == other.weightKg &&
          gearWeightKg == other.gearWeightKg;

  @override
  int get hashCode => Object.hash(weightKg, gearWeightKg);

  @override
  String toString() =>
      'RiderConfig(weightKg: $weightKg, gearWeightKg: $gearWeightKg)';
}
