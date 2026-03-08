// Tests for the SuspensionConfig schema models (FR-SM-006).
//
// Covers:
//   - DampingClicksConfig: construction, copyWith, equality, hashCode, toString
//   - RearGeometryConfig: construction, copyWith, equality, hashCode, toString
//   - MotorcycleConfig: construction, copyWith, equality, hashCode, toString
//   - RiderConfig: construction, copyWith, equality, totalWeightKg, toString
//   - FrontSuspensionConfig: construction, copyWith, equality, toString
//   - RearSuspensionConfig: construction, copyWith, equality, toString
//   - SuspensionConfig: construction, copyWith, equality, toString

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

// ── Helpers ──────────────────────────────────────────────────────────────────

const _spring = SpringConfig(
  type: SpringType.linear,
  springRateNPerMm: 9.0,
  preloadMm: 5.0,
);

const _damping = DampingClicksConfig(
  compressionLowSpeedClicks: 10.0,
  compressionHighSpeedClicks: 10.0,
  reboundLowSpeedClicks: 10.0,
  reboundHighSpeedClicks: 10.0,
);

const _frontGeo = FrontGeometryConfig(
  wheelTravelMaxMm: 210.0,
  rakeDeg: 27.0,
  trailMm: 110.0,
  unsprungMassKg: 18.0,
);

const _rearGeo = RearGeometryConfig(
  wheelTravelMaxMm: 200.0,
  unsprungMassKg: 28.0,
  leverRatio: 2.8,
);

const _moto = MotorcycleConfig(model: 'Test Bike', weightDryKg: 200.0);
const _rider = RiderConfig(weightKg: 75.0, gearWeightKg: 8.0);

const _frontConfig = FrontSuspensionConfig(
  spring: _spring,
  damping: _damping,
  geometry: _frontGeo,
);

// ── DampingClicksConfig ───────────────────────────────────────────────────────

