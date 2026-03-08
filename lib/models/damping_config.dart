/// The type of damping model to apply (FR-SM-002).
enum DampingType {
  /// Linear damping: F = c × v
  linear,

  /// Bi-linear (low-speed / high-speed) damping:
  /// ```
  /// F = c_low × v                      if |v| < v_threshold
  /// F = c_high × v + offset × sign(v)  if |v| ≥ v_threshold
  /// ```
  /// where offset × sign(v) ensures force continuity at ±v_threshold.
  biLinear,

  /// Non-linear damping extension hook:
  /// ```
  /// F = c × v + d × v² × sign(v)
  /// ```
  /// Models realistic, velocity-squared damper characteristics.
  nonLinear,
}

/// Configuration for a single damping channel (compression or rebound).
///
/// All coefficients are in **N·s/mm**; velocity inputs to [DampingModel] are
/// in **m/s** and are converted internally.
///
/// Usage:
/// ```dart
/// const config = DampingConfig(
///   type: DampingType.biLinear,
///   lowSpeedCoefficientNsPerMm: 10.0,
///   highSpeedCoefficientNsPerMm: 4.0,
///   velocityThresholdMps: 0.5,
/// );
/// final result = DampingModel.calculateForce(config, velocityMps: 0.3);
/// ```
class DampingConfig {
  const DampingConfig({
    required this.type,
    required this.lowSpeedCoefficientNsPerMm,
    this.highSpeedCoefficientNsPerMm = 0.0,
    this.velocityThresholdMps = 0.5,
    this.nonLinearDCoefficientNs2PerMm2 = 0.0,
  });

  /// Damping model type.
  final DampingType type;

  /// Low-speed damping coefficient in N·s/mm.
  ///
  /// Used as the sole coefficient for [DampingType.linear] and
  /// [DampingType.nonLinear], and for the low-speed regime of
  /// [DampingType.biLinear].
  final double lowSpeedCoefficientNsPerMm;

  /// High-speed damping coefficient in N·s/mm.
  ///
  /// Used only for [DampingType.biLinear]. Typically lower than
  /// [lowSpeedCoefficientNsPerMm] so that the damper becomes
  /// relatively softer at high shaft velocities (blow-off behaviour).
  final double highSpeedCoefficientNsPerMm;

  /// Velocity threshold in m/s at which the bi-linear transition occurs.
  ///
  /// Default is 0.5 m/s, which is typical for motorcycle dampers.
  final double velocityThresholdMps;

  /// Non-linear d-coefficient in N·s²/mm².
  ///
  /// Used only for [DampingType.nonLinear]. A positive value increases
  /// damping force super-linearly with velocity.
  final double nonLinearDCoefficientNs2PerMm2;

  /// Returns a copy with any provided fields replaced.
  DampingConfig copyWith({
    DampingType? type,
    double? lowSpeedCoefficientNsPerMm,
    double? highSpeedCoefficientNsPerMm,
    double? velocityThresholdMps,
    double? nonLinearDCoefficientNs2PerMm2,
  }) {
    return DampingConfig(
      type: type ?? this.type,
      lowSpeedCoefficientNsPerMm:
          lowSpeedCoefficientNsPerMm ?? this.lowSpeedCoefficientNsPerMm,
      highSpeedCoefficientNsPerMm:
          highSpeedCoefficientNsPerMm ?? this.highSpeedCoefficientNsPerMm,
      velocityThresholdMps: velocityThresholdMps ?? this.velocityThresholdMps,
      nonLinearDCoefficientNs2PerMm2:
          nonLinearDCoefficientNs2PerMm2 ?? this.nonLinearDCoefficientNs2PerMm2,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DampingConfig &&
          type == other.type &&
          lowSpeedCoefficientNsPerMm == other.lowSpeedCoefficientNsPerMm &&
          highSpeedCoefficientNsPerMm == other.highSpeedCoefficientNsPerMm &&
          velocityThresholdMps == other.velocityThresholdMps &&
          nonLinearDCoefficientNs2PerMm2 ==
              other.nonLinearDCoefficientNs2PerMm2;

  @override
  int get hashCode => Object.hash(
    type,
    lowSpeedCoefficientNsPerMm,
    highSpeedCoefficientNsPerMm,
    velocityThresholdMps,
    nonLinearDCoefficientNs2PerMm2,
  );

  @override
  String toString() =>
      'DampingConfig(type: $type, '
      'lowSpeedCoefficientNsPerMm: $lowSpeedCoefficientNsPerMm, '
      'highSpeedCoefficientNsPerMm: $highSpeedCoefficientNsPerMm, '
      'velocityThresholdMps: $velocityThresholdMps, '
      'nonLinearDCoefficientNs2PerMm2: $nonLinearDCoefficientNs2PerMm2)';
}
