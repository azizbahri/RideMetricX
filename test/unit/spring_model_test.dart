// Tests for Spring Models and Sag Calculations (FR-SM-001, FR-SM-008).
//
// Covers:
//   - SpringConfig model (construction, copyWith, equality)
//   - SpringForceResult model (equality, toString)
//   - SagResult model (equality, toString)
//   - SpringModel:
//     * UT-SM-001: linear spring force and elastic energy
//     * UT-SM-002: progressive spring force and elastic energy
//     * Dual-rate spring below and above breakpoint
//     * Boundary cases (zero displacement, negative displacement)
//     * Validation errors (invalid spring rate)
//   - SagCalculator:
//     * Free sag and static sag formula (reference values from docs)
//     * Zero rider weight (static sag == free sag)
//     * Boundary / validation errors (zero spring rate, negative weights)

import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/models/sag_result.dart';
import 'package:ride_metric_x/models/spring_config.dart';
import 'package:ride_metric_x/models/spring_force_result.dart';
import 'package:ride_metric_x/services/simulation/sag_calculator.dart';
import 'package:ride_metric_x/services/simulation/spring_model.dart';

void main() {
  // ── SpringConfig ────────────────────────────────────────────────────────────

  group('SpringConfig', () {
    test('default optional fields are zero', () {
      const cfg = SpringConfig(
        type: SpringType.linear,
        springRateNPerMm: 9.0,
      );
      expect(cfg.preloadMm, 0.0);
      expect(cfg.progressiveRateNPerMm2, 0.0);
      expect(cfg.dualRateBreakpointMm, 0.0);
      expect(cfg.secondarySpringRateNPerMm, 0.0);
    });

    test('copyWith replaces provided fields', () {
      const cfg = SpringConfig(
        type: SpringType.linear,
        springRateNPerMm: 9.0,
        preloadMm: 5.0,
      );
      final updated = cfg.copyWith(springRateNPerMm: 12.0);
      expect(updated.springRateNPerMm, 12.0);
      expect(updated.preloadMm, 5.0); // unchanged
      expect(updated.type, SpringType.linear); // unchanged
    });

    test('equality holds for identical configs', () {
      const a = SpringConfig(
        type: SpringType.progressive,
        springRateNPerMm: 10.0,
        progressiveRateNPerMm2: 0.05,
      );
      const b = SpringConfig(
        type: SpringType.progressive,
        springRateNPerMm: 10.0,
        progressiveRateNPerMm2: 0.05,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('equality fails when fields differ', () {
      const a = SpringConfig(
        type: SpringType.linear,
        springRateNPerMm: 9.0,
      );
      const b = SpringConfig(
        type: SpringType.linear,
        springRateNPerMm: 10.0,
      );
      expect(a, isNot(equals(b)));
    });

    test('toString contains key fields', () {
      const cfg = SpringConfig(
        type: SpringType.dualRate,
        springRateNPerMm: 9.0,
      );
      final s = cfg.toString();
      expect(s, contains('dualRate'));
      expect(s, contains('9.0'));
    });
  });

  // ── SpringForceResult ───────────────────────────────────────────────────────

  group('SpringForceResult', () {
    test('equality holds for identical results', () {
      const a = SpringForceResult(forceN: 100.0, elasticEnergyJ: 5.0);
      const b = SpringForceResult(forceN: 100.0, elasticEnergyJ: 5.0);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('toString contains force and energy', () {
      const r = SpringForceResult(forceN: 270.0, elasticEnergyJ: 4.05);
      final s = r.toString();
      expect(s, contains('270.0'));
      expect(s, contains('4.05'));
    });
  });

  // ── SagResult ───────────────────────────────────────────────────────────────

  group('SagResult', () {
    test('equality holds for identical results', () {
      const a = SagResult(freeSagMm: 21.0, staticSagMm: 29.0);
      const b = SagResult(freeSagMm: 21.0, staticSagMm: 29.0);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('toString contains free and static sag', () {
      const r = SagResult(freeSagMm: 21.0, staticSagMm: 29.0);
      final s = r.toString();
      expect(s, contains('21.0'));
      expect(s, contains('29.0'));
    });
  });

  // ── SpringModel — UT-SM-001: linear spring ──────────────────────────────────

  group('SpringModel – linear (UT-SM-001)', () {
    const k = 9.0; // N/mm — typical front fork (Tenere 700)
    const linearConfig = SpringConfig(
      type: SpringType.linear,
      springRateNPerMm: k,
    );

    test('zero displacement produces zero force and zero energy', () {
      final result = SpringModel.calculateForce(
        linearConfig,
        displacementMm: 0.0,
      );
      expect(result.forceN, 0.0);
      expect(result.elasticEnergyJ, 0.0);
    });

    test('30 mm displacement → 270 N', () {
      final result = SpringModel.calculateForce(
        linearConfig,
        displacementMm: 30.0,
      );
      expect(result.forceN, closeTo(270.0, 1e-9));
    });

    test('30 mm displacement → elastic energy ½k x² = 4.05 J', () {
      // ½ × 9 N/mm × 30² mm² = 4050 N·mm = 4.05 J
      final result = SpringModel.calculateForce(
        linearConfig,
        displacementMm: 30.0,
      );
      expect(result.elasticEnergyJ, closeTo(4.05, 1e-9));
    });

    test('force scales linearly with displacement', () {
      for (final x in [10.0, 50.0, 100.0, 200.0]) {
        final result = SpringModel.calculateForce(
          linearConfig,
          displacementMm: x,
        );
        expect(result.forceN, closeTo(k * x, 1e-9));
      }
    });

    test('negative displacement produces negative (extension) force', () {
      final result = SpringModel.calculateForce(
        linearConfig,
        displacementMm: -10.0,
      );
      expect(result.forceN, closeTo(-90.0, 1e-9));
    });

    test('rear spring (95 N/mm) at 40 mm → 3800 N', () {
      const rearConfig = SpringConfig(
        type: SpringType.linear,
        springRateNPerMm: 95.0,
      );
      final result = SpringModel.calculateForce(
        rearConfig,
        displacementMm: 40.0,
      );
      expect(result.forceN, closeTo(3800.0, 1e-9));
    });

    test('throws ArgumentError for zero spring rate', () {
      const badConfig = SpringConfig(
        type: SpringType.linear,
        springRateNPerMm: 0.0,
      );
      expect(
        () => SpringModel.calculateForce(badConfig, displacementMm: 10.0),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for negative spring rate', () {
      const badConfig = SpringConfig(
        type: SpringType.linear,
        springRateNPerMm: -5.0,
      );
      expect(
        () => SpringModel.calculateForce(badConfig, displacementMm: 10.0),
        throwsArgumentError,
      );
    });

    test('preloadMm does not change force/energy for a given displacement', () {
      // preloadMm is stored on the config for use by higher-level solvers;
      // SpringModel.calculateForce uses only displacementMm and rate coefficients.
      const preloadConfig = SpringConfig(
        type: SpringType.linear,
        springRateNPerMm: k,
        preloadMm: 10.0,
      );
      final result = SpringModel.calculateForce(
        preloadConfig,
        displacementMm: 30.0,
      );
      expect(result.forceN, closeTo(270.0, 1e-9)); // k × x = 9 × 30
      expect(result.elasticEnergyJ, closeTo(4.05, 1e-9)); // ½ × k × x²
    });
  });

  // ── SpringModel — UT-SM-002: progressive spring ─────────────────────────────

  group('SpringModel – progressive (UT-SM-002)', () {
    const k1 = 9.0; // N/mm
    const k2 = 0.05; // N/mm²
    const progressiveConfig = SpringConfig(
      type: SpringType.progressive,
      springRateNPerMm: k1,
      progressiveRateNPerMm2: k2,
    );

    test('zero displacement produces zero force and zero energy', () {
      final result = SpringModel.calculateForce(
        progressiveConfig,
        displacementMm: 0.0,
      );
      expect(result.forceN, 0.0);
      expect(result.elasticEnergyJ, 0.0);
    });

    test('30 mm → F = k1·x + k2·x² = 270 + 45 = 315 N', () {
      final result = SpringModel.calculateForce(
        progressiveConfig,
        displacementMm: 30.0,
      );
      // k1 × 30 + k2 × 30² = 9×30 + 0.05×900 = 270 + 45 = 315
      expect(result.forceN, closeTo(315.0, 1e-9));
    });

    test('30 mm → elastic energy = (½ k1 x² + ⅓ k2 x³) / 1000', () {
      final result = SpringModel.calculateForce(
        progressiveConfig,
        displacementMm: 30.0,
      );
      // ½×9×900 = 4050  +  ⅓×0.05×27000 = 450  → 4500 N·mm = 4.5 J
      expect(result.elasticEnergyJ, closeTo(4.5, 1e-9));
    });

    test('progressive force exceeds linear force at same displacement', () {
      const linearConfig = SpringConfig(
        type: SpringType.linear,
        springRateNPerMm: k1,
      );
      const x = 50.0;
      final linearResult = SpringModel.calculateForce(
        linearConfig,
        displacementMm: x,
      );
      final progressiveResult = SpringModel.calculateForce(
        progressiveConfig,
        displacementMm: x,
      );
      expect(progressiveResult.forceN, greaterThan(linearResult.forceN));
    });

    test('force increases faster than linearly as displacement grows', () {
      final r1 = SpringModel.calculateForce(
        progressiveConfig,
        displacementMm: 20.0,
      );
      final r2 = SpringModel.calculateForce(
        progressiveConfig,
        displacementMm: 40.0,
      );
      // In a linear spring the force would exactly double; in a progressive
      // spring doubling displacement more than doubles the force.
      expect(r2.forceN, greaterThan(r1.forceN * 2.0));
    });

    test('throws ArgumentError for negative displacement', () {
      expect(
        () => SpringModel.calculateForce(
          progressiveConfig,
          displacementMm: -10.0,
        ),
        throwsArgumentError,
      );
    });
  });

  // ── SpringModel — dual-rate spring ─────────────────────────────────────────

  group('SpringModel – dual-rate', () {
    const k1 = 8.0; // N/mm (primary rate)
    const k2 = 14.0; // N/mm (secondary rate, stiffer beyond breakpoint)
    const bp = 50.0; // mm breakpoint
    const dualConfig = SpringConfig(
      type: SpringType.dualRate,
      springRateNPerMm: k1,
      dualRateBreakpointMm: bp,
      secondarySpringRateNPerMm: k2,
    );

    test('displacement below breakpoint uses primary rate', () {
      final result = SpringModel.calculateForce(
        dualConfig,
        displacementMm: 30.0,
      );
      expect(result.forceN, closeTo(k1 * 30.0, 1e-9)); // 8 × 30 = 240
    });

    test('displacement at breakpoint is on the primary rate curve', () {
      final result = SpringModel.calculateForce(
        dualConfig,
        displacementMm: bp,
      );
      expect(result.forceN, closeTo(k1 * bp, 1e-9)); // 8 × 50 = 400
    });

    test('displacement above breakpoint uses secondary rate for overflow', () {
      // F = k1 × bp + k2 × (x - bp) = 8×50 + 14×20 = 400 + 280 = 680
      final result = SpringModel.calculateForce(
        dualConfig,
        displacementMm: 70.0,
      );
      expect(result.forceN, closeTo(680.0, 1e-9));
    });

    test('force is continuous at the breakpoint (no jump)', () {
      final below = SpringModel.calculateForce(
        dualConfig,
        displacementMm: bp - 0.001,
      );
      final above = SpringModel.calculateForce(
        dualConfig,
        displacementMm: bp + 0.001,
      );
      expect((above.forceN - below.forceN).abs(), lessThan(1.0));
    });

    test('elastic energy below breakpoint = ½ k1 x²', () {
      final result = SpringModel.calculateForce(
        dualConfig,
        displacementMm: 30.0,
      );
      // ½ × 8 × 30² = 3600 N·mm = 3.6 J
      expect(result.elasticEnergyJ, closeTo(3.6, 1e-9));
    });

    test('elastic energy above breakpoint is continuous', () {
      final atBp = SpringModel.calculateForce(
        dualConfig,
        displacementMm: bp,
      );
      final justAbove = SpringModel.calculateForce(
        dualConfig,
        displacementMm: bp + 1.0,
      );
      expect(justAbove.elasticEnergyJ, greaterThan(atBp.elasticEnergyJ));
    });

    test('throws ArgumentError for zero secondary spring rate', () {
      const badConfig = SpringConfig(
        type: SpringType.dualRate,
        springRateNPerMm: 8.0,
        dualRateBreakpointMm: 50.0,
        secondarySpringRateNPerMm: 0.0,
      );
      expect(
        () => SpringModel.calculateForce(badConfig, displacementMm: 10.0),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for zero breakpoint', () {
      const badConfig = SpringConfig(
        type: SpringType.dualRate,
        springRateNPerMm: 8.0,
        dualRateBreakpointMm: 0.0,
        secondarySpringRateNPerMm: 14.0,
      );
      expect(
        () => SpringModel.calculateForce(badConfig, displacementMm: 10.0),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for negative breakpoint', () {
      const badConfig = SpringConfig(
        type: SpringType.dualRate,
        springRateNPerMm: 8.0,
        dualRateBreakpointMm: -5.0,
        secondarySpringRateNPerMm: 14.0,
      );
      expect(
        () => SpringModel.calculateForce(badConfig, displacementMm: 10.0),
        throwsArgumentError,
      );
    });
  });

  // ── SagCalculator ───────────────────────────────────────────────────────────

  group('SagCalculator', () {
    test('reference: 90 kg total on 95 N/mm rear spring → ~9.3 mm', () {
      // From docs: (90 × 9.81) / 95 ≈ 9.3 mm
      final result = SagCalculator.calculate(
        springRateNPerMm: 95.0,
        bikeWeightKg: 90.0,
        riderWeightKg: 0.0,
      );
      expect(result.freeSagMm, closeTo(9.3, 0.1));
    });

    test('free sag: (bikeWeight × 9.81) / springRate', () {
      final result = SagCalculator.calculate(
        springRateNPerMm: 9.0,
        bikeWeightKg: 102.0, // half of 204 kg on front
        riderWeightKg: 0.0,
      );
      expect(result.freeSagMm, closeTo((102.0 * 9.81) / 9.0, 1e-9));
    });

    test('static sag: ((bikeWeight + riderWeight) × 9.81) / springRate', () {
      final result = SagCalculator.calculate(
        springRateNPerMm: 9.0,
        bikeWeightKg: 102.0,
        riderWeightKg: 80.0,
      );
      expect(
        result.staticSagMm,
        closeTo((102.0 + 80.0) * 9.81 / 9.0, 1e-9),
      );
    });

    test('staticSagMm > freeSagMm when riderWeightKg > 0', () {
      final result = SagCalculator.calculate(
        springRateNPerMm: 9.0,
        bikeWeightKg: 102.0,
        riderWeightKg: 80.0,
      );
      expect(result.staticSagMm, greaterThan(result.freeSagMm));
    });

    test('staticSagMm == freeSagMm when riderWeightKg == 0', () {
      final result = SagCalculator.calculate(
        springRateNPerMm: 9.0,
        bikeWeightKg: 102.0,
        riderWeightKg: 0.0,
      );
      expect(result.staticSagMm, closeTo(result.freeSagMm, 1e-9));
    });

    test('zero bike weight → zero sag', () {
      final result = SagCalculator.calculate(
        springRateNPerMm: 9.0,
        bikeWeightKg: 0.0,
        riderWeightKg: 0.0,
      );
      expect(result.freeSagMm, 0.0);
      expect(result.staticSagMm, 0.0);
    });

    test('sag decreases as spring rate increases (stiffer spring)', () {
      final soft = SagCalculator.calculate(
        springRateNPerMm: 9.0,
        bikeWeightKg: 102.0,
        riderWeightKg: 80.0,
      );
      final stiff = SagCalculator.calculate(
        springRateNPerMm: 12.0,
        bikeWeightKg: 102.0,
        riderWeightKg: 80.0,
      );
      expect(stiff.staticSagMm, lessThan(soft.staticSagMm));
    });

    test('throws ArgumentError for zero spring rate', () {
      expect(
        () => SagCalculator.calculate(
          springRateNPerMm: 0.0,
          bikeWeightKg: 102.0,
          riderWeightKg: 80.0,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for negative spring rate', () {
      expect(
        () => SagCalculator.calculate(
          springRateNPerMm: -5.0,
          bikeWeightKg: 102.0,
          riderWeightKg: 80.0,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for negative bike weight', () {
      expect(
        () => SagCalculator.calculate(
          springRateNPerMm: 9.0,
          bikeWeightKg: -1.0,
          riderWeightKg: 0.0,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for negative rider weight', () {
      expect(
        () => SagCalculator.calculate(
          springRateNPerMm: 9.0,
          bikeWeightKg: 102.0,
          riderWeightKg: -5.0,
        ),
        throwsArgumentError,
      );
    });
  });
}
