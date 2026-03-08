// Unit tests for RecommendationEngine (FR-UI-007).
//
// Covers:
//  • Severity thresholds for the bottoming-too-much check
//  • Travel underutilisation detection and suggestion delta
//  • Harsh-ride and too-much-rebound flag-based checks
//  • Front/rear imbalance detection
//  • Prioritisation: output is sorted high → medium → low
//  • No recommendations when metrics are nominal
//  • Suggested parameters respect SuspensionParameters bounds

import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/models/analysis_metrics.dart';
import 'package:ride_metric_x/models/recommendation.dart';
import 'package:ride_metric_x/models/suspension_parameters.dart';
import 'package:ride_metric_x/services/recommendation_engine.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _engine = RecommendationEngine();

/// Nominal metrics – all values within the "good" range.
const _nominal = AnalysisMetrics(
  frontBottomingEvents: 0,
  rearBottomingEvents: 0,
  frontTravelUsagePercent: 80.0,
  rearTravelUsagePercent: 80.0,
  harshRideDetected: false,
  tooMuchReboundDetected: false,
);

const _current = TuningParameters.defaultPreset; // 10 comp / 10 rebound

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── No issues ───────────────────────────────────────────────────────────────
  group('No recommendations when metrics are nominal', () {
    test('returns empty list for nominal metrics', () {
      final recs = _engine.generate(_nominal, _current);
      expect(recs, isEmpty);
    });
  });

  // ── Bottoming ───────────────────────────────────────────────────────────────
  group('Bottoming too much', () {
    test('generates LOW severity for 1–4 events', () {
      const metrics = AnalysisMetrics(rearBottomingEvents: 3);
      final recs = _engine.generate(metrics, _current);
      final bottoming =
          recs.where((r) => r.type == RecommendationType.bottomingTooMuch);
      expect(bottoming, hasLength(1));
      expect(bottoming.first.severity, RecommendationSeverity.low);
    });

    test('generates MEDIUM severity for 5–10 events', () {
      const metrics = AnalysisMetrics(rearBottomingEvents: 7);
      final recs = _engine.generate(metrics, _current);
      final rec =
          recs.firstWhere((r) => r.type == RecommendationType.bottomingTooMuch);
      expect(rec.severity, RecommendationSeverity.medium);
    });

    test('generates HIGH severity for >10 events', () {
      const metrics = AnalysisMetrics(rearBottomingEvents: 12);
      final recs = _engine.generate(metrics, _current);
      final rec =
          recs.firstWhere((r) => r.type == RecommendationType.bottomingTooMuch);
      expect(rec.severity, RecommendationSeverity.high);
    });

    test('suggests increased compression on the end that bottomed more (rear)',
        () {
      const metrics = AnalysisMetrics(
        frontBottomingEvents: 2,
        rearBottomingEvents: 8,
      );
      final recs = _engine.generate(metrics, _current);
      final rec =
          recs.firstWhere((r) => r.type == RecommendationType.bottomingTooMuch);

      // Rear bottomed more → rear compression should increase.
      expect(
        rec.suggestedParameters!.rear.compression,
        greaterThan(_current.rear.compression),
      );
      // Front compression unchanged.
      expect(
        rec.suggestedParameters!.front.compression,
        _current.front.compression,
      );
    });

    test('suggests increased compression on front when it bottomed more', () {
      const metrics = AnalysisMetrics(
        frontBottomingEvents: 9,
        rearBottomingEvents: 1,
      );
      final recs = _engine.generate(metrics, _current);
      final rec =
          recs.firstWhere((r) => r.type == RecommendationType.bottomingTooMuch);

      expect(
        rec.suggestedParameters!.front.compression,
        greaterThan(_current.front.compression),
      );
      expect(
        rec.suggestedParameters!.rear.compression,
        _current.rear.compression,
      );
    });

    test('no bottoming recommendation when events == 0', () {
      final recs = _engine.generate(_nominal, _current);
      expect(
        recs.any((r) => r.type == RecommendationType.bottomingTooMuch),
        isFalse,
      );
    });
  });

  // ── Travel underutilisation ─────────────────────────────────────────────────
  group('Travel underutilisation', () {
    test('triggers when travel < 70%', () {
      const metrics = AnalysisMetrics(
        frontTravelUsagePercent: 60.0,
        rearTravelUsagePercent: 65.0,
      );
      final recs = _engine.generate(metrics, _current);
      expect(
        recs.any((r) => r.type == RecommendationType.notUsingFullTravel),
        isTrue,
      );
    });

    test('does not trigger when both ends use ≥ 70% travel', () {
      const metrics = AnalysisMetrics(
        frontTravelUsagePercent: 75.0,
        rearTravelUsagePercent: 70.0,
      );
      final recs = _engine.generate(metrics, _current);
      expect(
        recs.any((r) => r.type == RecommendationType.notUsingFullTravel),
        isFalse,
      );
    });

    test('suggests reduced compression on both ends', () {
      const metrics = AnalysisMetrics(
        frontTravelUsagePercent: 55.0,
        rearTravelUsagePercent: 60.0,
      );
      final recs = _engine.generate(metrics, _current);
      final rec = recs
          .firstWhere((r) => r.type == RecommendationType.notUsingFullTravel);

      expect(
        rec.suggestedParameters!.front.compression,
        lessThan(_current.front.compression),
      );
      expect(
        rec.suggestedParameters!.rear.compression,
        lessThan(_current.rear.compression),
      );
    });

    test('severity is MEDIUM', () {
      const metrics = AnalysisMetrics(frontTravelUsagePercent: 50.0);
      final recs = _engine.generate(metrics, _current);
      final rec = recs
          .firstWhere((r) => r.type == RecommendationType.notUsingFullTravel);
      expect(rec.severity, RecommendationSeverity.medium);
    });
  });

  // ── Harsh ride ──────────────────────────────────────────────────────────────
  group('Harsh ride', () {
    test('triggers when harshRideDetected is true', () {
      const metrics = AnalysisMetrics(harshRideDetected: true);
      final recs = _engine.generate(metrics, _current);
      expect(recs.any((r) => r.type == RecommendationType.harshRide), isTrue);
    });

    test('does not trigger when harshRideDetected is false', () {
      final recs = _engine.generate(_nominal, _current);
      expect(recs.any((r) => r.type == RecommendationType.harshRide), isFalse);
    });

    test('suggests reduced compression on both ends', () {
      const metrics = AnalysisMetrics(harshRideDetected: true);
      final recs = _engine.generate(metrics, _current);
      final rec =
          recs.firstWhere((r) => r.type == RecommendationType.harshRide);
      expect(
        rec.suggestedParameters!.front.compression,
        lessThan(_current.front.compression),
      );
      expect(
        rec.suggestedParameters!.rear.compression,
        lessThan(_current.rear.compression),
      );
    });
  });

  // ── Too much rebound ─────────────────────────────────────────────────────────
  group('Too much rebound', () {
    test('triggers when tooMuchReboundDetected is true', () {
      const metrics = AnalysisMetrics(tooMuchReboundDetected: true);
      final recs = _engine.generate(metrics, _current);
      expect(
        recs.any((r) => r.type == RecommendationType.tooMuchRebound),
        isTrue,
      );
    });

    test('does not trigger when tooMuchReboundDetected is false', () {
      final recs = _engine.generate(_nominal, _current);
      expect(
        recs.any((r) => r.type == RecommendationType.tooMuchRebound),
        isFalse,
      );
    });

    test('suggests increased rebound clicks on both ends', () {
      const metrics = AnalysisMetrics(tooMuchReboundDetected: true);
      final recs = _engine.generate(metrics, _current);
      final rec =
          recs.firstWhere((r) => r.type == RecommendationType.tooMuchRebound);
      expect(
        rec.suggestedParameters!.front.rebound,
        greaterThan(_current.front.rebound),
      );
      expect(
        rec.suggestedParameters!.rear.rebound,
        greaterThan(_current.rear.rebound),
      );
    });
  });

  // ── Front/rear imbalance ─────────────────────────────────────────────────────
  group('Front/rear imbalance', () {
    test('triggers when difference is ≥ 20%', () {
      const metrics = AnalysisMetrics(
        frontTravelUsagePercent: 90.0,
        rearTravelUsagePercent: 60.0,
      );
      final recs = _engine.generate(metrics, _current);
      expect(
        recs.any((r) => r.type == RecommendationType.imbalancedFrontRear),
        isTrue,
      );
    });

    test('does not trigger when difference is < 20%', () {
      const metrics = AnalysisMetrics(
        frontTravelUsagePercent: 80.0,
        rearTravelUsagePercent: 65.0,
      );
      final recs = _engine.generate(metrics, _current);
      expect(
        recs.any((r) => r.type == RecommendationType.imbalancedFrontRear),
        isFalse,
      );
    });

    test('reduces compression on the lighter end (rear) when front is heavier',
        () {
      const metrics = AnalysisMetrics(
        frontTravelUsagePercent: 90.0,
        rearTravelUsagePercent: 60.0,
      );
      final recs = _engine.generate(metrics, _current);
      final rec = recs.firstWhere(
        (r) => r.type == RecommendationType.imbalancedFrontRear,
      );

      // Rear is lighter → rear compression should decrease.
      expect(
        rec.suggestedParameters!.rear.compression,
        lessThan(_current.rear.compression),
      );
      // Front compression unchanged.
      expect(
        rec.suggestedParameters!.front.compression,
        _current.front.compression,
      );
    });

    test('reduces front compression when rear is heavier', () {
      const metrics = AnalysisMetrics(
        frontTravelUsagePercent: 60.0,
        rearTravelUsagePercent: 90.0,
      );
      final recs = _engine.generate(metrics, _current);
      final rec = recs.firstWhere(
        (r) => r.type == RecommendationType.imbalancedFrontRear,
      );

      expect(
        rec.suggestedParameters!.front.compression,
        lessThan(_current.front.compression),
      );
      expect(
        rec.suggestedParameters!.rear.compression,
        _current.rear.compression,
      );
    });
  });

  // ── Prioritisation ───────────────────────────────────────────────────────────
  group('Severity prioritisation', () {
    test('output is sorted high → medium → low', () {
      // Bottoming >10 = HIGH; travel underuse = MEDIUM; harsh ride = MEDIUM
      const metrics = AnalysisMetrics(
        rearBottomingEvents: 12, // HIGH
        frontTravelUsagePercent: 50.0, // MEDIUM
        harshRideDetected: true, // MEDIUM
      );
      final recs = _engine.generate(metrics, _current);

      // First item must be HIGH.
      expect(recs.first.severity, RecommendationSeverity.high);

      // Remaining items must be non-increasing in severity.
      for (int i = 1; i < recs.length; i++) {
        expect(
          recs[i].severity.priorityScore,
          lessThanOrEqualTo(recs[i - 1].severity.priorityScore),
        );
      }
    });

    test('priorityScore: high=2, medium=1, low=0', () {
      expect(RecommendationSeverity.high.priorityScore, 2);
      expect(RecommendationSeverity.medium.priorityScore, 1);
      expect(RecommendationSeverity.low.priorityScore, 0);
    });
  });

  // ── Bounds clamping ──────────────────────────────────────────────────────────
  group('Suggested parameters respect SuspensionParameters bounds', () {
    test('compression clicks do not exceed kMaxClicks when already near max',
        () {
      // Start at 18 clicks, suggest +4 → would be 22 but clamped to 20.
      const nearMax = TuningParameters(
        front: SuspensionParameters(
          springRate: 25.0,
          compression: 18.0,
          rebound: 10.0,
          preload: 5.0,
        ),
        rear: SuspensionParameters(
          springRate: 30.0,
          compression: 18.0,
          rebound: 10.0,
          preload: 5.0,
        ),
      );
      const metrics = AnalysisMetrics(rearBottomingEvents: 5);
      final recs = _engine.generate(metrics, nearMax);
      final rec =
          recs.firstWhere((r) => r.type == RecommendationType.bottomingTooMuch);

      expect(
        rec.suggestedParameters!.rear.compression,
        lessThanOrEqualTo(SuspensionParameters.kMaxClicks),
      );
    });

    test('compression clicks do not go below kMinClicks when already near min',
        () {
      // Start at 1 click, suggest -2 → would be -1 but clamped to 0.
      const nearMin = TuningParameters(
        front: SuspensionParameters(
          springRate: 25.0,
          compression: 1.0,
          rebound: 10.0,
          preload: 5.0,
        ),
        rear: SuspensionParameters(
          springRate: 30.0,
          compression: 1.0,
          rebound: 10.0,
          preload: 5.0,
        ),
      );
      const metrics = AnalysisMetrics(harshRideDetected: true);
      final recs = _engine.generate(metrics, nearMin);
      final rec =
          recs.firstWhere((r) => r.type == RecommendationType.harshRide);

      expect(
        rec.suggestedParameters!.front.compression,
        greaterThanOrEqualTo(SuspensionParameters.kMinClicks),
      );
      expect(
        rec.suggestedParameters!.rear.compression,
        greaterThanOrEqualTo(SuspensionParameters.kMinClicks),
      );
    });
  });

  // ── AnalysisMetrics ──────────────────────────────────────────────────────────
  group('AnalysisMetrics', () {
    test('totalBottomingEvents sums front and rear', () {
      const m = AnalysisMetrics(
        frontBottomingEvents: 3,
        rearBottomingEvents: 7,
      );
      expect(m.totalBottomingEvents, 10);
    });

    test('default values produce no recommendations', () {
      const m = AnalysisMetrics();
      expect(_engine.generate(m, _current), isEmpty);
    });

    test('equality holds for identical values', () {
      const a = AnalysisMetrics(frontBottomingEvents: 5, harshRideDetected: true);
      const b = AnalysisMetrics(frontBottomingEvents: 5, harshRideDetected: true);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
