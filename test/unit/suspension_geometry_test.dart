// Tests for Suspension Geometry and Linkage Model (FR-SM-003).
//
// Covers:
//   - LinkageConfig model (construction, equality, toString)
//   - FrontGeometryConfig model (construction, copyWith, equality, toString)
//   - SuspensionGeometry service:
//     * UT-SM-007: linkage ratio application for all three models
//     * Forward/inverse conversion consistency (displacement, velocity, force)
//     * Travel boundary condition clamping
//     * Validation errors

import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/models/front_geometry_config.dart';
import 'package:ride_metric_x/models/linkage_config.dart';
import 'package:ride_metric_x/services/simulation/suspension_geometry.dart';

void main() {
  // ── LinkageConfig model ─────────────────────────────────────────────────────

  group('LinkageConfig', () {
    test('constant constructor stores fields correctly', () {
      const cfg = LinkageConfig.constant(ratio: 2.8, wheelTravelMaxMm: 200.0);
      expect(cfg.type, LinkageType.constant);
      expect(cfg.constantRatio, 2.8);
      expect(cfg.wheelTravelMaxMm, 200.0);
    });

    test('progressive constructor stores fields correctly', () {
      const cfg = LinkageConfig.progressive(
        r0: 2.0,
        r1: 0.005,
        r2: 0.00002,
        wheelTravelMaxMm: 200.0,
      );
      expect(cfg.type, LinkageType.progressive);
      expect(cfg.r0, 2.0);
      expect(cfg.r1, 0.005);
      expect(cfg.r2, 0.00002);
    });

    test('lookupTable constructor stores fields correctly', () {
      const cfg = LinkageConfig.lookupTable(
        travelPoints: [0.0, 100.0, 200.0],
        ratioPoints: [2.0, 2.8, 3.5],
        wheelTravelMaxMm: 200.0,
      );
      expect(cfg.type, LinkageType.lookupTable);
      expect(cfg.travelPoints, [0.0, 100.0, 200.0]);
      expect(cfg.ratioPoints, [2.0, 2.8, 3.5]);
    });

    test('constant equality holds for identical configs', () {
      const a = LinkageConfig.constant(ratio: 2.8, wheelTravelMaxMm: 200.0);
      const b = LinkageConfig.constant(ratio: 2.8, wheelTravelMaxMm: 200.0);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('equality fails when ratio differs', () {
      const a = LinkageConfig.constant(ratio: 2.8, wheelTravelMaxMm: 200.0);
      const b = LinkageConfig.constant(ratio: 3.0, wheelTravelMaxMm: 200.0);
      expect(a, isNot(equals(b)));
    });

    test('constant toString contains type and ratio', () {
      const cfg = LinkageConfig.constant(ratio: 2.8, wheelTravelMaxMm: 200.0);
      expect(cfg.toString(), contains('constant'));
      expect(cfg.toString(), contains('2.8'));
    });

    test('progressive toString contains type and coefficients', () {
      const cfg = LinkageConfig.progressive(
        r0: 2.0,
        r1: 0.005,
        wheelTravelMaxMm: 200.0,
      );
      expect(cfg.toString(), contains('progressive'));
      expect(cfg.toString(), contains('2.0'));
    });

    test('lookupTable toString contains type and point count', () {
      const cfg = LinkageConfig.lookupTable(
        travelPoints: [0.0, 100.0, 200.0],
        ratioPoints: [2.0, 2.8, 3.5],
        wheelTravelMaxMm: 200.0,
      );
      expect(cfg.toString(), contains('lookupTable'));
      expect(cfg.toString(), contains('3')); // 3 points
    });
  });

  // ── FrontGeometryConfig model ───────────────────────────────────────────────

  group('FrontGeometryConfig', () {
    test('required field and optional defaults', () {
      const cfg = FrontGeometryConfig(wheelTravelMaxMm: 210.0);
      expect(cfg.wheelTravelMaxMm, 210.0);
      expect(cfg.rakeDeg, 0.0);
      expect(cfg.trailMm, 0.0);
      expect(cfg.unsprungMassKg, 0.0);
    });

    test('all fields populated', () {
      const cfg = FrontGeometryConfig(
        wheelTravelMaxMm: 210.0,
        rakeDeg: 27.0,
        trailMm: 110.0,
        unsprungMassKg: 18.0,
      );
      expect(cfg.rakeDeg, 27.0);
      expect(cfg.trailMm, 110.0);
      expect(cfg.unsprungMassKg, 18.0);
    });

    test('copyWith replaces provided fields and preserves others', () {
      const cfg = FrontGeometryConfig(
        wheelTravelMaxMm: 210.0,
        rakeDeg: 27.0,
        trailMm: 110.0,
        unsprungMassKg: 18.0,
      );
      final updated = cfg.copyWith(rakeDeg: 25.0);
      expect(updated.rakeDeg, 25.0);
      expect(updated.wheelTravelMaxMm, 210.0); // unchanged
      expect(updated.trailMm, 110.0); // unchanged
    });

    test('equality holds for identical configs', () {
      const a = FrontGeometryConfig(
        wheelTravelMaxMm: 210.0,
        rakeDeg: 27.0,
        trailMm: 110.0,
        unsprungMassKg: 18.0,
      );
      const b = FrontGeometryConfig(
        wheelTravelMaxMm: 210.0,
        rakeDeg: 27.0,
        trailMm: 110.0,
        unsprungMassKg: 18.0,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('equality fails when field differs', () {
      const a = FrontGeometryConfig(wheelTravelMaxMm: 210.0, rakeDeg: 27.0);
      const b = FrontGeometryConfig(wheelTravelMaxMm: 210.0, rakeDeg: 28.0);
      expect(a, isNot(equals(b)));
    });

    test('toString contains key fields', () {
      const cfg = FrontGeometryConfig(
        wheelTravelMaxMm: 210.0,
        rakeDeg: 27.0,
        trailMm: 110.0,
        unsprungMassKg: 18.0,
      );
      expect(cfg.toString(), contains('210.0'));
      expect(cfg.toString(), contains('27.0'));
      expect(cfg.toString(), contains('110.0'));
      expect(cfg.toString(), contains('18.0'));
    });
  });

  // ── SuspensionGeometry – constant linkage ──────────────────────────────────

  group('SuspensionGeometry (constant linkage) – UT-SM-007', () {
    const cfg = LinkageConfig.constant(ratio: 2.8, wheelTravelMaxMm: 200.0);

    test('linkageRatioAt returns constant ratio at any displacement', () {
      expect(SuspensionGeometry.linkageRatioAt(cfg, 0.0), 2.8);
      expect(SuspensionGeometry.linkageRatioAt(cfg, 100.0), 2.8);
      expect(SuspensionGeometry.linkageRatioAt(cfg, 200.0), 2.8);
    });

    test('wheelToShockDisplacement: shockDisp = wheelDisp / ratio', () {
      final shock = SuspensionGeometry.wheelToShockDisplacement(cfg, 140.0);
      expect(shock, closeTo(140.0 / 2.8, 1e-10));
    });

    test('wheelToShockVelocity: shockVel = wheelVel / ratio', () {
      final vel = SuspensionGeometry.wheelToShockVelocity(cfg, 0.56, 100.0);
      expect(vel, closeTo(0.56 / 2.8, 1e-10));
    });

    test('wheelToShockVelocity preserves sign for rebound (negative velocity)',
        () {
      final vel = SuspensionGeometry.wheelToShockVelocity(cfg, -0.3, 50.0);
      expect(vel, lessThan(0.0));
      expect(vel, closeTo(-0.3 / 2.8, 1e-10));
    });

    test('shockToWheelForce: wheelForce = shockForce × ratio', () {
      final force = SuspensionGeometry.shockToWheelForce(cfg, 500.0, 100.0);
      expect(force, closeTo(500.0 * 2.8, 1e-10));
    });
  });

  // ── SuspensionGeometry – progressive linkage ───────────────────────────────

  group('SuspensionGeometry (progressive linkage) – UT-SM-007', () {
    // r(x) = 2.0 + 0.005·x + 0.00002·x²
    const cfg = LinkageConfig.progressive(
      r0: 2.0,
      r1: 0.005,
      r2: 0.00002,
      wheelTravelMaxMm: 200.0,
    );

    test('linkageRatioAt zero displacement equals r0', () {
      expect(SuspensionGeometry.linkageRatioAt(cfg, 0.0), closeTo(2.0, 1e-10));
    });

    test('linkageRatioAt 100 mm matches polynomial', () {
      // r(100) = 2.0 + 0.005*100 + 0.00002*10000 = 2.0 + 0.5 + 0.2 = 2.7
      expect(
        SuspensionGeometry.linkageRatioAt(cfg, 100.0),
        closeTo(2.7, 1e-10),
      );
    });

    test('linkageRatioAt 200 mm matches polynomial', () {
      // r(200) = 2.0 + 0.005*200 + 0.00002*40000 = 2.0 + 1.0 + 0.8 = 3.8
      expect(
        SuspensionGeometry.linkageRatioAt(cfg, 200.0),
        closeTo(3.8, 1e-10),
      );
    });

    test('ratio increases with displacement (progressive / rising-rate)', () {
      final r0 = SuspensionGeometry.linkageRatioAt(cfg, 0.0);
      final r100 = SuspensionGeometry.linkageRatioAt(cfg, 100.0);
      final r200 = SuspensionGeometry.linkageRatioAt(cfg, 200.0);
      expect(r100, greaterThan(r0));
      expect(r200, greaterThan(r100));
    });

    test('wheelToShockDisplacement uses displacement-dependent ratio', () {
      // At x=100 mm, r=2.7 → shock = 100/2.7 ≈ 37.04
      final shock = SuspensionGeometry.wheelToShockDisplacement(cfg, 100.0);
      expect(shock, closeTo(100.0 / 2.7, 1e-6));
    });
  });

  // ── SuspensionGeometry – lookup-table linkage ──────────────────────────────

  group('SuspensionGeometry (lookupTable linkage) – UT-SM-007', () {
    const cfg = LinkageConfig.lookupTable(
      travelPoints: [0.0, 100.0, 200.0],
      ratioPoints: [2.0, 2.8, 3.5],
      wheelTravelMaxMm: 200.0,
    );

    test('linkageRatioAt exact sample points returns stored ratios', () {
      expect(SuspensionGeometry.linkageRatioAt(cfg, 0.0), closeTo(2.0, 1e-10));
      expect(
          SuspensionGeometry.linkageRatioAt(cfg, 100.0), closeTo(2.8, 1e-10));
      expect(
          SuspensionGeometry.linkageRatioAt(cfg, 200.0), closeTo(3.5, 1e-10));
    });

    test('linkageRatioAt midpoint is linearly interpolated', () {
      // Between 0 and 100: r(50) = 2.0 + 0.5*(2.8-2.0) = 2.4
      expect(
        SuspensionGeometry.linkageRatioAt(cfg, 50.0),
        closeTo(2.4, 1e-10),
      );
    });

    test('linkageRatioAt second segment midpoint (150 mm)', () {
      // Between 100 and 200: r(150) = 2.8 + 0.5*(3.5-2.8) = 3.15
      expect(
        SuspensionGeometry.linkageRatioAt(cfg, 150.0),
        closeTo(3.15, 1e-10),
      );
    });

    test('shockToWheelForce at table midpoint uses interpolated ratio', () {
      // r(50) = 2.4; wheel_force = 500 × 2.4 = 1200
      expect(
        SuspensionGeometry.shockToWheelForce(cfg, 500.0, 50.0),
        closeTo(1200.0, 1e-6),
      );
    });
  });

  // ── Forward / inverse conversion consistency ───────────────────────────────

  group('Forward/inverse conversion consistency', () {
    const cfg = LinkageConfig.constant(ratio: 3.0, wheelTravelMaxMm: 200.0);

    test(
        'wheelToShockDisplacement followed by shockToWheelForce is self-consistent',
        () {
      const shockForce = 1000.0; // N
      const wheelDisp = 90.0; // mm
      // Get ratio at this displacement.
      final ratio = SuspensionGeometry.linkageRatioAt(cfg, wheelDisp);
      // Compute shock displacement.
      final shockDisp =
          SuspensionGeometry.wheelToShockDisplacement(cfg, wheelDisp);
      // The wheel force recovered from shock force should equal shock × ratio.
      final wheelForce =
          SuspensionGeometry.shockToWheelForce(cfg, shockForce, wheelDisp);
      expect(shockDisp, closeTo(wheelDisp / ratio, 1e-10));
      expect(wheelForce, closeTo(shockForce * ratio, 1e-10));
    });

    test('velocity and displacement transforms use the same ratio', () {
      const wheelDisp = 60.0;
      const wheelVel = 0.5;
      final ratio = SuspensionGeometry.linkageRatioAt(cfg, wheelDisp);
      final shockVel =
          SuspensionGeometry.wheelToShockVelocity(cfg, wheelVel, wheelDisp);
      final shockDisp =
          SuspensionGeometry.wheelToShockDisplacement(cfg, wheelDisp);
      // Both transforms must divide by the same ratio.
      expect(shockVel / wheelVel, closeTo(shockDisp / wheelDisp, 1e-10));
    });

    test('round-trip: wheelForce == shockForce * ratio (progressive)', () {
      const progCfg = LinkageConfig.progressive(
        r0: 2.5,
        r1: 0.003,
        wheelTravelMaxMm: 200.0,
      );
      const shockForce = 800.0;
      const wheelDisp = 120.0;
      final ratio = SuspensionGeometry.linkageRatioAt(progCfg, wheelDisp);
      final wheelForce =
          SuspensionGeometry.shockToWheelForce(progCfg, shockForce, wheelDisp);
      expect(wheelForce, closeTo(shockForce * ratio, 1e-6));
    });
  });

  // ── Travel boundary conditions ─────────────────────────────────────────────

  group('Travel boundary conditions', () {
    const cfg = LinkageConfig.constant(ratio: 2.8, wheelTravelMaxMm: 200.0);

    test('linkageRatioAt clamps negative displacement to zero', () {
      expect(
        SuspensionGeometry.linkageRatioAt(cfg, -10.0),
        SuspensionGeometry.linkageRatioAt(cfg, 0.0),
      );
    });

    test('linkageRatioAt clamps over-travel to wheelTravelMaxMm', () {
      expect(
        SuspensionGeometry.linkageRatioAt(cfg, 250.0),
        SuspensionGeometry.linkageRatioAt(cfg, 200.0),
      );
    });

    test(
        'wheelToShockDisplacement clamps over-travel and returns shock at max',
        () {
      final atMax = SuspensionGeometry.wheelToShockDisplacement(cfg, 200.0);
      final overMax = SuspensionGeometry.wheelToShockDisplacement(cfg, 250.0);
      expect(overMax, closeTo(atMax, 1e-10));
    });

    test('wheelToShockDisplacement at zero travel returns zero shock', () {
      expect(
        SuspensionGeometry.wheelToShockDisplacement(cfg, 0.0),
        closeTo(0.0, 1e-10),
      );
    });

    test(
        'lookup-table: displacement below first point clamps to first ratio', () {
      const ltCfg = LinkageConfig.lookupTable(
        travelPoints: [10.0, 100.0, 200.0],
        ratioPoints: [2.0, 2.8, 3.5],
        wheelTravelMaxMm: 200.0,
      );
      // Displacement 0 < first table point 10, so clamped displacement = 0
      // which is below xs.first (10) → returns ratios.first (2.0).
      expect(
        SuspensionGeometry.linkageRatioAt(ltCfg, 0.0),
        closeTo(2.0, 1e-10),
      );
    });

    test(
        'lookup-table: displacement above last point clamps to last ratio', () {
      const ltCfg = LinkageConfig.lookupTable(
        travelPoints: [0.0, 100.0, 190.0],
        ratioPoints: [2.0, 2.8, 3.4],
        wheelTravelMaxMm: 200.0,
      );
      // Clamped to 200 → above xs.last (190) → returns ratios.last (3.4).
      expect(
        SuspensionGeometry.linkageRatioAt(ltCfg, 200.0),
        closeTo(3.4, 1e-10),
      );
    });
  });

  // ── Validation errors ──────────────────────────────────────────────────────

  group('SuspensionGeometry validation errors', () {
    test('throws for non-positive wheelTravelMaxMm', () {
      const cfg = LinkageConfig.constant(ratio: 2.8, wheelTravelMaxMm: -1.0);
      expect(
        () => SuspensionGeometry.linkageRatioAt(cfg, 0.0),
        throwsArgumentError,
      );
    });

    test('throws for non-positive constant ratio', () {
      const cfg = LinkageConfig.constant(ratio: 0.0, wheelTravelMaxMm: 200.0);
      expect(
        () => SuspensionGeometry.linkageRatioAt(cfg, 0.0),
        throwsArgumentError,
      );
    });

    test('throws for non-positive progressive r0', () {
      const cfg = LinkageConfig.progressive(
        r0: -1.0,
        wheelTravelMaxMm: 200.0,
      );
      expect(
        () => SuspensionGeometry.linkageRatioAt(cfg, 0.0),
        throwsArgumentError,
      );
    });

    test('throws for lookup table with fewer than two points', () {
      const cfg = LinkageConfig.lookupTable(
        travelPoints: [0.0],
        ratioPoints: [2.0],
        wheelTravelMaxMm: 200.0,
      );
      expect(
        () => SuspensionGeometry.linkageRatioAt(cfg, 0.0),
        throwsArgumentError,
      );
    });

    test('throws for lookup table with mismatched lengths', () {
      const cfg = LinkageConfig.lookupTable(
        travelPoints: [0.0, 100.0],
        ratioPoints: [2.0, 2.8, 3.5],
        wheelTravelMaxMm: 200.0,
      );
      expect(
        () => SuspensionGeometry.linkageRatioAt(cfg, 0.0),
        throwsArgumentError,
      );
    });

    test('throws for non-ascending lookup table travel points', () {
      const cfg = LinkageConfig.lookupTable(
        travelPoints: [100.0, 0.0],
        ratioPoints: [2.0, 2.8],
        wheelTravelMaxMm: 200.0,
      );
      expect(
        () => SuspensionGeometry.linkageRatioAt(cfg, 0.0),
        throwsArgumentError,
      );
    });

    test('throws for non-positive ratio in lookup table', () {
      const cfg = LinkageConfig.lookupTable(
        travelPoints: [0.0, 100.0],
        ratioPoints: [2.0, 0.0],
        wheelTravelMaxMm: 200.0,
      );
      expect(
        () => SuspensionGeometry.linkageRatioAt(cfg, 0.0),
        throwsArgumentError,
      );
    });
  });
}
