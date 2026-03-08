import 'package:flutter/foundation.dart';

/// Snapshot of the current suspension animation state (FR-VZ-002, FR-VZ-004).
///
/// All travel values are in millimetres.  Positive values indicate compression
/// from the fully-extended rest position.
///
/// [frontCompressionRatio] and [rearCompressionRatio] normalise the travel
/// values to [0, 1] for use by the material and painter layers.
@immutable
class SuspensionState {
  const SuspensionState({
    this.frontTravelMm = 0.0,
    this.rearTravelMm = 0.0,
    this.wheelRotationRad = 0.0,
    this.frontMaxTravelMm = 300.0,
    this.rearMaxTravelMm = 200.0,
  });

  /// Front-fork compression in mm (0 = fully extended).
  final double frontTravelMm;

  /// Rear-shock compression in mm (0 = fully extended).
  final double rearTravelMm;

  /// Cumulative wheel rotation angle in radians (increases as bike moves
  /// forward).
  final double wheelRotationRad;

  /// Maximum front travel used for normalisation (default 300 mm).
  final double frontMaxTravelMm;

  /// Maximum rear travel used for normalisation (default 200 mm).
  final double rearMaxTravelMm;

  // ── Derived properties ─────────────────────────────────────────────────────

  /// Front compression ratio in [0, 1] (0 = extended, 1 = fully compressed).
  double get frontCompressionRatio {
    if (frontMaxTravelMm <= 0.0) {
      // Avoid division by zero or negative normalisation; treat as no compression.
      return 0.0;
    }
    final double ratio = frontTravelMm / frontMaxTravelMm;
    return ratio.clamp(0.0, 1.0);
  }

  /// Rear compression ratio in [0, 1] (0 = extended, 1 = fully compressed).
  double get rearCompressionRatio {
    if (rearMaxTravelMm <= 0.0) {
      // Avoid division by zero or negative normalisation; treat as no compression.
      return 0.0;
    }
    final double ratio = rearTravelMm / rearMaxTravelMm;
    return ratio.clamp(0.0, 1.0);
  }

  // ── Copy ───────────────────────────────────────────────────────────────────

  /// Returns a copy of this state with the specified fields overridden.
  SuspensionState copyWith({
    double? frontTravelMm,
    double? rearTravelMm,
    double? wheelRotationRad,
    double? frontMaxTravelMm,
    double? rearMaxTravelMm,
  }) {
    return SuspensionState(
      frontTravelMm: frontTravelMm ?? this.frontTravelMm,
      rearTravelMm: rearTravelMm ?? this.rearTravelMm,
      wheelRotationRad: wheelRotationRad ?? this.wheelRotationRad,
      frontMaxTravelMm: frontMaxTravelMm ?? this.frontMaxTravelMm,
      rearMaxTravelMm: rearMaxTravelMm ?? this.rearMaxTravelMm,
    );
  }

  // ── Equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SuspensionState &&
          frontTravelMm == other.frontTravelMm &&
          rearTravelMm == other.rearTravelMm &&
          wheelRotationRad == other.wheelRotationRad &&
          frontMaxTravelMm == other.frontMaxTravelMm &&
          rearMaxTravelMm == other.rearMaxTravelMm;

  @override
  int get hashCode => Object.hash(
        frontTravelMm,
        rearTravelMm,
        wheelRotationRad,
        frontMaxTravelMm,
        rearMaxTravelMm,
      );

  @override
  String toString() =>
      'SuspensionState('
      'front: ${frontTravelMm.toStringAsFixed(1)} mm, '
      'rear: ${rearTravelMm.toStringAsFixed(1)} mm, '
      'wheel: ${wheelRotationRad.toStringAsFixed(3)} rad)';
}
