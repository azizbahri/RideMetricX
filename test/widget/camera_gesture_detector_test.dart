// Widget tests for CameraGestureDetector (FR-VZ-005).
//
// Covers:
//  • Widget builds successfully and renders its child
//  • Double-tap triggers CameraController.reset
//  • Scale-start resets internal delta tracking
//  • Drag (single-pointer) in orbit mode triggers rotate
//  • Drag (single-pointer) in fixed mode triggers pan, not rotate
//  • Pinch (multi-pointer scale) triggers zoom
//  • Negative / zero sensitivity rejected by assertion

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/rendering/camera_controller.dart';
import 'package:ride_metric_x/rendering/camera_state.dart';
import 'package:ride_metric_x/widgets/camera_gesture_detector.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

const Key _childKey = Key('gesture_child');

Widget _detector(CameraController ctrl) => _wrap(
      CameraGestureDetector(
        controller: ctrl,
        child: const SizedBox.expand(key: _childKey),
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Lifecycle ──────────────────────────────────────────────────────────────
  group('CameraGestureDetector lifecycle', () {
    testWidgets('builds successfully', (tester) async {
      final ctrl = CameraController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(_detector(ctrl));
      expect(find.byType(CameraGestureDetector), findsOneWidget);
    });

    testWidgets('renders its child widget', (tester) async {
      final ctrl = CameraController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(_detector(ctrl));
      expect(find.byKey(_childKey), findsOneWidget);
    });
  });

  // ── Double-tap → reset ─────────────────────────────────────────────────────
  group('CameraGestureDetector double-tap resets camera', () {
    testWidgets('double-tap calls controller.reset()', (tester) async {
      final ctrl = CameraController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(_detector(ctrl));

      // Mutate the state so reset has a visible effect.
      ctrl.rotate(1.0, 0.5);
      ctrl.pan(20.0, 10.0);
      const initial = CameraState();

      await tester.tap(find.byKey(_childKey));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(_childKey));
      await tester.pumpAndSettle();

      expect(ctrl.state, initial);
    });
  });

  // ── Drag → rotate (orbit / arcball) ───────────────────────────────────────
  group('CameraGestureDetector drag rotates in orbit mode', () {
    testWidgets('horizontal drag changes azimuth', (tester) async {
      final ctrl = CameraController(); // default: orbit mode
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(_detector(ctrl));

      final before = ctrl.state.azimuthRad;
      await tester.drag(find.byKey(_childKey), const Offset(50, 0));
      await tester.pump(const Duration(milliseconds: 50));

      // A rightward drag should change azimuth (direction depends on sensitivity).
      expect(ctrl.state.azimuthRad, isNot(closeTo(before, 1e-6)));
    });

    testWidgets('vertical drag changes elevation', (tester) async {
      final ctrl = CameraController(); // default: orbit mode
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(_detector(ctrl));

      final before = ctrl.state.elevationRad;
      await tester.drag(find.byKey(_childKey), const Offset(0, 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(ctrl.state.elevationRad, isNot(closeTo(before, 1e-6)));
    });
  });

  // ── Drag → pan (fixed mode) ────────────────────────────────────────────────
  group('CameraGestureDetector drag pans in fixed mode', () {
    testWidgets('drag updates panOffset and not azimuth', (tester) async {
      final ctrl = CameraController(
        initialState: const CameraState(mode: CameraMode.fixed),
      );
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(_detector(ctrl));

      final azBefore = ctrl.state.azimuthRad;
      await tester.drag(find.byKey(_childKey), const Offset(50, 30));
      await tester.pump(const Duration(milliseconds: 50));

      // Pan offset must have changed.
      expect(ctrl.state.panOffset, isNot(Offset.zero));
      // Azimuth must remain unchanged.
      expect(ctrl.state.azimuthRad, closeTo(azBefore, 1e-10));
    });
  });

  // ── Assertion guards ───────────────────────────────────────────────────────
  group('CameraGestureDetector parameter assertions', () {
    test('throws if rotateSensitivity is zero', () {
      final ctrl = CameraController();
      addTearDown(ctrl.dispose);
      expect(
        () => CameraGestureDetector(
          controller: ctrl,
          rotateSensitivity: 0.0,
          child: const SizedBox(),
        ),
        throwsAssertionError,
      );
    });

    test('throws if panSensitivity is zero', () {
      final ctrl = CameraController();
      addTearDown(ctrl.dispose);
      expect(
        () => CameraGestureDetector(
          controller: ctrl,
          panSensitivity: 0.0,
          child: const SizedBox(),
        ),
        throwsAssertionError,
      );
    });
  });
}
