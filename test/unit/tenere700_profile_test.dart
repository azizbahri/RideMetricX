// Tests for Tenere700Profile baseline (FR-SM-006).
//
// Covers:
//   - baseline() returns a valid SuspensionConfig (no validation errors)
//   - motorcycle metadata matches Ténéré 700 2025 specs
//   - rider reference values match docs
//   - front fork: spring rate, preload, damping clicks, geometry
//   - rear shock: spring rate, preload, damping clicks, linkage, geometry
//   - baseline config can be customised via copyWith
//   - repeated calls to baseline() return equal configs

import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/models/linkage_config.dart';
import 'package:ride_metric_x/models/spring_config.dart';
import 'package:ride_metric_x/services/simulation/config_validator.dart';
import 'package:ride_metric_x/services/simulation/tenere700_profile.dart';

void main() {
  group('Tenere700Profile – baseline config', () {
    // ── Validity ─────────────────────────────────────────────────────────────

    test('baseline passes ConfigValidator with no errors', () {
      final errors = ConfigValidator.validate(Tenere700Profile.baseline);
      expect(errors, isEmpty, reason: 'Errors: $errors');
    });

    test('repeated calls to baseline return equal configs', () {
      final a = Tenere700Profile.baseline;
      final b = Tenere700Profile.baseline;
      expect(a, equals(b));
    });
  });

  group('Tenere700Profile – motorcycle metadata', () {
    test('model name contains "Ténéré 700"', () {
      expect(
        Tenere700Profile.motorcycle.model,
        contains('Ténéré 700'),
      );
    });

    test('dry weight is 204 kg', () {
      expect(Tenere700Profile.motorcycle.weightDryKg, closeTo(204.0, 1e-9));
    });
  });

  group('Tenere700Profile – rider reference', () {
    test('rider weight is 80 kg', () {
      expect(Tenere700Profile.rider.weightKg, closeTo(80.0, 1e-9));
    });

    test('gear weight is 10 kg', () {
      expect(Tenere700Profile.rider.gearWeightKg, closeTo(10.0, 1e-9));
    });

    test('total rider weight is 90 kg', () {
      expect(Tenere700Profile.rider.totalWeightKg, closeTo(90.0, 1e-9));
    });
  });

  group('Tenere700Profile – front fork (KYB USD 43 mm)', () {
    test('spring type is linear', () {
      expect(Tenere700Profile.front.spring.type, SpringType.linear);
    });

    test('front spring rate is 9.0 N/mm', () {
      expect(
        Tenere700Profile.front.spring.springRateNPerMm,
        closeTo(9.0, 1e-9),
      );
    });

    test('front spring preload is 10 mm', () {
      expect(
        Tenere700Profile.front.spring.preloadMm,
        closeTo(10.0, 1e-9),
      );
    });

    test('front LSC clicks are 10', () {
      expect(
        Tenere700Profile.front.damping.compressionLowSpeedClicks,
        closeTo(10.0, 1e-9),
      );
    });

    test('front HSC clicks are 10', () {
      expect(
        Tenere700Profile.front.damping.compressionHighSpeedClicks,
        closeTo(10.0, 1e-9),
      );
    });

    test('front LSR clicks are 10', () {
      expect(
        Tenere700Profile.front.damping.reboundLowSpeedClicks,
        closeTo(10.0, 1e-9),
      );
    });

    test('front HSR clicks are 10', () {
      expect(
        Tenere700Profile.front.damping.reboundHighSpeedClicks,
        closeTo(10.0, 1e-9),
      );
    });

    test('front wheel travel is 210 mm', () {
      expect(
        Tenere700Profile.front.geometry.wheelTravelMaxMm,
        closeTo(210.0, 1e-9),
      );
    });

    test('front rake is 27 degrees', () {
      expect(Tenere700Profile.front.geometry.rakeDeg, closeTo(27.0, 1e-9));
    });

    test('front trail is 110 mm', () {
      expect(Tenere700Profile.front.geometry.trailMm, closeTo(110.0, 1e-9));
    });

    test('front unsprung mass is 18 kg', () {
      expect(
        Tenere700Profile.front.geometry.unsprungMassKg,
        closeTo(18.0, 1e-9),
      );
    });
  });

  group('Tenere700Profile – rear shock (KYB monoshock)', () {
    test('rear spring type is linear', () {
      expect(Tenere700Profile.rear.spring.type, SpringType.linear);
    });

    test('rear spring rate is 95.0 N/mm', () {
      expect(
        Tenere700Profile.rear.spring.springRateNPerMm,
        closeTo(95.0, 1e-9),
      );
    });

    test('rear spring preload is 5 mm', () {
      expect(
        Tenere700Profile.rear.spring.preloadMm,
        closeTo(5.0, 1e-9),
      );
    });

    test('rear LSC clicks are 8', () {
      expect(
        Tenere700Profile.rear.damping.compressionLowSpeedClicks,
        closeTo(8.0, 1e-9),
      );
    });

    test('rear HSC clicks are 8', () {
      expect(
        Tenere700Profile.rear.damping.compressionHighSpeedClicks,
        closeTo(8.0, 1e-9),
      );
    });

    test('rear LSR clicks are 10', () {
      expect(
        Tenere700Profile.rear.damping.reboundLowSpeedClicks,
        closeTo(10.0, 1e-9),
      );
    });

    test('rear HSR clicks are 10', () {
      expect(
        Tenere700Profile.rear.damping.reboundHighSpeedClicks,
        closeTo(10.0, 1e-9),
      );
    });

    test('rear linkage type is constant', () {
      expect(Tenere700Profile.rear.linkage.type, LinkageType.constant);
    });

    test('rear linkage ratio is 2.8', () {
      expect(
        Tenere700Profile.rear.linkage.constantRatio,
        closeTo(2.8, 1e-9),
      );
    });

    test('rear wheel travel is 200 mm', () {
      expect(
        Tenere700Profile.rear.geometry.wheelTravelMaxMm,
        closeTo(200.0, 1e-9),
      );
    });

    test('rear unsprung mass is 28 kg', () {
      expect(
        Tenere700Profile.rear.geometry.unsprungMassKg,
        closeTo(28.0, 1e-9),
      );
    });

    test('rear lever ratio is 2.8', () {
      expect(
        Tenere700Profile.rear.geometry.leverRatio,
        closeTo(2.8, 1e-9),
      );
    });
  });

  group('Tenere700Profile – copyWith customisation', () {
    test('rider weight can be overridden and config remains valid', () {
      final custom = Tenere700Profile.baseline.copyWith(
        rider: Tenere700Profile.rider.copyWith(weightKg: 95.0),
      );
      expect(custom.rider.weightKg, closeTo(95.0, 1e-9));
      // Other fields unchanged.
      expect(
        custom.motorcycle,
        equals(Tenere700Profile.motorcycle),
      );
      expect(ConfigValidator.validate(custom), isEmpty);
    });

    test('front spring rate can be overridden and config remains valid', () {
      final custom = Tenere700Profile.baseline.copyWith(
        front: Tenere700Profile.front.copyWith(
          spring: Tenere700Profile.front.spring.copyWith(
            springRateNPerMm: 10.0,
          ),
        ),
      );
      expect(custom.front.spring.springRateNPerMm, closeTo(10.0, 1e-9));
      expect(ConfigValidator.validate(custom), isEmpty);
    });
  });
}
