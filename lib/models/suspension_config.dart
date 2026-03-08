import 'front_suspension_config.dart';
import 'motorcycle_config.dart';
import 'rear_suspension_config.dart';
import 'rider_config.dart';

/// Top-level typed suspension configuration schema (FR-SM-006).
///
/// Aggregates motorcycle metadata, rider parameters, and front/rear suspension
/// configurations into a single immutable object that downstream modules
/// (simulation, sag calculator, force reconstruction) can consume safely.
///
/// Use [ConfigValidator.validate] to check required-field and range constraints
/// before passing a config to the physics engine.
///
/// Example:
/// ```dart
/// // Load the Tenere 700 baseline and tweak the rider weight.
/// final config = Tenere700Profile.baseline.copyWith(
///   rider: const RiderConfig(weightKg: 90, gearWeightKg: 12),
/// );
/// final errors = ConfigValidator.validate(config);
/// if (errors.isEmpty) {
///   // safe to use
/// }
/// ```
class SuspensionConfig {
  const SuspensionConfig({
    required this.motorcycle,
    required this.rider,
    required this.front,
    required this.rear,
  });

  /// Motorcycle identification and weight.
  final MotorcycleConfig motorcycle;

  /// Rider weight and gear.
  final RiderConfig rider;

  /// Front suspension assembly configuration.
  final FrontSuspensionConfig front;

  /// Rear suspension assembly configuration.
  final RearSuspensionConfig rear;

  /// Returns a copy with any provided fields replaced.
  SuspensionConfig copyWith({
    MotorcycleConfig? motorcycle,
    RiderConfig? rider,
    FrontSuspensionConfig? front,
    RearSuspensionConfig? rear,
  }) {
    return SuspensionConfig(
      motorcycle: motorcycle ?? this.motorcycle,
      rider: rider ?? this.rider,
      front: front ?? this.front,
      rear: rear ?? this.rear,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SuspensionConfig &&
          motorcycle == other.motorcycle &&
          rider == other.rider &&
          front == other.front &&
          rear == other.rear;

  @override
  int get hashCode => Object.hash(motorcycle, rider, front, rear);

  @override
  String toString() =>
      'SuspensionConfig(motorcycle: $motorcycle, rider: $rider, '
      'front: $front, rear: $rear)';
}
