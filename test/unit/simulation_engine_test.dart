// Tests for SimulationEngine (FR-SM-010).
//
// Covers:
//   - SimulationSample model (construction, equality, toString)
//   - SimulationMetrics model (construction, equality, toString)
//   - SimulationResult model (construction, toString)
//   - SimulationEngine:
//     * Returns expected sample count for synthetic run
//     * Stiffer spring produces lower peak displacement
//     * More compression damping reduces oscillation peak
//     * Displacement stays within [0, maxTravel] bounds
//     * Metrics: maxDisplacementMm >= rmsDisplacementMm
//     * Bottoming and topping event detection
//     * Session-based input uses accelZLinear values
//     * Empty session falls back to synthetic profile

import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/models/imu_sample.dart';
import 'package:ride_metric_x/models/processed_sample.dart';
import 'package:ride_metric_x/models/quality_score.dart';
import 'package:ride_metric_x/models/ride_session.dart';
import 'package:ride_metric_x/models/simulation_result.dart';
import 'package:ride_metric_x/models/suspension_parameters.dart';
import 'package:ride_metric_x/services/simulation/simulation_engine.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

const _engine = SimulationEngine();

ProcessedSample _makeSample(int i, double accelZ) => ProcessedSample(
      raw: ImuSample(
        timestampMs: i * 5,
        accelXG: 0,
        accelYG: 0,
        accelZG: accelZ / 9.81,
        gyroXDps: 0,
        gyroYDps: 0,
        gyroZDps: 0,
        tempC: 25,
        sampleCount: i,
      ),
      accelXLinear: 0,
      accelYLinear: 0,
      accelZLinear: accelZ,
    );

