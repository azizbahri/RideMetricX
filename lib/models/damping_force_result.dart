/// Result of a damping force calculation at a given suspension velocity.
class DampingForceResult {
  const DampingForceResult({required this.forceN});

  /// Damping force in Newtons.
  ///
  /// The sign matches the suspension velocity convention:
  /// - Positive value for compression (positive velocity) — opposes compression.
  /// - Negative value for rebound (negative velocity) — opposes extension.
  final double forceN;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DampingForceResult && forceN == other.forceN;

  @override
  int get hashCode => forceN.hashCode;

  @override
  String toString() => 'DampingForceResult(forceN: $forceN)';
}
