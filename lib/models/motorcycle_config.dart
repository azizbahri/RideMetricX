/// Motorcycle identification and weight parameters (FR-SM-006).
///
/// Used to compute the sprung mass and total system weight for
/// suspension tuning calculations.
class MotorcycleConfig {
  const MotorcycleConfig({
    required this.model,
    required this.weightDryKg,
  });

  /// Human-readable motorcycle model name (e.g. "Yamaha Ténéré 700 2025").
  ///
  /// Must not be empty.
  final String model;

  /// Dry weight of the motorcycle (without fuel, fluids, or rider) in kg.
  ///
  /// Valid range: [[kMinWeightDryKg], [kMaxWeightDryKg]].
  final double weightDryKg;

  // ── Bounds ──────────────────────────────────────────────────────────────────

  /// Minimum reasonable dry weight in kg (lightest production motorcycles).
  static const double kMinWeightDryKg = 50.0;

  /// Maximum reasonable dry weight in kg.
  static const double kMaxWeightDryKg = 1000.0;

  // ── copyWith ────────────────────────────────────────────────────────────────

  /// Returns a copy with any provided fields replaced.
  MotorcycleConfig copyWith({
    String? model,
    double? weightDryKg,
  }) {
    return MotorcycleConfig(
      model: model ?? this.model,
      weightDryKg: weightDryKg ?? this.weightDryKg,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MotorcycleConfig &&
          model == other.model &&
          weightDryKg == other.weightDryKg;

  @override
  int get hashCode => Object.hash(model, weightDryKg);

  @override
  String toString() =>
      'MotorcycleConfig(model: $model, weightDryKg: $weightDryKg)';
}
