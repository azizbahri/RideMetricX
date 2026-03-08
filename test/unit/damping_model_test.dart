// Tests for Damping Models and Click Mapping (FR-SM-002, FR-SM-007).
//
// Covers:
//   - DampingConfig model (construction, copyWith, equality)
//   - DampingForceResult model (equality, toString)
//   - DampingModel:
//     * UT-SM-003: linear damping force (compression)
//     * UT-SM-004: linear damping force (rebound)
//     * UT-SM-005: bi-linear damping threshold transition
//     * Non-linear damping extension hook
//     * Boundary cases (zero velocity)
//     * Validation errors (invalid coefficients, invalid threshold)
//   - ClickMapper (FR-SM-007):
//     * Monotonicity across click range
//     * Boundary values (0 clicks, max clicks)
//     * Coefficient range (1× to 3×)
//     * Validation errors (out-of-range clicks, non-positive inputs)

import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/models/damping_config.dart';
import 'package:ride_metric_x/models/damping_force_result.dart';
import 'package:ride_metric_x/services/simulation/click_mapper.dart';
import 'package:ride_metric_x/services/simulation/damping_model.dart';

void main() {
  // ── DampingConfig ───────────────────────────────────────────────────────────

  group('DampingConfig', () {
    test('default optional fields are zero / default', () {
      const cfg = DampingConfig(
        type: DampingType.linear,
        lowSpeedCoefficientNsPerMm: 10.0,
      );
      expect(cfg.highSpeedCoefficientNsPerMm, 0.0);
      expect(cfg.velocityThresholdMps, 0.5);
      expect(cfg.nonLinearDCoefficientNs2PerMm2, 0.0);
    });

    test('copyWith replaces provided fields', () {
      const cfg = DampingConfig(
        type: DampingType.linear,
        lowSpeedCoefficientNsPerMm: 10.0,
        velocityThresholdMps: 0.5,
      );
      final updated = cfg.copyWith(lowSpeedCoefficientNsPerMm: 15.0);
      expect(updated.lowSpeedCoefficientNsPerMm, 15.0);
      expect(updated.velocityThresholdMps, 0.5); // unchanged
      expect(updated.type, DampingType.linear); // unchanged
    });

    test('equality holds for identical configs', () {
      const a = DampingConfig(
        type: DampingType.biLinear,
        lowSpeedCoefficientNsPerMm: 10.0,
        highSpeedCoefficientNsPerMm: 4.0,
        velocityThresholdMps: 0.5,
      );
      const b = DampingConfig(
        type: DampingType.biLinear,
        lowSpeedCoefficientNsPerMm: 10.0,
        highSpeedCoefficientNsPerMm: 4.0,
        velocityThresholdMps: 0.5,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('equality fails when fields differ', () {
      const a = DampingConfig(
        type: DampingType.linear,
        lowSpeedCoefficientNsPerMm: 10.0,
      );
      const b = DampingConfig(
        type: DampingType.linear,
        lowSpeedCoefficientNsPerMm: 12.0,
      );
      expect(a, isNot(equals(b)));
    });

    test('toString contains key fields', () {
      const cfg = DampingConfig(
        type: DampingType.biLinear,
        lowSpeedCoefficientNsPerMm: 10.0,
      );
      final s = cfg.toString();
      expect(s, contains('biLinear'));
      expect(s, contains('10.0'));
    });
  });

  // ── DampingForceResult ──────────────────────────────────────────────────────

  group('DampingForceResult', () {
    test('equality holds for identical results', () {
      const a = DampingForceResult(forceN: 3000.0);
      const b = DampingForceResult(forceN: 3000.0);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('equality fails when force differs', () {
      const a = DampingForceResult(forceN: 3000.0);
      const b = DampingForceResult(forceN: 4000.0);
      expect(a, isNot(equals(b)));
    });

    test('toString contains force value', () {
      const r = DampingForceResult(forceN: 3000.0);
      expect(r.toString(), contains('3000.0'));
    });
  });

  // ── DampingModel — UT-SM-003: linear damping, compression ──────────────────

  group('DampingModel – linear compression (UT-SM-003)', () {
    const c = 10.0; // N·s/mm — typical low-speed damping coefficient
    const linearConfig = DampingConfig(
      type: DampingType.linear,
      lowSpeedCoefficientNsPerMm: c,
    );

    test('zero velocity produces zero force', () {
      final result = DampingModel.calculateForce(
        linearConfig,
        velocityMps: 0.0,
      );
      expect(result.forceN, 0.0);
    });

    test('0.3 m/s compression → F = c × v = 10 × 300 = 3000 N', () {
      // v = 0.3 m/s = 300 mm/s; F = 10 N·s/mm × 300 mm/s = 3000 N
      final result = DampingModel.calculateForce(
        linearConfig,
        velocityMps: 0.3,
      );
      expect(result.forceN, closeTo(3000.0, 1e-9));
    });

    test('force scales linearly with compression velocity', () {
      for (final v in [0.1, 0.3, 0.5, 1.0]) {
        final result = DampingModel.calculateForce(
          linearConfig,
          velocityMps: v,
        );
        expect(result.forceN, closeTo(c * v * 1000.0, 1e-9));
      }
    });

    test('compression force is positive (opposes compression)', () {
      final result = DampingModel.calculateForce(
        linearConfig,
        velocityMps: 0.5,
      );
      expect(result.forceN, greaterThan(0));
    });

    test('throws ArgumentError for zero coefficient', () {
      const badConfig = DampingConfig(
        type: DampingType.linear,
        lowSpeedCoefficientNsPerMm: 0.0,
      );
      expect(
        () => DampingModel.calculateForce(badConfig, velocityMps: 0.3),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for negative coefficient', () {
      const badConfig = DampingConfig(
        type: DampingType.linear,
        lowSpeedCoefficientNsPerMm: -5.0,
      );
      expect(
        () => DampingModel.calculateForce(badConfig, velocityMps: 0.3),
        throwsArgumentError,
      );
    });
  });

  // ── DampingModel — UT-SM-004: linear damping, rebound ──────────────────────

  group('DampingModel – linear rebound (UT-SM-004)', () {
    const c = 12.0; // N·s/mm — slightly higher rebound coefficient
    const linearConfig = DampingConfig(
      type: DampingType.linear,
      lowSpeedCoefficientNsPerMm: c,
    );

    test('−0.3 m/s rebound → F = c × v = 12 × (−300) = −3600 N', () {
      // v = −0.3 m/s = −300 mm/s; F = 12 × −300 = −3600 N
      final result = DampingModel.calculateForce(
        linearConfig,
        velocityMps: -0.3,
      );
      expect(result.forceN, closeTo(-3600.0, 1e-9));
    });

    test('rebound force is negative (opposes extension)', () {
      final result = DampingModel.calculateForce(
        linearConfig,
        velocityMps: -0.5,
      );
      expect(result.forceN, lessThan(0));
    });

    test('force magnitude scales linearly with rebound velocity', () {
      for (final v in [0.1, 0.3, 0.5, 1.0]) {
        final result = DampingModel.calculateForce(
          linearConfig,
          velocityMps: -v,
        );
        expect(result.forceN, closeTo(-c * v * 1000.0, 1e-9));
      }
    });

    test('compression and rebound forces are antisymmetric for same |v|', () {
      const v = 0.4;
      final comp = DampingModel.calculateForce(linearConfig, velocityMps: v);
      final reb = DampingModel.calculateForce(linearConfig, velocityMps: -v);
      expect(comp.forceN, closeTo(-reb.forceN, 1e-9));
    });
  });

  // ── DampingModel — UT-SM-005: bi-linear damping transition ─────────────────

  group('DampingModel – bi-linear threshold transition (UT-SM-005)', () {
    const cLow = 10.0; // N·s/mm  low-speed coefficient
    const cHigh = 4.0; // N·s/mm  high-speed coefficient (softer at high speed)
    const threshold = 0.5; // m/s
    const biLinearConfig = DampingConfig(
      type: DampingType.biLinear,
      lowSpeedCoefficientNsPerMm: cLow,
      highSpeedCoefficientNsPerMm: cHigh,
      velocityThresholdMps: threshold,
    );

    // Derived offset: (c_low - c_high) × threshold_mm_s
    const threshMmS = threshold * 1000.0; // 500 mm/s

    test('velocity below threshold uses low-speed coefficient', () {
      // v = 0.3 m/s = 300 mm/s < 500 mm/s
      final result = DampingModel.calculateForce(
        biLinearConfig,
        velocityMps: 0.3,
      );
      expect(result.forceN, closeTo(cLow * 300.0, 1e-9)); // 3000 N
    });

    test('velocity above threshold uses high-speed coefficient + offset', () {
      // v = 0.8 m/s = 800 mm/s > 500 mm/s
      // offset = (cLow - cHigh) × threshMmS = (10-4) × 500 = 3000
      // F = cHigh × 800 + offset = 4×800 + 3000 = 3200 + 3000 = 6200 N
      final result = DampingModel.calculateForce(
        biLinearConfig,
        velocityMps: 0.8,
      );
      const expected = cHigh * 800.0 + (cLow - cHigh) * threshMmS;
      expect(result.forceN, closeTo(expected, 1e-9));
    });

    test('force is continuous at the threshold (no jump)', () {
      // Use a tiny delta (1e-9 m/s = 1e-6 mm/s) so the slope difference between
      // the two regimes (~14 N·s/mm) contributes only ~1.4e-5 N over the span.
      final justBelow = DampingModel.calculateForce(
        biLinearConfig,
        velocityMps: threshold - 1e-9,
      );
      final justAbove = DampingModel.calculateForce(
        biLinearConfig,
        velocityMps: threshold + 1e-9,
      );
      expect((justAbove.forceN - justBelow.forceN).abs(), lessThan(1.0));
    });

    test('force at threshold equals c_low × threshold', () {
      // Exactly at threshold (|v| == threshold, uses low-speed branch)
      final result = DampingModel.calculateForce(
        biLinearConfig,
        velocityMps: threshold - 1e-12, // just below
      );
      expect(result.forceN, closeTo(cLow * threshMmS, 1e-6));
    });

    test('bi-linear rebound: force is negative and continuous at −threshold', () {
      final justBelow = DampingModel.calculateForce(
        biLinearConfig,
        velocityMps: -(threshold - 1e-9),
      );
      final justAbove = DampingModel.calculateForce(
        biLinearConfig,
        velocityMps: -(threshold + 1e-9),
      );
      expect(justBelow.forceN, lessThan(0));
      expect(justAbove.forceN, lessThan(0));
      expect((justAbove.forceN - justBelow.forceN).abs(), lessThan(1.0));
    });

    test('high-speed slope is less steep than low-speed slope', () {
      // Above threshold, every extra 0.1 m/s adds less force than below.
      const delta = 0.1;
      final atLS1 = DampingModel.calculateForce(
        biLinearConfig,
        velocityMps: 0.1,
      );
      final atLS2 = DampingModel.calculateForce(
        biLinearConfig,
        velocityMps: 0.1 + delta,
      );
      final atHS1 = DampingModel.calculateForce(
        biLinearConfig,
        velocityMps: 0.8,
      );
      final atHS2 = DampingModel.calculateForce(
        biLinearConfig,
        velocityMps: 0.8 + delta,
      );
      final lsSlope = atLS2.forceN - atLS1.forceN;
      final hsSlope = atHS2.forceN - atHS1.forceN;
      expect(hsSlope, lessThan(lsSlope));
    });

    test('throws ArgumentError for zero high-speed coefficient', () {
      const badConfig = DampingConfig(
        type: DampingType.biLinear,
        lowSpeedCoefficientNsPerMm: 10.0,
        highSpeedCoefficientNsPerMm: 0.0,
        velocityThresholdMps: 0.5,
      );
      expect(
        () => DampingModel.calculateForce(badConfig, velocityMps: 0.3),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for zero velocity threshold', () {
      const badConfig = DampingConfig(
        type: DampingType.biLinear,
        lowSpeedCoefficientNsPerMm: 10.0,
        highSpeedCoefficientNsPerMm: 4.0,
        velocityThresholdMps: 0.0,
      );
      expect(
        () => DampingModel.calculateForce(badConfig, velocityMps: 0.3),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for negative velocity threshold', () {
      const badConfig = DampingConfig(
        type: DampingType.biLinear,
        lowSpeedCoefficientNsPerMm: 10.0,
        highSpeedCoefficientNsPerMm: 4.0,
        velocityThresholdMps: -0.5,
      );
      expect(
        () => DampingModel.calculateForce(badConfig, velocityMps: 0.3),
        throwsArgumentError,
      );
    });
  });

  // ── DampingModel — non-linear extension hook ────────────────────────────────

  group('DampingModel – non-linear', () {
    const c = 8.0; // N·s/mm
    const d = 0.01; // N·s²/mm²
    const nonLinearConfig = DampingConfig(
      type: DampingType.nonLinear,
      lowSpeedCoefficientNsPerMm: c,
      nonLinearDCoefficientNs2PerMm2: d,
    );

    test('zero velocity produces zero force', () {
      final result = DampingModel.calculateForce(
        nonLinearConfig,
        velocityMps: 0.0,
      );
      expect(result.forceN, 0.0);
    });

    test('positive velocity: F = c×v + d×v²×sign(v) with sign(v)=+1', () {
      // v = 0.5 m/s = 500 mm/s
      // F = 8×500 + 0.01×500²×1 = 4000 + 2500 = 6500 N
      final result = DampingModel.calculateForce(
        nonLinearConfig,
        velocityMps: 0.5,
      );
      const vMmS = 500.0;
      expect(result.forceN, closeTo(c * vMmS + d * vMmS * vMmS, 1e-9));
    });

    test('negative velocity: F = c×v + d×v²×sign(v) with sign(v)=−1', () {
      // v = −0.5 m/s = −500 mm/s
      // F = 8×(−500) + 0.01×500²×(−1) = −4000 − 2500 = −6500 N
      final result = DampingModel.calculateForce(
        nonLinearConfig,
        velocityMps: -0.5,
      );
      const vMmS = -500.0;
      expect(
        result.forceN,
        closeTo(c * vMmS + d * vMmS * vMmS * -1.0, 1e-9),
      );
    });

    test('non-linear force exceeds linear force at same velocity', () {
      const linearConfig = DampingConfig(
        type: DampingType.linear,
        lowSpeedCoefficientNsPerMm: c,
      );
      const v = 0.5;
      final linear = DampingModel.calculateForce(linearConfig, velocityMps: v);
      final nonLinear = DampingModel.calculateForce(
        nonLinearConfig,
        velocityMps: v,
      );
      expect(nonLinear.forceN, greaterThan(linear.forceN));
    });

    test('non-linear force is antisymmetric (|F(v)| == |F(−v)|)', () {
      const v = 0.4;
      final pos = DampingModel.calculateForce(nonLinearConfig, velocityMps: v);
      final neg = DampingModel.calculateForce(nonLinearConfig, velocityMps: -v);
      expect(pos.forceN, closeTo(-neg.forceN, 1e-9));
    });
  });

  // ── ClickMapper — FR-SM-007 ─────────────────────────────────────────────────

  group('ClickMapper – click-to-coefficient conversion (FR-SM-007)', () {
    const base = 10.0; // N·s/mm base coefficient

    test('0 clicks returns base coefficient (softest, factor = 1.0)', () {
      final c = ClickMapper.clicksToCoefficient(0, base);
      expect(c, closeTo(base * 1.0, 1e-9));
    });

    test('20 clicks returns 3× base coefficient (hardest, factor = 3.0)', () {
      final c = ClickMapper.clicksToCoefficient(20, base);
      expect(c, closeTo(base * 3.0, 1e-9));
    });

    test('10 clicks returns 2× base coefficient (midpoint, factor = 2.0)', () {
      final c = ClickMapper.clicksToCoefficient(10, base);
      expect(c, closeTo(base * 2.0, 1e-9));
    });

    test('coefficient is monotonically increasing with clicks', () {
      double prev = ClickMapper.clicksToCoefficient(0, base);
      for (int clicks = 1; clicks <= 20; clicks++) {
        final current = ClickMapper.clicksToCoefficient(clicks, base);
        expect(current, greaterThan(prev));
        prev = current;
      }
    });

    test('factor scales linearly: (clicks/range) × 2 + 1', () {
      for (int clicks = 0; clicks <= 20; clicks++) {
        final result = ClickMapper.clicksToCoefficient(clicks, base);
        final expectedFactor = 1.0 + (clicks / 20) * 2.0;
        expect(result, closeTo(base * expectedFactor, 1e-9));
      }
    });

    test('custom clicksRange changes the scaling', () {
      // With 10-click range: at 5 clicks, factor = 1 + (5/10)×2 = 2.0
      final c = ClickMapper.clicksToCoefficient(5, base, clicksRange: 10);
      expect(c, closeTo(base * 2.0, 1e-9));
    });

    test('coefficient minimum is baseCoefficient (at 0 clicks)', () {
      for (int clicks = 0; clicks <= 20; clicks++) {
        final c = ClickMapper.clicksToCoefficient(clicks, base);
        expect(c, greaterThanOrEqualTo(base));
      }
    });

    test('coefficient maximum is 3 × baseCoefficient (at max clicks)', () {
      for (int clicks = 0; clicks <= 20; clicks++) {
        final c = ClickMapper.clicksToCoefficient(clicks, base);
        expect(c, lessThanOrEqualTo(base * 3.0 + 1e-9));
      }
    });

    test('throws ArgumentError for negative clicks', () {
      expect(
        () => ClickMapper.clicksToCoefficient(-1, base),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for clicks exceeding clicksRange', () {
      expect(
        () => ClickMapper.clicksToCoefficient(21, base),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for zero clicksRange', () {
      expect(
        () => ClickMapper.clicksToCoefficient(0, base, clicksRange: 0),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for negative clicksRange', () {
      expect(
        () => ClickMapper.clicksToCoefficient(0, base, clicksRange: -5),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for zero base coefficient', () {
      expect(
        () => ClickMapper.clicksToCoefficient(10, 0.0),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for negative base coefficient', () {
      expect(
        () => ClickMapper.clicksToCoefficient(10, -5.0),
        throwsArgumentError,
      );
    });
  });
}
