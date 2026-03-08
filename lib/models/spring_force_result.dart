/// Result of a spring force calculation at a given displacement.
class SpringForceResult {
  const SpringForceResult({
    required this.forceN,
    required this.elasticEnergyJ,
  });

  /// Spring force in Newtons at the computed displacement.
  ///
  /// A positive value indicates a compressive (restoring) force opposing the
  /// displacement.
  final double forceN;

  /// Elastic (potential) energy stored in the spring in Joules.
  final double elasticEnergyJ;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpringForceResult &&
          forceN == other.forceN &&
          elasticEnergyJ == other.elasticEnergyJ;

  @override
  int get hashCode => Object.hash(forceN, elasticEnergyJ);

  @override
  String toString() =>
      'SpringForceResult(forceN: $forceN, elasticEnergyJ: $elasticEnergyJ)';
}
