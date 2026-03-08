// Tests for ConfigValidator (FR-SM-006).
//
// Covers:
//   - Valid baseline config produces no errors
//   - Required-field validation: empty motorcycle model
//   - Range validation: motorcycle dry weight out of bounds
//   - Range validation: rider weight out of bounds
//   - Range validation: negative gear weight
//   - Range validation: spring rate <= 0
//   - Range validation: negative preload
//   - Range validation: damping clicks out of bounds
//   - Range validation: front travel <= 0
//   - Range validation: rear travel <= 0
//   - Range validation: lever ratio <= 0
//   - Range validation: linkage ratio <= 0
//   - Range validation: lookupTable with < 2 points
//   - Range validation: lookupTable with mismatched point lists

import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/models/damping_clicks_config.dart';
import 'package:ride_metric_x/models/front_geometry_config.dart';
import 'package:ride_metric_x/models/front_suspension_config.dart';
import 'package:ride_metric_x/models/linkage_config.dart';
import 'package:ride_metric_x/models/motorcycle_config.dart';
import 'package:ride_metric_x/models/rear_geometry_config.dart';
import 'package:ride_metric_x/models/rear_suspension_config.dart';
import 'package:ride_metric_x/models/rider_config.dart';
import 'package:ride_metric_x/models/spring_config.dart';
import 'package:ride_metric_x/models/suspension_config.dart';
import 'package:ride_metric_x/services/simulation/config_validator.dart';
import 'package:ride_metric_x/services/simulation/tenere700_profile.dart';

