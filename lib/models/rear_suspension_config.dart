import 'damping_clicks_config.dart';
import 'linkage_config.dart';
import 'rear_geometry_config.dart';
import 'spring_config.dart';

/// Configuration for the rear suspension assembly (FR-SM-006).
///
/// Combines the spring model, damping adjuster positions, linkage motion ratio,
/// and geometry parameters for a rear monoshock with linkage.
///
/// Example (Yamaha Ténéré 700 2025 baseline):
/// ```dart
/// final rear = RearSuspensionConfig(
///   spring: const SpringConfig(
///     type: SpringType.linear,
///     springRateNPerMm: 95.0,
///     preloadMm: 5.0,
///   ),
///   damping: const DampingClicksConfig(
///     compressionLowSpeedClicks: 8,
///     compressionHighSpeedClicks: 8,
///     reboundLowSpeedClicks: 10,
///     reboundHighSpeedClicks: 10,
///   ),
///   linkage: LinkageConfig.constant(ratio: 2.8, wheelTravelMaxMm: 200),
///   geometry: const RearGeometryConfig(
///     wheelTravelMaxMm: 200,
///     unsprungMassKg: 28,
///     leverRatio: 2.8,
///   ),
/// );
/// ```
class RearSuspensionConfig {
  const RearSuspensionConfig({
    required this.spring,
    required this.damping,
    required this.linkage,
    required this.geometry,
  });

  /// Spring model for the rear shock.
  final SpringConfig spring;

  /// Damping adjuster positions for the rear shock.
  final DampingClicksConfig damping;

  /// Rear linkage motion ratio configuration.
  final LinkageConfig linkage;

  /// Geometry parameters for the rear suspension.
  final RearGeometryConfig geometry;

  /// Returns a copy with any provided fields replaced.
  RearSuspensionConfig copyWith({
    SpringConfig? spring,
    DampingClicksConfig? damping,
    LinkageConfig? linkage,
    RearGeometryConfig? geometry,
  }) {
    return RearSuspensionConfig(
      spring: spring ?? this.spring,
      damping: damping ?? this.damping,
      linkage: linkage ?? this.linkage,
      geometry: geometry ?? this.geometry,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RearSuspensionConfig &&
          spring == other.spring &&
          damping == other.damping &&
          linkage == other.linkage &&
          geometry == other.geometry;

  @override
  int get hashCode => Object.hash(spring, damping, linkage, geometry);

  @override
  String toString() =>
      'RearSuspensionConfig(spring: $spring, damping: $damping, '
      'linkage: $linkage, geometry: $geometry)';
}
