// Unit tests for CameraState and CameraController (FR-VZ-005).
//
// Covers:
//  • CameraState defaults and copyWith field replacement
//  • Azimuth wrap-around into [0, 2π)
//  • Elevation clamping to [minElevationRad, maxElevationRad]
//  • Distance clamping to [minDistance, maxDistance]
//  • Equality and toString
//  • CameraController.rotate (arcball/orbit vs fixed no-op)
//  • CameraController.pan
//  • CameraController.zoom (positive scale / non-positive guard)
//  • CameraController.reset
//  • CameraController.setMode (incl. same-mode no-op)
//  • ChangeNotifier: listener notifications on every state mutation

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/rendering/camera_state.dart';
import 'package:ride_metric_x/rendering/camera_controller.dart';

void main() {
  // ── CameraState ─────────────────────────────────────────────────────────────
  group('CameraState defaults', () {
    test('mode is orbit', () {
      expect(CameraState.defaults.mode, CameraMode.orbit);
    });

    test('azimuthRad is 0', () {
      expect(CameraState.defaults.azimuthRad, 0.0);
    });

    test('elevationRad is π/6 (30°)', () {
      expect(CameraState.defaults.elevationRad, closeTo(math.pi / 6, 1e-10));
    });

    test('distance is 5.0', () {
      expect(CameraState.defaults.distance, 5.0);
    });

    test('panOffset is Offset.zero', () {
      expect(CameraState.defaults.panOffset, Offset.zero);
    });

    test('minDistance is 0.5', () {
      expect(CameraState.defaults.minDistance, 0.5);
    });

    test('maxDistance is 50.0', () {
      expect(CameraState.defaults.maxDistance, 50.0);
    });
  });

  // ── CameraState.copyWith ────────────────────────────────────────────────────
  group('CameraState.copyWith', () {
    test('replaces mode', () {
      final s = CameraState.defaults.copyWith(mode: CameraMode.arcball);
      expect(s.mode, CameraMode.arcball);
    });

    test('replaces panOffset', () {
      const offset = Offset(10, -5);
      final s = CameraState.defaults.copyWith(panOffset: offset);
      expect(s.panOffset, offset);
    });

    test('preserves unchanged fields', () {
      final s = CameraState.defaults.copyWith(distance: 3.0);
      expect(s.mode, CameraState.defaults.mode);
      expect(s.azimuthRad, CameraState.defaults.azimuthRad);
      expect(s.elevationRad, CameraState.defaults.elevationRad);
      expect(s.panOffset, CameraState.defaults.panOffset);
    });
  });

  // ── Azimuth wrap ────────────────────────────────────────────────────────────
  group('CameraState azimuth wrap-around', () {
    test('wraps negative azimuth into [0, 2π)', () {
      final s = CameraState.defaults.copyWith(azimuthRad: -0.5);
      expect(s.azimuthRad, closeTo(2 * math.pi - 0.5, 1e-10));
    });

    test('wraps azimuth > 2π back into [0, 2π)', () {
      final s = CameraState.defaults.copyWith(azimuthRad: 3 * math.pi);
      expect(s.azimuthRad, closeTo(math.pi, 1e-10));
    });

    test('keeps azimuth 0 unchanged', () {
      final s = CameraState.defaults.copyWith(azimuthRad: 0.0);
      expect(s.azimuthRad, 0.0);
    });

    test('keeps azimuth inside [0, 2π) unchanged', () {
      final s = CameraState.defaults.copyWith(azimuthRad: math.pi);
      expect(s.azimuthRad, closeTo(math.pi, 1e-10));
    });
  });

  // ── Elevation clamp ─────────────────────────────────────────────────────────
  group('CameraState elevation clamping', () {
    test('clamps elevation above maxElevationRad', () {
      final s = CameraState.defaults.copyWith(
        elevationRad: math.pi, // way above limit
      );
      expect(s.elevationRad, closeTo(s.maxElevationRad, 1e-10));
    });

    test('clamps elevation below minElevationRad', () {
      final s = CameraState.defaults.copyWith(
        elevationRad: -math.pi, // way below limit
      );
      expect(s.elevationRad, closeTo(s.minElevationRad, 1e-10));
    });

    test('preserves elevation within bounds', () {
      const angle = 0.3;
      final s = CameraState.defaults.copyWith(elevationRad: angle);
      expect(s.elevationRad, closeTo(angle, 1e-10));
    });
  });

  // ── Distance clamp ──────────────────────────────────────────────────────────
  group('CameraState distance clamping', () {
    test('clamps distance below minDistance', () {
      final s = CameraState.defaults.copyWith(distance: 0.0);
      expect(s.distance, CameraState.defaults.minDistance);
    });

    test('clamps distance above maxDistance', () {
      final s = CameraState.defaults.copyWith(distance: 1000.0);
      expect(s.distance, CameraState.defaults.maxDistance);
    });

    test('preserves distance within bounds', () {
      final s = CameraState.defaults.copyWith(distance: 10.0);
      expect(s.distance, 10.0);
    });
  });

  // ── Equality ────────────────────────────────────────────────────────────────
  group('CameraState equality', () {
    test('identical instances are equal', () {
      expect(CameraState.defaults, equals(CameraState.defaults));
    });

    test('equal by value', () {
      const a = CameraState();
      const b = CameraState();
      expect(a, equals(b));
    });

    test('differs when mode differs', () {
      const a = CameraState();
      final b = a.copyWith(mode: CameraMode.fixed);
      expect(a, isNot(equals(b)));
    });

    test('differs when azimuth differs', () {
      const a = CameraState();
      final b = a.copyWith(azimuthRad: 1.0);
      expect(a, isNot(equals(b)));
    });
  });

  // ── CameraController ────────────────────────────────────────────────────────
  group('CameraController initial state', () {
    test('defaults to CameraState.defaults when no initialState provided', () {
      final ctrl = CameraController();
      expect(ctrl.state, CameraState.defaults);
      ctrl.dispose();
    });

    test('uses supplied initialState', () {
      const initial = CameraState(distance: 10.0);
      final ctrl = CameraController(initialState: initial);
      expect(ctrl.state.distance, 10.0);
      ctrl.dispose();
    });
  });

  // ── rotate ──────────────────────────────────────────────────────────────────
  group('CameraController.rotate', () {
    test('updates azimuth in orbit mode', () {
      final ctrl = CameraController();
      final before = ctrl.state.azimuthRad;
      ctrl.rotate(0.5, 0.0);
      expect(ctrl.state.azimuthRad, closeTo(before + 0.5, 1e-10));
      ctrl.dispose();
    });

    test('updates elevation in arcball mode', () {
      final ctrl = CameraController(
        initialState: const CameraState(mode: CameraMode.arcball),
      );
      final before = ctrl.state.elevationRad;
      ctrl.rotate(0.0, 0.1);
      expect(ctrl.state.elevationRad, closeTo(before + 0.1, 1e-10));
      ctrl.dispose();
    });

    test('is a no-op in fixed mode (azimuth unchanged)', () {
      final ctrl = CameraController(
        initialState: const CameraState(mode: CameraMode.fixed),
      );
      final before = ctrl.state.azimuthRad;
      ctrl.rotate(1.0, 1.0);
      expect(ctrl.state.azimuthRad, before);
      ctrl.dispose();
    });

    test('is a no-op in fixed mode (elevation unchanged)', () {
      final ctrl = CameraController(
        initialState: const CameraState(mode: CameraMode.fixed),
      );
      final before = ctrl.state.elevationRad;
      ctrl.rotate(1.0, 1.0);
      expect(ctrl.state.elevationRad, before);
      ctrl.dispose();
    });

    test('notifies listeners', () {
      final ctrl = CameraController();
      var notified = false;
      ctrl.addListener(() => notified = true);
      ctrl.rotate(0.1, 0.0);
      expect(notified, isTrue);
      ctrl.dispose();
    });
  });

  // ── pan ─────────────────────────────────────────────────────────────────────
  group('CameraController.pan', () {
    test('updates panOffset', () {
      final ctrl = CameraController();
      ctrl.pan(10.0, -5.0);
      expect(ctrl.state.panOffset, const Offset(10.0, -5.0));
      ctrl.dispose();
    });

    test('accumulates pan offsets', () {
      final ctrl = CameraController();
      ctrl.pan(10.0, 0.0);
      ctrl.pan(0.0, -5.0);
      expect(ctrl.state.panOffset, const Offset(10.0, -5.0));
      ctrl.dispose();
    });

    test('notifies listeners', () {
      final ctrl = CameraController();
      var notified = false;
      ctrl.addListener(() => notified = true);
      ctrl.pan(1.0, 1.0);
      expect(notified, isTrue);
      ctrl.dispose();
    });
  });

  // ── zoom ────────────────────────────────────────────────────────────────────
  group('CameraController.zoom', () {
    test('scaleFactor > 1 decreases distance (zoom in)', () {
      final ctrl = CameraController();
      final before = ctrl.state.distance;
      ctrl.zoom(2.0);
      expect(ctrl.state.distance, closeTo(before / 2.0, 1e-10));
      ctrl.dispose();
    });

    test('scaleFactor < 1 increases distance (zoom out)', () {
      final ctrl = CameraController();
      final before = ctrl.state.distance;
      ctrl.zoom(0.5);
      expect(ctrl.state.distance, closeTo(before / 0.5, 1e-10));
      ctrl.dispose();
    });

    test('ignores zero scaleFactor', () {
      final ctrl = CameraController();
      final before = ctrl.state.distance;
      ctrl.zoom(0.0);
      expect(ctrl.state.distance, before);
      ctrl.dispose();
    });

    test('ignores negative scaleFactor', () {
      final ctrl = CameraController();
      final before = ctrl.state.distance;
      ctrl.zoom(-1.0);
      expect(ctrl.state.distance, before);
      ctrl.dispose();
    });

    test('clamps distance to minDistance', () {
      final ctrl = CameraController();
      ctrl.zoom(1000.0); // extreme zoom-in
      expect(ctrl.state.distance, CameraState.defaults.minDistance);
      ctrl.dispose();
    });

    test('clamps distance to maxDistance', () {
      final ctrl = CameraController();
      ctrl.zoom(0.0001); // extreme zoom-out
      expect(ctrl.state.distance, CameraState.defaults.maxDistance);
      ctrl.dispose();
    });

    test('notifies listeners on valid scaleFactor', () {
      final ctrl = CameraController();
      var notified = false;
      ctrl.addListener(() => notified = true);
      ctrl.zoom(2.0);
      expect(notified, isTrue);
      ctrl.dispose();
    });
  });

  // ── reset ───────────────────────────────────────────────────────────────────
  group('CameraController.reset', () {
    test('restores state to the initial state', () {
      const initial = CameraState(distance: 8.0);
      final ctrl = CameraController(initialState: initial);
      ctrl.rotate(1.0, 0.5);
      ctrl.pan(20.0, 10.0);
      ctrl.zoom(3.0);
      ctrl.reset();
      expect(ctrl.state, initial);
      ctrl.dispose();
    });

    test('notifies listeners', () {
      final ctrl = CameraController();
      var notified = false;
      ctrl.addListener(() => notified = true);
      ctrl.reset();
      expect(notified, isTrue);
      ctrl.dispose();
    });
  });

  // ── setMode ─────────────────────────────────────────────────────────────────
  group('CameraController.setMode', () {
    test('changes mode', () {
      final ctrl = CameraController();
      ctrl.setMode(CameraMode.arcball);
      expect(ctrl.mode, CameraMode.arcball);
      ctrl.dispose();
    });

    test('preserves other state when mode changes', () {
      final ctrl = CameraController();
      ctrl.pan(5.0, 3.0);
      final panBefore = ctrl.state.panOffset;
      ctrl.setMode(CameraMode.fixed);
      expect(ctrl.state.panOffset, panBefore);
      ctrl.dispose();
    });

    test('is a no-op when mode is already the same', () {
      final ctrl = CameraController();
      var notifyCount = 0;
      ctrl.addListener(() => notifyCount++);
      ctrl.setMode(ctrl.mode); // same mode
      expect(notifyCount, 0);
      ctrl.dispose();
    });

    test('notifies listeners when mode changes', () {
      final ctrl = CameraController();
      var notified = false;
      ctrl.addListener(() => notified = true);
      ctrl.setMode(CameraMode.fixed);
      expect(notified, isTrue);
      ctrl.dispose();
    });
  });
}
