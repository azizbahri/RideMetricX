import '../../models/damping_clicks_config.dart';
import '../../models/front_geometry_config.dart';
import '../../models/front_suspension_config.dart';
import '../../models/linkage_config.dart';
import '../../models/motorcycle_config.dart';
import '../../models/rear_geometry_config.dart';
import '../../models/rear_suspension_config.dart';
import '../../models/rider_config.dart';
import '../../models/spring_config.dart';
import '../../models/suspension_config.dart';

/// Yamaha Ténéré 700 (2025) baseline suspension configuration (FR-SM-006).
///
/// Provides stock factory values for the KYB USD 43 mm front fork and
/// KYB monoshock, based on manufacturer specifications and community
/// measurements.  These values serve as the default starting point for
/// the suspension simulation; downstream modules should call
/// [ConfigValidator.validate] before use.
///
/// Usage:
/// ```dart
/// final config = Tenere700Profile.baseline;
/// // Tweak rider weight only:
/// final custom = config.copyWith(
///   rider: const RiderConfig(weightKg: 90, gearWeightKg: 12),
/// );
/// ```
class Tenere700Profile {
  Tenere700Profile._();

  // ── Motorcycle ──────────────────────────────────────────────────────────────

  /// Stock motorcycle metadata for the Yamaha Ténéré 700 2025.
  static const MotorcycleConfig motorcycle = MotorcycleConfig(
    model: 'Yamaha Ténéré 700 2025',
    weightDryKg: 204.0,
  );

  // ── Rider ───────────────────────────────────────────────────────────────────

  /// Default reference rider (80 kg body + 10 kg gear).
  static const RiderConfig rider = RiderConfig(
    weightKg: 80.0,
    gearWeightKg: 10.0,
  );

  // ── Front fork (KYB USD 43 mm) ───────────────────────────────────────────

  /// Baseline front fork configuration for the Ténéré 700 2025.
  ///
  /// - Spring: linear, 9.0 N/mm, 10 mm preload
  /// - Damping: 10 clicks LSC/HSC/LSR/HSR (mid-range factory setting)
  /// - Geometry: 210 mm travel, 27° rake, 110 mm trail, 18 kg unsprung mass
  static const FrontSuspensionConfig front = FrontSuspensionConfig(
    spring: SpringConfig(
      type: SpringType.linear,
      springRateNPerMm: 9.0,
      preloadMm: 10.0,
    ),
    damping: DampingClicksConfig(
      compressionLowSpeedClicks: 10.0,
      compressionHighSpeedClicks: 10.0,
      reboundLowSpeedClicks: 10.0,
      reboundHighSpeedClicks: 10.0,
    ),
    geometry: FrontGeometryConfig(
      wheelTravelMaxMm: 210.0,
      rakeDeg: 27.0,
      trailMm: 110.0,
      unsprungMassKg: 18.0,
    ),
  );

  // ── Rear shock (KYB monoshock) ───────────────────────────────────────────

  /// Baseline rear suspension configuration for the Ténéré 700 2025.
  ///
  /// - Spring: linear, 95.0 N/mm, 5 mm preload
  /// - Damping: 8 clicks LSC/HSC, 10 clicks LSR/HSR (factory setting)
  /// - Linkage: constant ratio 2.8 (representative mid-stroke value)
  /// - Geometry: 200 mm wheel travel, 28 kg unsprung mass, 2.8 lever ratio
  static const RearSuspensionConfig rear = RearSuspensionConfig(
    spring: SpringConfig(
      type: SpringType.linear,
      springRateNPerMm: 95.0,
      preloadMm: 5.0,
    ),
    damping: DampingClicksConfig(
      compressionLowSpeedClicks: 8.0,
      compressionHighSpeedClicks: 8.0,
      reboundLowSpeedClicks: 10.0,
      reboundHighSpeedClicks: 10.0,
    ),
    linkage: LinkageConfig.constant(
      ratio: 2.8,
      wheelTravelMaxMm: 200.0,
    ),
    geometry: RearGeometryConfig(
      wheelTravelMaxMm: 200.0,
      unsprungMassKg: 28.0,
      leverRatio: 2.8,
    ),
  );

  // ── Baseline profile ─────────────────────────────────────────────────────

  /// Complete Ténéré 700 2025 baseline [SuspensionConfig].
  static const SuspensionConfig baseline = SuspensionConfig(
    motorcycle: motorcycle,
    rider: rider,
    front: front,
    rear: rear,
  );
}