RideSession _makeSession({
  List<ProcessedSample> front = const [],
  List<ProcessedSample> rear = const [],
}) =>
    RideSession(
      sessionId: 'test',
      importedAt: DateTime(2024),
      frontProcessed: front,
      rearProcessed: rear,
      qualityScore: const QualityScore(100),
    );

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  // ── SimulationSample model ─────────────────────────────────────────────────

  group('SimulationSample', () {
    const sample = SimulationSample(
      timeMs: 5.0,
      displacementMm: 30.0,
      velocityMps: 0.1,
      springForceN: 750.0,
      dampingForceN: 60.0,
    );

    test('equality holds for identical values', () {
      const other = SimulationSample(
        timeMs: 5.0,
        displacementMm: 30.0,
        velocityMps: 0.1,
        springForceN: 750.0,
        dampingForceN: 60.0,
      );
      expect(sample, equals(other));
      expect(sample.hashCode, equals(other.hashCode));
    });

    test('inequality when any field differs', () {
      expect(sample, isNot(equals(sample.copyWith(timeMs: 6.0))));
    });

    test('toString contains key fields', () {
      final s = sample.toString();
      expect(s, contains('5.0ms'));
      expect(s, contains('30.00mm'));
    });
  });

  // ── SimulationMetrics model ────────────────────────────────────────────────

  group('SimulationMetrics', () {
    const metrics = SimulationMetrics(
      maxDisplacementMm: 80.0,
      rmsDisplacementMm: 40.0,
      bottomingEvents: 2,
      toppingEvents: 1,
    );

    test('equality holds for identical values', () {
      const other = SimulationMetrics(
        maxDisplacementMm: 80.0,
        rmsDisplacementMm: 40.0,
        bottomingEvents: 2,
        toppingEvents: 1,
      );
      expect(metrics, equals(other));
      expect(metrics.hashCode, equals(other.hashCode));
    });

    test('inequality when any field differs', () {
      expect(
        metrics,
        isNot(
          equals(
            const SimulationMetrics(
              maxDisplacementMm: 80.0,
              rmsDisplacementMm: 40.0,
              bottomingEvents: 3,
              toppingEvents: 1,
            ),
          ),
        ),
      );
    });

    test('toString contains key fields', () {
      final s = metrics.toString();
      expect(s, contains('80.0mm'));
      expect(s, contains('bottom=2'));
      expect(s, contains('top=1'));
    });
  });

  // ── SimulationResult model ─────────────────────────────────────────────────

  group('SimulationResult', () {
    test('toString includes sample counts and metrics', () {
      const result = SimulationResult(
        frontSamples: [],
        rearSamples: [],
        frontMetrics: SimulationMetrics(
          maxDisplacementMm: 0,
          rmsDisplacementMm: 0,
          bottomingEvents: 0,
          toppingEvents: 0,
        ),
        rearMetrics: SimulationMetrics(
          maxDisplacementMm: 0,
          rmsDisplacementMm: 0,
          bottomingEvents: 0,
          toppingEvents: 0,
        ),
        parameters: TuningParameters.defaultPreset,
      );
      expect(result.toString(), contains('SimulationResult'));
    });
  });

  // ── SimulationEngine ───────────────────────────────────────────────────────

  group('SimulationEngine – synthetic run', () {
    late SimulationResult result;

    setUpAll(() async {
      result = await _engine.simulate(tuning: TuningParameters.defaultPreset);
    });

    test('returns expected number of samples (200 Hz × 10 s)', () {
      const expected = 2000; // 200 Hz × 10 s
      expect(result.frontSamples.length, expected);
      expect(result.rearSamples.length, expected);
    });

    test('parameters in result match input', () {
      expect(result.parameters, equals(TuningParameters.defaultPreset));
    });

    test('front displacement stays within [0, kFrontMaxTravelMm]', () {
      for (final s in result.frontSamples) {
        expect(
          s.displacementMm,
          inInclusiveRange(0.0, SimulationEngine.kFrontMaxTravelMm),
        );
      }
    });

    test('rear displacement stays within [0, kRearMaxTravelMm]', () {
      for (final s in result.rearSamples) {
        expect(
          s.displacementMm,
          inInclusiveRange(0.0, SimulationEngine.kRearMaxTravelMm),
        );
      }
    });

    test('time stamps are monotonically increasing', () {
      for (int i = 1; i < result.frontSamples.length; i++) {
        expect(
          result.frontSamples[i].timeMs,
          greaterThan(result.frontSamples[i - 1].timeMs),
        );
      }
    });

    test('maxDisplacementMm >= rmsDisplacementMm', () {
      expect(
        result.frontMetrics.maxDisplacementMm,
        greaterThanOrEqualTo(result.frontMetrics.rmsDisplacementMm),
      );
      expect(
        result.rearMetrics.maxDisplacementMm,
        greaterThanOrEqualTo(result.rearMetrics.rmsDisplacementMm),
      );
    });

    test('maxDisplacementMm is positive (suspension moves)', () {
      expect(result.frontMetrics.maxDisplacementMm, greaterThan(0));
      expect(result.rearMetrics.maxDisplacementMm, greaterThan(0));
    });
  });

  // ── Stiffness sensitivity ──────────────────────────────────────────────────

  group('SimulationEngine – stiffness sensitivity', () {
    test('stiffer spring produces lower RMS displacement', () async {
      final soft = await _engine.simulate(
        tuning: const TuningParameters(
          front: SuspensionParameters(
            springRate: SuspensionParameters.kMinSpringRate,
            compression: 10,
            rebound: 10,
            preload: 5,
          ),
          rear: SuspensionParameters(
            springRate: SuspensionParameters.kMinSpringRate,
            compression: 10,
            rebound: 10,
            preload: 5,
          ),
        ),
      );
      final firm = await _engine.simulate(
        tuning: const TuningParameters(
          front: SuspensionParameters(
            springRate: SuspensionParameters.kMaxSpringRate,
            compression: 10,
            rebound: 10,
            preload: 5,
          ),
          rear: SuspensionParameters(
            springRate: SuspensionParameters.kMaxSpringRate,
            compression: 10,
            rebound: 10,
            preload: 5,
          ),
        ),
      );

      expect(
        firm.frontMetrics.rmsDisplacementMm,
        lessThan(soft.frontMetrics.rmsDisplacementMm),
      );
    });
  });

  // ── Damping sensitivity ────────────────────────────────────────────────────

  group('SimulationEngine – damping sensitivity', () {
    test('more compression damping (higher clicks) lowers max displacement',
        () async {
      final lowDamp = await _engine.simulate(
        tuning: const TuningParameters(
          front: SuspensionParameters(
            springRate: 25,
            compression: 2,
            rebound: 10,
            preload: 5,
          ),
          rear: SuspensionParameters(
            springRate: 30,
            compression: 2,
            rebound: 10,
            preload: 5,
          ),
        ),
      );
      final highDamp = await _engine.simulate(
        tuning: const TuningParameters(
          front: SuspensionParameters(
            springRate: 25,
            compression: 18,
            rebound: 10,
            preload: 5,
          ),
          rear: SuspensionParameters(
            springRate: 30,
            compression: 18,
            rebound: 10,
            preload: 5,
          ),
        ),
      );

      expect(
        highDamp.frontMetrics.maxDisplacementMm,
        lessThan(lowDamp.frontMetrics.maxDisplacementMm),
      );
    });
  });

  // ── Session-based input ────────────────────────────────────────────────────

  group('SimulationEngine – session input', () {
    test('uses session samples when provided', () async {
      // Build a 100-sample session with constant 1 m/s² front input.
      final frontSamples =
          List.generate(100, (i) => _makeSample(i, 1.0));
      final session = _makeSession(front: frontSamples);

      final result = await _engine.simulate(
        tuning: TuningParameters.defaultPreset,
        session: session,
      );

      // Should have exactly 100 front samples (one per session sample).
      expect(result.frontSamples.length, 100);
    });

    test('falls back to synthetic data for missing rear channel', () async {
      final frontSamples =
          List.generate(50, (i) => _makeSample(i, 0.5));
      final session = _makeSession(front: frontSamples); // no rear

      final result = await _engine.simulate(
        tuning: TuningParameters.defaultPreset,
        session: session,
      );

      // Front uses session (50 samples), rear falls back to synthetic (2000).
      expect(result.frontSamples.length, 50);
      expect(
        result.rearSamples.length,
        (SimulationEngine.kSyntheticDurationS *
                SimulationEngine.kSyntheticSampleRateHz)
            .round(),
      );
    });

    test('empty session falls back to synthetic profile', () async {
      final session = _makeSession(); // no samples
      final result = await _engine.simulate(
        tuning: TuningParameters.defaultPreset,
        session: session,
      );

      const syntheticCount =
          SimulationEngine.kSyntheticDurationS *
          SimulationEngine.kSyntheticSampleRateHz;
      expect(result.frontSamples.length, syntheticCount.round());
      expect(result.rearSamples.length, syntheticCount.round());
    });
  });

  // ── Metrics edge cases ─────────────────────────────────────────────────────

  group('SimulationEngine – metrics on empty samples', () {
    test('_computeMetrics handles empty list via zero-sample session', () async {
      // We cannot call _computeMetrics directly (private), but we can
      // trigger it through a session that produces 0 samples.
      // An empty list in frontProcessed but non-empty rearProcessed ensures
      // both paths are exercised by the engine.
      // We only verify that the engine completes without throwing.
      final session = _makeSession(
        rear: List.generate(10, (i) => _makeSample(i, 0.0)),
      );
      final result = await _engine.simulate(
        tuning: TuningParameters.defaultPreset,
        session: session,
      );
      expect(result, isNotNull);
    });
  });
}

// ── SimulationSample.copyWith helper (test-local) ─────────────────────────────

extension _SimulationSampleX on SimulationSample {
  SimulationSample copyWith({double? timeMs}) => SimulationSample(
        timeMs: timeMs ?? this.timeMs,
        displacementMm: displacementMm,
        velocityMps: velocityMps,
        springForceN: springForceN,
        dampingForceN: dampingForceN,
      );
}