void main() {
  // ── Valid baseline ─────────────────────────────────────────────────────────

  group('ConfigValidator valid config', () {
    test('Tenere 700 baseline config is valid', () {
      final errors = ConfigValidator.validate(Tenere700Profile.baseline);
      expect(errors, isEmpty);
    });
  });

  // ── Motorcycle validation ─────────────────────────────────────────────────

  group('ConfigValidator motorcycle validation', () {
    SuspensionConfig withMoto(MotorcycleConfig m) =>
        Tenere700Profile.baseline.copyWith(motorcycle: m);

    test('empty model name is rejected', () {
      final errors = ConfigValidator.validate(
        withMoto(const MotorcycleConfig(model: '', weightDryKg: 200.0)),
      );
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('motorcycle.model')), isTrue);
    });

    test('whitespace-only model name is rejected', () {
      final errors = ConfigValidator.validate(
        withMoto(const MotorcycleConfig(model: '   ', weightDryKg: 200.0)),
      );
      expect(errors.any((e) => e.contains('motorcycle.model')), isTrue);
    });

    test('zero dry weight is rejected', () {
      final errors = ConfigValidator.validate(
        withMoto(const MotorcycleConfig(model: 'Bike', weightDryKg: 0.0)),
      );
      expect(errors.any((e) => e.contains('motorcycle.weightDryKg')), isTrue);
    });

    test('negative dry weight is rejected', () {
      final errors = ConfigValidator.validate(
        withMoto(const MotorcycleConfig(model: 'Bike', weightDryKg: -10.0)),
      );
      expect(errors.any((e) => e.contains('motorcycle.weightDryKg')), isTrue);
    });

    test('dry weight below minimum is rejected', () {
      final errors = ConfigValidator.validate(
        withMoto(
          const MotorcycleConfig(
            model: 'Bike',
            weightDryKg: MotorcycleConfig.kMinWeightDryKg - 1,
          ),
        ),
      );
      expect(errors.any((e) => e.contains('motorcycle.weightDryKg')), isTrue);
    });

    test('dry weight above maximum is rejected', () {
      final errors = ConfigValidator.validate(
        withMoto(
          const MotorcycleConfig(
            model: 'Bike',
            weightDryKg: MotorcycleConfig.kMaxWeightDryKg + 1,
          ),
        ),
      );
      expect(errors.any((e) => e.contains('motorcycle.weightDryKg')), isTrue);
    });
  });

  // ── Rider validation ──────────────────────────────────────────────────────

  group('ConfigValidator rider validation', () {
    SuspensionConfig withRider(RiderConfig r) =>
        Tenere700Profile.baseline.copyWith(rider: r);

    test('zero rider weight is rejected', () {
      final errors = ConfigValidator.validate(
        withRider(const RiderConfig(weightKg: 0.0)),
      );
      expect(errors.any((e) => e.contains('rider.weightKg')), isTrue);
    });

    test('rider weight below minimum is rejected', () {
      final errors = ConfigValidator.validate(
        withRider(const RiderConfig(weightKg: RiderConfig.kMinWeightKg - 1)),
      );
      expect(errors.any((e) => e.contains('rider.weightKg')), isTrue);
    });

    test('rider weight above maximum is rejected', () {
      final errors = ConfigValidator.validate(
        withRider(const RiderConfig(weightKg: RiderConfig.kMaxWeightKg + 1)),
      );
      expect(errors.any((e) => e.contains('rider.weightKg')), isTrue);
    });

    test('negative gear weight is rejected', () {
      final errors = ConfigValidator.validate(
        withRider(const RiderConfig(weightKg: 80.0, gearWeightKg: -1.0)),
      );
      expect(errors.any((e) => e.contains('rider.gearWeightKg')), isTrue);
    });

    test('gear weight above maximum is rejected', () {
      final errors = ConfigValidator.validate(
        withRider(
          const RiderConfig(
            weightKg: 80.0,
            gearWeightKg: RiderConfig.kMaxGearWeightKg + 1,
          ),
        ),
      );
      expect(errors.any((e) => e.contains('rider.gearWeightKg')), isTrue);
    });
  });

  // ── Spring validation ─────────────────────────────────────────────────────

  group('ConfigValidator spring validation', () {
    SuspensionConfig withFrontSpring(SpringConfig s) =>
        Tenere700Profile.baseline.copyWith(
          front: Tenere700Profile.front.copyWith(spring: s),
        );

    SuspensionConfig withRearSpring(SpringConfig s) =>
        Tenere700Profile.baseline.copyWith(
          rear: Tenere700Profile.rear.copyWith(spring: s),
        );

    test('front spring rate of zero is rejected', () {
      final errors = ConfigValidator.validate(
        withFrontSpring(
          const SpringConfig(type: SpringType.linear, springRateNPerMm: 0.0),
        ),
      );
      expect(
        errors.any((e) => e.contains('front.spring.springRateNPerMm')),
        isTrue,
      );
    });

    test('rear spring rate of zero is rejected', () {
      final errors = ConfigValidator.validate(
        withRearSpring(
          const SpringConfig(type: SpringType.linear, springRateNPerMm: 0.0),
        ),
      );
      expect(
        errors.any((e) => e.contains('rear.spring.springRateNPerMm')),
        isTrue,
      );
    });

    test('negative spring rate is rejected', () {
      final errors = ConfigValidator.validate(
        withFrontSpring(
          const SpringConfig(type: SpringType.linear, springRateNPerMm: -9.0),
        ),
      );
      expect(
        errors.any((e) => e.contains('front.spring.springRateNPerMm')),
        isTrue,
      );
    });

    test('negative preload is rejected', () {
      final errors = ConfigValidator.validate(
        withFrontSpring(
          const SpringConfig(
            type: SpringType.linear,
            springRateNPerMm: 9.0,
            preloadMm: -1.0,
          ),
        ),
      );
      expect(
        errors.any((e) => e.contains('front.spring.preloadMm')),
        isTrue,
      );
    });

    test('dualRate with zero breakpoint is rejected', () {
      final errors = ConfigValidator.validate(
        withFrontSpring(
          const SpringConfig(
            type: SpringType.dualRate,
            springRateNPerMm: 9.0,
            dualRateBreakpointMm: 0.0,
            secondarySpringRateNPerMm: 12.0,
          ),
        ),
      );
      expect(
        errors.any((e) => e.contains('front.spring.dualRateBreakpointMm')),
        isTrue,
      );
    });

    test('dualRate with zero secondary rate is rejected', () {
      final errors = ConfigValidator.validate(
        withFrontSpring(
          const SpringConfig(
            type: SpringType.dualRate,
            springRateNPerMm: 9.0,
            dualRateBreakpointMm: 50.0,
            secondarySpringRateNPerMm: 0.0,
          ),
        ),
      );
      expect(
        errors.any((e) => e.contains('front.spring.secondarySpringRateNPerMm')),
        isTrue,
      );
    });
  });

  // ── Damping clicks validation ─────────────────────────────────────────────

  group('ConfigValidator damping clicks validation', () {
    SuspensionConfig withFrontDamping(DampingClicksConfig d) =>
        Tenere700Profile.baseline.copyWith(
          front: Tenere700Profile.front.copyWith(damping: d),
        );

    test('negative LSC clicks are rejected', () {
      final errors = ConfigValidator.validate(
        withFrontDamping(
          const DampingClicksConfig(
            compressionLowSpeedClicks: -1.0,
            compressionHighSpeedClicks: 10.0,
            reboundLowSpeedClicks: 10.0,
            reboundHighSpeedClicks: 10.0,
          ),
        ),
      );
      expect(
        errors.any(
          (e) => e.contains('front.damping.compressionLowSpeedClicks'),
        ),
        isTrue,
      );
    });

    test('clicks above maximum are rejected', () {
      final errors = ConfigValidator.validate(
        withFrontDamping(
          const DampingClicksConfig(
            compressionLowSpeedClicks: DampingClicksConfig.kMaxClicks + 1,
            compressionHighSpeedClicks: 10.0,
            reboundLowSpeedClicks: 10.0,
            reboundHighSpeedClicks: 10.0,
          ),
        ),
      );
      expect(
        errors.any(
          (e) => e.contains('front.damping.compressionLowSpeedClicks'),
        ),
        isTrue,
      );
    });
  });

  // ── Geometry validation ───────────────────────────────────────────────────

  group('ConfigValidator geometry validation', () {
    SuspensionConfig withFrontGeo(FrontGeometryConfig g) =>
        Tenere700Profile.baseline.copyWith(
          front: Tenere700Profile.front.copyWith(geometry: g),
        );

    SuspensionConfig withRearGeo(RearGeometryConfig g) =>
        Tenere700Profile.baseline.copyWith(
          rear: Tenere700Profile.rear.copyWith(geometry: g),
        );

    test('front travel <= 0 is rejected', () {
      final errors = ConfigValidator.validate(
        withFrontGeo(
          const FrontGeometryConfig(
            wheelTravelMaxMm: 0.0,
            rakeDeg: 27.0,
            trailMm: 110.0,
            unsprungMassKg: 18.0,
          ),
        ),
      );
      expect(
        errors.any((e) => e.contains('front.geometry.wheelTravelMaxMm')),
        isTrue,
      );
    });

    test('rear travel <= 0 is rejected', () {
      final errors = ConfigValidator.validate(
        withRearGeo(
          const RearGeometryConfig(wheelTravelMaxMm: 0.0),
        ),
      );
      expect(
        errors.any((e) => e.contains('rear.geometry.wheelTravelMaxMm')),
        isTrue,
      );
    });

    test('negative front unsprung mass is rejected', () {
      final errors = ConfigValidator.validate(
        withFrontGeo(
          const FrontGeometryConfig(
            wheelTravelMaxMm: 210.0,
            unsprungMassKg: -1.0,
          ),
        ),
      );
      expect(
        errors.any((e) => e.contains('front.geometry.unsprungMassKg')),
        isTrue,
      );
    });

    test('negative rear unsprung mass is rejected', () {
      final errors = ConfigValidator.validate(
        withRearGeo(
          const RearGeometryConfig(
            wheelTravelMaxMm: 200.0,
            unsprungMassKg: -1.0,
          ),
        ),
      );
      expect(
        errors.any((e) => e.contains('rear.geometry.unsprungMassKg')),
        isTrue,
      );
    });

    test('rear lever ratio <= 0 is rejected', () {
      final errors = ConfigValidator.validate(
        withRearGeo(
          const RearGeometryConfig(
            wheelTravelMaxMm: 200.0,
            leverRatio: 0.0,
          ),
        ),
      );
      expect(
        errors.any((e) => e.contains('rear.geometry.leverRatio')),
        isTrue,
      );
    });

    test('rake angle out of [0, 90] is rejected', () {
      final errors = ConfigValidator.validate(
        withFrontGeo(
          const FrontGeometryConfig(
            wheelTravelMaxMm: 210.0,
            rakeDeg: 95.0,
          ),
        ),
      );
      expect(
        errors.any((e) => e.contains('front.geometry.rakeDeg')),
        isTrue,
      );
    });

    test('negative trail is rejected', () {
      final errors = ConfigValidator.validate(
        withFrontGeo(
          const FrontGeometryConfig(
            wheelTravelMaxMm: 210.0,
            trailMm: -5.0,
          ),
        ),
      );
      expect(
        errors.any((e) => e.contains('front.geometry.trailMm')),
        isTrue,
      );
    });
  });

  // ── Linkage validation ────────────────────────────────────────────────────

  group('ConfigValidator linkage validation', () {
    SuspensionConfig withLinkage(LinkageConfig l) =>
        Tenere700Profile.baseline.copyWith(
          rear: Tenere700Profile.rear.copyWith(linkage: l),
        );

    test('constant linkage with ratio <= 0 is rejected', () {
      final errors = ConfigValidator.validate(
        withLinkage(
          LinkageConfig.constant(ratio: 0.0, wheelTravelMaxMm: 200.0),
        ),
      );
      expect(
        errors.any((e) => e.contains('rear.linkage.constantRatio')),
        isTrue,
      );
    });

    test('constant linkage with travel <= 0 is rejected', () {
      final errors = ConfigValidator.validate(
        withLinkage(
          LinkageConfig.constant(ratio: 2.8, wheelTravelMaxMm: 0.0),
        ),
      );
      expect(
        errors.any((e) => e.contains('rear.linkage.wheelTravelMaxMm')),
        isTrue,
      );
    });

    test('progressive linkage with r0 <= 0 is rejected', () {
      final errors = ConfigValidator.validate(
        withLinkage(
          const LinkageConfig.progressive(r0: 0.0, wheelTravelMaxMm: 200.0),
        ),
      );
      expect(
        errors.any((e) => e.contains('rear.linkage.r0')),
        isTrue,
      );
    });

    test('lookupTable with < 2 travel points is rejected', () {
      final errors = ConfigValidator.validate(
        withLinkage(
          LinkageConfig.lookupTable(
            travelPoints: [0.0],
            ratioPoints: [2.8],
            wheelTravelMaxMm: 200.0,
          ),
        ),
      );
      expect(
        errors.any((e) => e.contains('travelPoints')),
        isTrue,
      );
    });

    test('lookupTable with mismatched point lists is rejected', () {
      final errors = ConfigValidator.validate(
        withLinkage(
          LinkageConfig.lookupTable(
            travelPoints: [0.0, 100.0, 200.0],
            ratioPoints: [2.8, 3.0],
            wheelTravelMaxMm: 200.0,
          ),
        ),
      );
      expect(
        errors.any((e) => e.contains('ratioPoints')),
        isTrue,
      );
    });

    test('valid lookupTable produces no errors', () {
      final errors = ConfigValidator.validate(
        withLinkage(
          LinkageConfig.lookupTable(
            travelPoints: [0.0, 100.0, 200.0],
            ratioPoints: [2.6, 2.8, 3.1],
            wheelTravelMaxMm: 200.0,
          ),
        ),
      );
      expect(errors, isEmpty);
    });
  });

  // ── Multiple errors ───────────────────────────────────────────────────────

  group('ConfigValidator multiple error accumulation', () {
    test('multiple violations are all reported', () {
      const config = SuspensionConfig(
        motorcycle: MotorcycleConfig(model: '', weightDryKg: -1.0),
        rider: RiderConfig(weightKg: -10.0, gearWeightKg: -5.0),
        front: FrontSuspensionConfig(
          spring: SpringConfig(
            type: SpringType.linear,
            springRateNPerMm: -9.0,
          ),
          damping: DampingClicksConfig(
            compressionLowSpeedClicks: 10.0,
            compressionHighSpeedClicks: 10.0,
            reboundLowSpeedClicks: 10.0,
            reboundHighSpeedClicks: 10.0,
          ),
          geometry: FrontGeometryConfig(wheelTravelMaxMm: 210.0),
        ),
        rear: RearSuspensionConfig(
          spring: SpringConfig(
            type: SpringType.linear,
            springRateNPerMm: 95.0,
          ),
          damping: DampingClicksConfig(
            compressionLowSpeedClicks: 8.0,
            compressionHighSpeedClicks: 8.0,
            reboundLowSpeedClicks: 10.0,
            reboundHighSpeedClicks: 10.0,
          ),
          linkage: LinkageConfig.constant(ratio: 2.8, wheelTravelMaxMm: 200.0),
          geometry: RearGeometryConfig(wheelTravelMaxMm: 200.0),
        ),
      );
      final errors = ConfigValidator.validate(config);
      // Expect at least: empty model, negative weight, negative rider weight,
      // negative gear weight, negative spring rate.
      expect(errors.length, greaterThanOrEqualTo(4));
    });
  });
}
