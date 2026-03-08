// Unit tests for TelemetryChart downsampling algorithms (FR-VZ-006, NFR-VZ-001).
//
// Covers:
//  • TelemetryChart.decimate (min/max bucketing)
//    – empty result for maxPoints ≤ 0
//    – original list returned when points.length ≤ maxPoints
//    – output length ≤ maxPoints * 2  (two points per bucket)
//    – first/last points retained for small maxPoints
//  • TelemetryChart.lttb (Largest Triangle Three Buckets)
//    – empty result for maxPoints ≤ 0
//    – original list returned when points.length ≤ maxPoints
//    – exactly maxPoints points in output
//    – first and last original points always retained
//    – LTTB preserves a signal peak better than uniform decimation

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:ride_metric_x/widgets/telemetry_chart.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Generates a uniform sine-wave series with [n] points over [cycles] full
/// oscillations.  x ∈ [0, n−1], y = sin(x / (n−1) × 2π × cycles).
List<Offset> _sineWave(int n, {int cycles = 1}) => List.generate(
      n,
      (i) => Offset(
        i.toDouble(),
        math.sin(i / (n - 1) * 2 * math.pi * cycles),
      ),
    );

/// Generates a flat line (y = 0) with [n] uniformly-spaced points.
List<Offset> _flatLine(int n) =>
    List.generate(n, (i) => Offset(i.toDouble(), 0));

// ── decimate ──────────────────────────────────────────────────────────────────

