import '../../models/sag_result.dart';

/// Calculates static and race sag for a suspension element (FR-SM-008).
///
/// Sag is the static compression of the suspension under weight:
/// - **Free sag**: compression under bike weight only (no rider).
/// - **Static (race) sag**: compression under bike + rider weight.
///
/// Formula:
/// ```
/// sagMm = (weightKg × g) / springRateNPerMm
/// ```
/// where g = 9.81 m/s².
///
/// Usage:
/// ```dart
/// final result = SagCalculator.calculate(
///   springRateNPerMm: 95.0,
///   bikeWeightKg: 204.0,
///   riderWeightKg: 80.0,
/// );
/// print(result.freeSagMm);    // ~21.0 mm
/// print(result.staticSagMm);  // ~29.2 mm
/// ```
class SagCalculator {
  const SagCalculator._();

  /// Acceleration due to gravity in m/s².
  static const double _g = 9.81;

  /// Calculates free sag and static (race) sag in mm.
  ///
  /// [springRateNPerMm] must be positive (N/mm).
  /// [bikeWeightKg] and [riderWeightKg] must be non-negative (kg).
  ///
  /// Throws [ArgumentError] if any parameter is out of range.
  static SagResult calculate({
    required double springRateNPerMm,
    required double bikeWeightKg,
    required double riderWeightKg,
  }) {
    if (springRateNPerMm <= 0) {
      throw ArgumentError.value(
        springRateNPerMm,
        'springRateNPerMm',
        'Spring rate must be positive.',
      );
    }
    if (bikeWeightKg < 0) {
      throw ArgumentError.value(
        bikeWeightKg,
        'bikeWeightKg',
        'Bike weight must be non-negative.',
      );
    }
    if (riderWeightKg < 0) {
      throw ArgumentError.value(
        riderWeightKg,
        'riderWeightKg',
        'Rider weight must be non-negative.',
      );
    }

    // Force [N] = mass [kg] × g [m/s²]
    // sag [mm] = force [N] / rate [N/mm]
    final freeSagMm = (bikeWeightKg * _g) / springRateNPerMm;
    final staticSagMm = ((bikeWeightKg + riderWeightKg) * _g) /
        springRateNPerMm;

    return SagResult(freeSagMm: freeSagMm, staticSagMm: staticSagMm);
  }
}
