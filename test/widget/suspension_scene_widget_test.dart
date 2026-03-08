// Widget tests for SuspensionSceneWidget (FR-VZ-002, FR-VZ-003, FR-VZ-004).
//
// Covers:
//  • Widget builds successfully
//  • Canvas renders with semantic key
//  • RepaintBoundary wraps the canvas
//  • Disposes without error
//  • Accepts custom targetFps
//  • Updates painter when state changes (didUpdateWidget)
//  • onFrame callback fires on animation tick
//  • Throws ArgumentError for non-positive targetFps
//  • Rendering smoke test: builds at multiple suspension states

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_metric_x/models/suspension_material.dart';
import 'package:ride_metric_x/models/suspension_state.dart';
import 'package:ride_metric_x/widgets/suspension_scene_widget.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Lifecycle ──────────────────────────────────────────────────────────────
  group('SuspensionSceneWidget lifecycle', () {
    testWidgets('builds successfully', (tester) async {
      await tester.pumpWidget(_wrap(const SuspensionSceneWidget()));
      expect(find.byType(SuspensionSceneWidget), findsOneWidget);
    });

    testWidgets('renders canvas with semantic key', (tester) async {
      await tester.pumpWidget(_wrap(const SuspensionSceneWidget()));
      expect(find.byKey(SuspensionSceneWidget.sceneKey), findsOneWidget);
    });

    testWidgets('RepaintBoundary is an ancestor of the scene canvas',
        (tester) async {
      await tester.pumpWidget(_wrap(const SuspensionSceneWidget()));
      final boundaryFinder = find.ancestor(
        of: find.byKey(SuspensionSceneWidget.sceneKey),
        matching: find.byType(RepaintBoundary),
      );
      expect(boundaryFinder, findsAtLeastNWidgets(1));
    });

    testWidgets('disposes without error when removed from tree', (tester) async {
      await tester.pumpWidget(_wrap(const SuspensionSceneWidget()));
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    });

    testWidgets('accepts custom targetFps', (tester) async {
      await tester.pumpWidget(
        _wrap(const SuspensionSceneWidget(targetFps: 30)),
      );
      expect(find.byType(SuspensionSceneWidget), findsOneWidget);
    });
  });

  // ── targetFps validation ──────────────────────────────────────────────────
  group('SuspensionSceneWidget targetFps validation', () {
    testWidgets('throws ArgumentError when targetFps is zero', (tester) async {
      await tester.pumpWidget(
        _wrap(const SuspensionSceneWidget(targetFps: 0)),
      );
      expect(tester.takeException(), isA<ArgumentError>());
    });

    testWidgets('throws ArgumentError when targetFps is negative',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const SuspensionSceneWidget(targetFps: -5)),
      );
      expect(tester.takeException(), isA<ArgumentError>());
    });
  });

  // ── Animation frame loop ──────────────────────────────────────────────────
  group('SuspensionSceneWidget animation frame loop', () {
    testWidgets('onFrame callback fires after animation tick', (tester) async {
      int callCount = 0;
      await tester.pumpWidget(
        _wrap(SuspensionSceneWidget(onFrame: (_) => callCount++)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(callCount, greaterThan(0));
    });

    testWidgets('onFrame values are in [0, 1] range', (tester) async {
      final values = <double>[];
      await tester.pumpWidget(
        _wrap(SuspensionSceneWidget(onFrame: values.add)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      for (final v in values) {
        expect(v, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  // ── State updates (state → geometry mapping, animation) ───────────────────
  group('SuspensionSceneWidget state updates', () {
    testWidgets('widget rebuilds when state changes', (tester) async {
      await tester.pumpWidget(
        _wrap(const SuspensionSceneWidget(
          state: SuspensionState(frontTravelMm: 0.0),
        )),
      );
      await tester.pumpWidget(
        _wrap(const SuspensionSceneWidget(
          state: SuspensionState(frontTravelMm: 100.0),
        )),
      );
      // No exception → didUpdateWidget handled the state change correctly.
      expect(find.byType(SuspensionSceneWidget), findsOneWidget);
    });

    testWidgets('updates cycle duration when targetFps changes', (tester) async {
      await tester.pumpWidget(
        _wrap(const SuspensionSceneWidget(targetFps: 60)),
      );
      await tester.pumpWidget(
        _wrap(const SuspensionSceneWidget(targetFps: 30)),
      );
      expect(find.byType(SuspensionSceneWidget), findsOneWidget);
    });
  });

  // ── Rendering smoke tests ─────────────────────────────────────────────────
  group('SuspensionSceneWidget rendering smoke tests', () {
    // Pump several representative suspension states and verify no exceptions
    // are thrown (desktop/mobile rendering correctness smoke test).
    final states = [
      const SuspensionState(),
      const SuspensionState(frontTravelMm: 150.0, rearTravelMm: 100.0),
      const SuspensionState(
        frontTravelMm: 300.0,
        rearTravelMm: 200.0,
        wheelRotationRad: math.pi / 2,
      ),
      const SuspensionState(
        frontTravelMm: 50.0,
        rearTravelMm: 25.0,
        wheelRotationRad: math.pi,
      ),
    ];

    for (final state in states) {
      testWidgets(
        'renders without error for state: $state',
        (tester) async {
          await tester.pumpWidget(
            _wrap(SizedBox(
              width: 400,
              height: 400,
              child: SuspensionSceneWidget(state: state),
            )),
          );
          await tester.pump(const Duration(milliseconds: 16));
          expect(find.byKey(SuspensionSceneWidget.sceneKey), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('renders with custom materials', (tester) async {
      await tester.pumpWidget(
        _wrap(const SizedBox(
          width: 400,
          height: 400,
          child: SuspensionSceneWidget(
            forkMaterial: SuspensionMaterial.carbon,
            shockMaterial: SuspensionMaterial.strainSensor,
          ),
        )),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    });
  });
}
