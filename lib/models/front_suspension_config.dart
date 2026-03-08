import 'damping_clicks_config.dart';
import 'front_geometry_config.dart';
import 'spring_config.dart';

/// Configuration for the front suspension assembly (FR-SM-006).
///
/// Combines the spring model, damping adjuster positions, and geometry
/// parameters for a front telescopic fork.
///
/// Example (Yamaha Ténéré 700 2025 baseline):
/// ```dart
/// const front = FrontSuspensionConfig(
///   spring: SpringConfig(
///     type: SpringType.linear,
///     springRateNPerMm: 9.0,
///     preloadMm: 10.0,
///   ),
///   damping: DampingClicksConfig(
///     compressionLowSpeedClicks: 10,
///     compressionHighSpeedClicks: 10,
///     reboundLowSpeedClicks: 10,
///     reboundHighSpeedClicks: 10,
///   ),
///   geometry: FrontGeometryConfig(
///     wheelTravelMaxMm: 210,
///     rakeDeg: 27,
///     trailMm: 110,
///     unsprungMassKg: 18,
///   ),
/// );
/// ```
class FrontSuspensionConfig {
  const FrontSuspensionConfig({
    required this.spring,
    required this.damping,
    required this.geometry,
  });

  /// Spring model for the front fork.
  final SpringConfig spring;

  /// Damping adjuster positions for the front fork.
  final DampingClicksConfig damping;

  /// Geometry parameters for the front fork.
  final FrontGeometryConfig geometry;

  /// Returns a copy with any provided fields replaced.
  FrontSuspensionConfig copyWith({
    SpringConfig? spring,
    DampingClicksConfig? damping,
    FrontGeometryConfig? geometry,
  }) {
    return FrontSuspensionConfig(
      spring: spring ?? this.spring,
      damping: damping ?? this.damping,
      geometry: geometry ?? this.geometry,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FrontSuspensionConfig &&
          spring == other.spring &&
          damping == other.damping &&
          geometry == other.geometry;

  @override
  int get hashCode => Object.hash(spring, damping, geometry);

  @override
  String toString() =>
      'FrontSuspensionConfig(spring: $spring, damping: $damping, '
      'geometry: $geometry)';
}