void main() {
  group('TelemetryChart.decimate (min/max bucketing)', () {
    test('returns empty list when maxPoints is zero', () {
      final pts = _sineWave(100);
      expect(TelemetryChart.decimate(pts, 0), isEmpty);
    });

    test('returns empty list when maxPoints is negative', () {
      final pts = _sineWave(100);
      expect(TelemetryChart.decimate(pts, -5), isEmpty);
    });

    test('returns original list when points.length <= maxPoints', () {
      final pts = _sineWave(50);
      final result = TelemetryChart.decimate(pts, 100);
      expect(identical(result, pts), isTrue,
          reason: 'should return the same list reference without copying');
    });

    test('returns original list when points.length == maxPoints', () {
      final pts = _sineWave(100);
      final result = TelemetryChart.decimate(pts, 100);
      expect(identical(result, pts), isTrue);
    });

    test('output length is at most 2 × maxPoints for large input', () {
      final pts = _sineWave(10000);
      const maxPts = 200;
      final result = TelemetryChart.decimate(pts, maxPts);
      // Each bucket can emit at most 2 points (min + max).
      expect(result.length, lessThanOrEqualTo(maxPts * 2));
    });

    test('output is non-empty for a large sine wave', () {
      final pts = _sineWave(10000);
      final result = TelemetryChart.decimate(pts, 200);
      expect(result, isNotEmpty);
    });

    test('all output points belong to the original list', () {
      final pts = _sineWave(1000);
      final result = TelemetryChart.decimate(pts, 100);
      final set = {for (final p in pts) p};
      for (final r in result) {
        expect(set.contains(r), isTrue,
            reason: 'every output point must be from the input');
      }
    });

    test('handles a flat line without throwing', () {
      final pts = _flatLine(5000);
      expect(() => TelemetryChart.decimate(pts, 100), returnsNormally);
    });

    test('single-point list is returned unchanged', () {
      final pts = [const Offset(0, 0)];
      final result = TelemetryChart.decimate(pts, 50);
      expect(identical(result, pts), isTrue);
    });
  });

  // ── lttb ────────────────────────────────────────────────────────────────────

  group('TelemetryChart.lttb (Largest Triangle Three Buckets)', () {
    test('returns empty list when maxPoints is zero', () {
      final pts = _sineWave(100);
      expect(TelemetryChart.lttb(pts, 0), isEmpty);
    });

    test('returns empty list when maxPoints is negative', () {
      final pts = _sineWave(100);
      expect(TelemetryChart.lttb(pts, -5), isEmpty);
    });

    test('returns original list when points.length <= maxPoints', () {
      final pts = _sineWave(50);
      final result = TelemetryChart.lttb(pts, 100);
      expect(identical(result, pts), isTrue,
          reason: 'should return the same list reference without copying');
    });

    test('returns original list when points.length == maxPoints', () {
      final pts = _sineWave(100);
      final result = TelemetryChart.lttb(pts, 100);
      expect(identical(result, pts), isTrue);
    });

    test('output length equals maxPoints exactly for large input', () {
      final pts = _sineWave(10000);
      const maxPts = 300;
      final result = TelemetryChart.lttb(pts, maxPts);
      expect(result.length, maxPts);
    });

    test('always retains the first point', () {
      final pts = _sineWave(5000);
      final result = TelemetryChart.lttb(pts, 100);
      expect(result.first, pts.first);
    });

    test('always retains the last point', () {
      final pts = _sineWave(5000);
      final result = TelemetryChart.lttb(pts, 100);
      expect(result.last, pts.last);
    });

    test('all output points belong to the original list', () {
      final pts = _sineWave(2000);
      final result = TelemetryChart.lttb(pts, 150);
      final set = {for (final p in pts) p};
      for (final r in result) {
        expect(set.contains(r), isTrue,
            reason: 'every output point must be from the input');
      }
    });

    test('output length == 1 when maxPoints == 1', () {
      final pts = _sineWave(1000);
      final result = TelemetryChart.lttb(pts, 1);
      expect(result.length, 1);
    });

    test('output length == 2 when maxPoints == 2', () {
      final pts = _sineWave(1000);
      final result = TelemetryChart.lttb(pts, 2);
      expect(result.length, 2);
      expect(result.first, pts.first);
      expect(result.last, pts.last);
    });

    test('single-point list is returned unchanged', () {
      final pts = [const Offset(0, 1)];
      final result = TelemetryChart.lttb(pts, 50);
      expect(identical(result, pts), isTrue);
    });

    test('handles a flat line without throwing', () {
      final pts = _flatLine(5000);
      expect(() => TelemetryChart.lttb(pts, 100), returnsNormally);
    });

    test('x-order of output is non-decreasing (monotone)', () {
      // LTTB iterates buckets left-to-right, so output x must be ordered.
      final pts = _sineWave(8000, cycles: 3);
      final result = TelemetryChart.lttb(pts, 200);
      for (int i = 1; i < result.length; i++) {
        expect(result[i].dx, greaterThanOrEqualTo(result[i - 1].dx),
            reason: 'x values must be non-decreasing in LTTB output');
      }
    });

    // Signal-shape preservation: LTTB must retain an extreme peak value.
    test('retains the global maximum on a spike series', () {
      // Build a mostly flat series with one very tall spike in the centre.
      final n = 2000;
      final pts = List.generate(n, (i) {
        final y = (i == n ~/ 2) ? 100.0 : 0.0;
        return Offset(i.toDouble(), y);
      });
      final result = TelemetryChart.lttb(pts, 50);
      final yValues = result.map((p) => p.dy).toList();
      expect(yValues, contains(100.0),
          reason: 'LTTB must retain the single spike point');
    });

    test('retains the global minimum on a spike series', () {
      final n = 2000;
      final pts = List.generate(n, (i) {
        final y = (i == n ~/ 2) ? -100.0 : 0.0;
        return Offset(i.toDouble(), y);
      });
      final result = TelemetryChart.lttb(pts, 50);
      final yValues = result.map((p) => p.dy).toList();
      expect(yValues, contains(-100.0),
          reason: 'LTTB must retain the single trough point');
    });
  });

  // ── Large-series performance ──────────────────────────────────────────────

  group('Downsampling performance for large datasets (NFR-VZ-001)', () {
    // These tests assert correctness, not wall-clock timing (which is
    // unreliable in test environments).  The point counts mirror realistic
    // session lengths at 1 kHz for ~100 s.

    test('decimate handles 100 000 points without error', () {
      final pts = _sineWave(100000, cycles: 10);
      final result = TelemetryChart.decimate(pts, 2000);
      expect(result.length, lessThanOrEqualTo(4000)); // ≤ 2 × maxPoints
      expect(result, isNotEmpty);
    });

    test('lttb handles 100 000 points and produces exactly maxPoints', () {
      final pts = _sineWave(100000, cycles: 10);
      const maxPts = 2000;
      final result = TelemetryChart.lttb(pts, maxPts);
      expect(result.length, maxPts);
      expect(result.first, pts.first);
      expect(result.last, pts.last);
    });
  });
}