void main() {
  group('DampingClicksConfig', () {
    test('construction sets all fields', () {
      expect(_damping.compressionLowSpeedClicks, 10.0);
      expect(_damping.compressionHighSpeedClicks, 10.0);
      expect(_damping.reboundLowSpeedClicks, 10.0);
      expect(_damping.reboundHighSpeedClicks, 10.0);
    });

    test('copyWith overrides compressionLowSpeedClicks only', () {
      final d = _damping.copyWith(compressionLowSpeedClicks: 5.0);
      expect(d.compressionLowSpeedClicks, 5.0);
      expect(d.compressionHighSpeedClicks, 10.0);
      expect(d.reboundLowSpeedClicks, 10.0);
      expect(d.reboundHighSpeedClicks, 10.0);
    });

    test('copyWith returns equal instance when no field overridden', () {
      expect(_damping.copyWith(), equals(_damping));
    });

    test('equality holds for identical values', () {
      const a = DampingClicksConfig(
        compressionLowSpeedClicks: 8.0,
        compressionHighSpeedClicks: 8.0,
        reboundLowSpeedClicks: 12.0,
        reboundHighSpeedClicks: 12.0,
      );
      const b = DampingClicksConfig(
        compressionLowSpeedClicks: 8.0,
        compressionHighSpeedClicks: 8.0,
        reboundLowSpeedClicks: 12.0,
        reboundHighSpeedClicks: 12.0,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality when any field differs', () {
      const a = DampingClicksConfig(
        compressionLowSpeedClicks: 10.0,
        compressionHighSpeedClicks: 10.0,
        reboundLowSpeedClicks: 10.0,
        reboundHighSpeedClicks: 10.0,
      );
      expect(a, isNot(equals(a.copyWith(compressionLowSpeedClicks: 5.0))));
      expect(a, isNot(equals(a.copyWith(compressionHighSpeedClicks: 5.0))));
      expect(a, isNot(equals(a.copyWith(reboundLowSpeedClicks: 5.0))));
      expect(a, isNot(equals(a.copyWith(reboundHighSpeedClicks: 5.0))));
    });

    test('toString contains all field names', () {
      final s = _damping.toString();
      expect(s, contains('compressionLowSpeedClicks'));
      expect(s, contains('compressionHighSpeedClicks'));
      expect(s, contains('reboundLowSpeedClicks'));
      expect(s, contains('reboundHighSpeedClicks'));
    });

    test('bounds constants are defined', () {
      expect(DampingClicksConfig.kMinClicks, 0.0);
      expect(DampingClicksConfig.kMaxClicks, greaterThan(0.0));
    });
  });

  // ── RearGeometryConfig ─────────────────────────────────────────────────────

  group('RearGeometryConfig', () {
    test('construction sets all fields', () {
      expect(_rearGeo.wheelTravelMaxMm, 200.0);
      expect(_rearGeo.unsprungMassKg, 28.0);
      expect(_rearGeo.leverRatio, 2.8);
    });

    test('default unsprungMassKg is 0 and leverRatio is 1', () {
      const g = RearGeometryConfig(wheelTravelMaxMm: 200.0);
      expect(g.unsprungMassKg, 0.0);
      expect(g.leverRatio, 1.0);
    });

    test('copyWith overrides wheelTravelMaxMm only', () {
      final g = _rearGeo.copyWith(wheelTravelMaxMm: 220.0);
      expect(g.wheelTravelMaxMm, 220.0);
      expect(g.unsprungMassKg, 28.0);
      expect(g.leverRatio, 2.8);
    });

    test('copyWith returns equal instance when no field overridden', () {
      expect(_rearGeo.copyWith(), equals(_rearGeo));
    });

    test('equality holds for identical values', () {
      const a = RearGeometryConfig(
        wheelTravelMaxMm: 200.0,
        unsprungMassKg: 28.0,
        leverRatio: 2.8,
      );
      const b = RearGeometryConfig(
        wheelTravelMaxMm: 200.0,
        unsprungMassKg: 28.0,
        leverRatio: 2.8,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('toString contains key fields', () {
      final s = _rearGeo.toString();
      expect(s, contains('200.0'));
      expect(s, contains('28.0'));
      expect(s, contains('2.8'));
    });
  });

  // ── MotorcycleConfig ───────────────────────────────────────────────────────

  group('MotorcycleConfig', () {
    test('construction sets all fields', () {
      expect(_moto.model, 'Test Bike');
      expect(_moto.weightDryKg, 200.0);
    });

    test('copyWith overrides model only', () {
      final m = _moto.copyWith(model: 'Other Bike');
      expect(m.model, 'Other Bike');
      expect(m.weightDryKg, 200.0);
    });

    test('copyWith returns equal instance when no field overridden', () {
      expect(_moto.copyWith(), equals(_moto));
    });

    test('equality holds for identical values', () {
      const a = MotorcycleConfig(model: 'Bike A', weightDryKg: 200.0);
      const b = MotorcycleConfig(model: 'Bike A', weightDryKg: 200.0);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality when model differs', () {
      const a = MotorcycleConfig(model: 'A', weightDryKg: 200.0);
      const b = MotorcycleConfig(model: 'B', weightDryKg: 200.0);
      expect(a, isNot(equals(b)));
    });

    test('inequality when weightDryKg differs', () {
      const a = MotorcycleConfig(model: 'A', weightDryKg: 200.0);
      const b = MotorcycleConfig(model: 'A', weightDryKg: 201.0);
      expect(a, isNot(equals(b)));
    });

    test('toString contains model and weight', () {
      final s = _moto.toString();
      expect(s, contains('Test Bike'));
      expect(s, contains('200.0'));
    });

    test('bounds constants are defined', () {
      expect(MotorcycleConfig.kMinWeightDryKg, greaterThan(0));
      expect(MotorcycleConfig.kMaxWeightDryKg, greaterThan(0));
    });
  });

  // ── RiderConfig ────────────────────────────────────────────────────────────

  group('RiderConfig', () {
    test('construction sets all fields', () {
      expect(_rider.weightKg, 75.0);
      expect(_rider.gearWeightKg, 8.0);
    });

    test('default gearWeightKg is 0', () {
      const r = RiderConfig(weightKg: 80.0);
      expect(r.gearWeightKg, 0.0);
    });

    test('totalWeightKg sums body and gear', () {
      const r = RiderConfig(weightKg: 80.0, gearWeightKg: 10.0);
      expect(r.totalWeightKg, closeTo(90.0, 1e-9));
    });

    test('totalWeightKg equals weightKg when gearWeightKg is 0', () {
      const r = RiderConfig(weightKg: 80.0);
      expect(r.totalWeightKg, 80.0);
    });

    test('copyWith overrides weightKg only', () {
      final r = _rider.copyWith(weightKg: 90.0);
      expect(r.weightKg, 90.0);
      expect(r.gearWeightKg, 8.0);
    });

    test('copyWith returns equal instance when no field overridden', () {
      expect(_rider.copyWith(), equals(_rider));
    });

    test('equality holds for identical values', () {
      const a = RiderConfig(weightKg: 80.0, gearWeightKg: 10.0);
      const b = RiderConfig(weightKg: 80.0, gearWeightKg: 10.0);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality when weightKg differs', () {
      const a = RiderConfig(weightKg: 80.0);
      const b = RiderConfig(weightKg: 81.0);
      expect(a, isNot(equals(b)));
    });

    test('toString contains weight', () {
      final s = _rider.toString();
      expect(s, contains('75.0'));
    });

    test('bounds constants are defined', () {
      expect(RiderConfig.kMinWeightKg, greaterThan(0));
      expect(RiderConfig.kMaxWeightKg, greaterThan(RiderConfig.kMinWeightKg));
      expect(RiderConfig.kMinGearWeightKg, 0.0);
      expect(RiderConfig.kMaxGearWeightKg, greaterThan(0));
    });
  });

  // ── FrontSuspensionConfig ──────────────────────────────────────────────────

  group('FrontSuspensionConfig', () {
    test('construction sets all sub-configs', () {
      expect(_frontConfig.spring, equals(_spring));
      expect(_frontConfig.damping, equals(_damping));
      expect(_frontConfig.geometry, equals(_frontGeo));
    });

    test('copyWith overrides spring only', () {
      const newSpring = SpringConfig(
        type: SpringType.linear,
        springRateNPerMm: 12.0,
      );
      final f = _frontConfig.copyWith(spring: newSpring);
      expect(f.spring, equals(newSpring));
      expect(f.damping, equals(_damping));
      expect(f.geometry, equals(_frontGeo));
    });

    test('copyWith returns equal instance when no field overridden', () {
      expect(_frontConfig.copyWith(), equals(_frontConfig));
    });

    test('equality holds for identical sub-configs', () {
      const a = FrontSuspensionConfig(
        spring: _spring,
        damping: _damping,
        geometry: _frontGeo,
      );
      const b = FrontSuspensionConfig(
        spring: _spring,
        damping: _damping,
        geometry: _frontGeo,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('toString contains sub-config descriptions', () {
      final s = _frontConfig.toString();
      expect(s, contains('FrontSuspensionConfig'));
      expect(s, contains('spring:'));
      expect(s, contains('damping:'));
      expect(s, contains('geometry:'));
    });
  });

  // ── RearSuspensionConfig ───────────────────────────────────────────────────

  group('RearSuspensionConfig', () {
    late RearSuspensionConfig rearConfig;

    setUp(() {
      rearConfig = RearSuspensionConfig(
        spring: const SpringConfig(
          type: SpringType.linear,
          springRateNPerMm: 95.0,
          preloadMm: 5.0,
        ),
        damping: const DampingClicksConfig(
          compressionLowSpeedClicks: 8.0,
          compressionHighSpeedClicks: 8.0,
          reboundLowSpeedClicks: 10.0,
          reboundHighSpeedClicks: 10.0,
        ),
        linkage: LinkageConfig.constant(
          ratio: 2.8,
          wheelTravelMaxMm: 200.0,
        ),
        geometry: const RearGeometryConfig(
          wheelTravelMaxMm: 200.0,
          unsprungMassKg: 28.0,
          leverRatio: 2.8,
        ),
      );
    });

    test('construction sets all sub-configs', () {
      expect(rearConfig.spring.springRateNPerMm, 95.0);
      expect(rearConfig.damping.compressionLowSpeedClicks, 8.0);
      expect(rearConfig.linkage.wheelTravelMaxMm, 200.0);
      expect(rearConfig.geometry.leverRatio, 2.8);
    });

    test('copyWith overrides geometry only', () {
      final newGeo = const RearGeometryConfig(
        wheelTravelMaxMm: 220.0,
        unsprungMassKg: 30.0,
        leverRatio: 3.0,
      );
      final r = rearConfig.copyWith(geometry: newGeo);
      expect(r.geometry, equals(newGeo));
      expect(r.spring.springRateNPerMm, 95.0);
    });

    test('copyWith returns equal instance when no field overridden', () {
      expect(rearConfig.copyWith(), equals(rearConfig));
    });

    test('equality holds for identical sub-configs', () {
      final a = RearSuspensionConfig(
        spring: const SpringConfig(
          type: SpringType.linear,
          springRateNPerMm: 95.0,
          preloadMm: 5.0,
        ),
        damping: const DampingClicksConfig(
          compressionLowSpeedClicks: 8.0,
          compressionHighSpeedClicks: 8.0,
          reboundLowSpeedClicks: 10.0,
          reboundHighSpeedClicks: 10.0,
        ),
        linkage: LinkageConfig.constant(
          ratio: 2.8,
          wheelTravelMaxMm: 200.0,
        ),
        geometry: const RearGeometryConfig(
          wheelTravelMaxMm: 200.0,
          unsprungMassKg: 28.0,
          leverRatio: 2.8,
        ),
      );
      expect(rearConfig, equals(a));
      expect(rearConfig.hashCode, a.hashCode);
    });

    test('toString contains sub-config descriptions', () {
      final s = rearConfig.toString();
      expect(s, contains('RearSuspensionConfig'));
      expect(s, contains('spring:'));
      expect(s, contains('damping:'));
      expect(s, contains('linkage:'));
      expect(s, contains('geometry:'));
    });
  });

  // ── SuspensionConfig ───────────────────────────────────────────────────────

  group('SuspensionConfig', () {
    late SuspensionConfig config;

    setUp(() {
      config = SuspensionConfig(
        motorcycle: _moto,
        rider: _rider,
        front: _frontConfig,
        rear: RearSuspensionConfig(
          spring: _spring,
          damping: _damping,
          linkage: LinkageConfig.constant(
            ratio: 2.8,
            wheelTravelMaxMm: 200.0,
          ),
          geometry: _rearGeo,
        ),
      );
    });

    test('construction sets all top-level fields', () {
      expect(config.motorcycle, equals(_moto));
      expect(config.rider, equals(_rider));
      expect(config.front, equals(_frontConfig));
    });

    test('copyWith overrides rider only', () {
      const newRider = RiderConfig(weightKg: 90.0, gearWeightKg: 12.0);
      final c = config.copyWith(rider: newRider);
      expect(c.rider, equals(newRider));
      expect(c.motorcycle, equals(_moto));
      expect(c.front, equals(_frontConfig));
    });

    test('copyWith returns equal instance when no field overridden', () {
      expect(config.copyWith(), equals(config));
    });

    test('equality holds for identical top-level configs', () {
      final a = SuspensionConfig(
        motorcycle: _moto,
        rider: _rider,
        front: _frontConfig,
        rear: RearSuspensionConfig(
          spring: _spring,
          damping: _damping,
          linkage: LinkageConfig.constant(
            ratio: 2.8,
            wheelTravelMaxMm: 200.0,
          ),
          geometry: _rearGeo,
        ),
      );
      expect(config, equals(a));
      expect(config.hashCode, a.hashCode);
    });

    test('inequality when rider changes', () {
      const newRider = RiderConfig(weightKg: 99.0);
      expect(config, isNot(equals(config.copyWith(rider: newRider))));
    });

    test('toString contains top-level field names', () {
      final s = config.toString();
      expect(s, contains('SuspensionConfig'));
      expect(s, contains('motorcycle:'));
      expect(s, contains('rider:'));
      expect(s, contains('front:'));
      expect(s, contains('rear:'));
    });
  });
}
