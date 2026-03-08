// Unit tests for SuspensionState (FR-VZ-002, FR-VZ-004).
//
// Covers:
//  • Default construction
//  • Compression ratio clamping
//  • State-to-geometry mapping: ratio reflects travel vs max travel
//  • copyWith preserves unchanged fields
//  • Equality and hashCode

import 'package:flutter_test/flutter_test.dart';
import 'package:ride_metric_x/models/suspension_state.dart';

void main() {
  // ── Default construction ───────────────────────────────────────────────────
  group('SuspensionState default construction', () {
    test('all fields are zero / defaults', () {
      const state = SuspensionState();
      expect(state.frontTravelMm, 0.0);
      expect(state.rearTravelMm, 0.0);
      expect(state.wheelRotationRad, 0.0);
      expect(state.frontMaxTravelMm, 300.0);
      expect(state.rearMaxTravelMm, 200.0);
    });

    test('compression ratios are 0 at rest', () {
      const state = SuspensionState();
      expect(state.frontCompressionRatio, 0.0);
      expect(state.rearCompressionRatio, 0.0);
    });
  });

  // ── Compression ratio – state-to-geometry mapping ──────────────────────────
  group('SuspensionState compression ratio (state → geometry mapping)', () {
    test('front ratio is 0.5 at half travel', () {
      const state = SuspensionState(
        frontTravelMm: 150.0,
        frontMaxTravelMm: 300.0,
      );
      expect(state.frontCompressionRatio, closeTo(0.5, 1e-9));
    });

    test('rear ratio is 0.5 at half travel', () {
      const state = SuspensionState(
        rearTravelMm: 100.0,
        rearMaxTravelMm: 200.0,
      );
      expect(state.rearCompressionRatio, closeTo(0.5, 1e-9));
    });

    test('front ratio is 1.0 at full travel', () {
      const state = SuspensionState(
        frontTravelMm: 300.0,
        frontMaxTravelMm: 300.0,
      );
      expect(state.frontCompressionRatio, 1.0);
    });

    test('rear ratio is 1.0 at full travel', () {
      const state = SuspensionState(
        rearTravelMm: 200.0,
        rearMaxTravelMm: 200.0,
      );
      expect(state.rearCompressionRatio, 1.0);
    });

    test('compression ratio clamps below 0', () {
      const state = SuspensionState(frontTravelMm: -50.0);
      expect(state.frontCompressionRatio, 0.0);
    });

    test('compression ratio clamps above 1', () {
      const state = SuspensionState(
        frontTravelMm: 400.0,
        frontMaxTravelMm: 300.0,
      );
      expect(state.frontCompressionRatio, 1.0);
    });
  });

  // ── copyWith ──────────────────────────────────────────────────────────────
  group('SuspensionState copyWith', () {
    const base = SuspensionState(
      frontTravelMm: 100.0,
      rearTravelMm: 50.0,
      wheelRotationRad: 1.5,
    );

    test('overrides only frontTravelMm', () {
      final s = base.copyWith(frontTravelMm: 200.0);
      expect(s.frontTravelMm, 200.0);
      expect(s.rearTravelMm, 50.0);
      expect(s.wheelRotationRad, 1.5);
    });

    test('overrides only rearTravelMm', () {
      final s = base.copyWith(rearTravelMm: 80.0);
      expect(s.rearTravelMm, 80.0);
      expect(s.frontTravelMm, 100.0);
    });

    test('overrides only wheelRotationRad', () {
      final s = base.copyWith(wheelRotationRad: 3.14);
      expect(s.wheelRotationRad, 3.14);
      expect(s.frontTravelMm, 100.0);
    });

    test('returns equal state when no field overridden', () {
      expect(base.copyWith(), equals(base));
    });
  });

  // ── Equality and hashCode ─────────────────────────────────────────────────
  group('SuspensionState equality', () {
    test('identical instances are equal', () {
      const a = SuspensionState(frontTravelMm: 50.0);
      const b = SuspensionState(frontTravelMm: 50.0);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different frontTravelMm are not equal', () {
      const a = SuspensionState(frontTravelMm: 50.0);
      const b = SuspensionState(frontTravelMm: 51.0);
      expect(a, isNot(equals(b)));
    });

    test('different rearTravelMm are not equal', () {
      const a = SuspensionState(rearTravelMm: 20.0);
      const b = SuspensionState(rearTravelMm: 21.0);
      expect(a, isNot(equals(b)));
    });

    test('toString contains front/rear/wheel info', () {
      const state = SuspensionState(
        frontTravelMm: 123.0,
        rearTravelMm: 45.6,
        wheelRotationRad: 1.23,
      );
      expect(state.toString(), contains('123.0 mm'));
      expect(state.toString(), contains('45.6 mm'));
      expect(state.toString(), contains('1.230 rad'));
    });
  });
}
