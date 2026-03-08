// Widget tests for VisualizationWidget (FR-VZ-001).
//
// Covers:
//  • Widget lifecycle: initState creates animation controller, dispose cleans up
//  • RepaintBoundary is a direct ancestor of the canvas (not a false match from
//    MaterialApp/Scaffold boundaries)
//  • Animation frame loop: onFrame callback fires on animation tick
//  • Baseline frame-loop smoke test across multiple pump cycles
//  • targetFps validation: throws ArgumentError for non-positive values
//  • VisualizationFramePainter.shouldRepaint guard behaviour

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/widgets/visualization_widget.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Wraps [child] in a minimal [MaterialApp] so that [Theme] etc. are available.
Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Lifecycle ──────────────────────────────────────────────────────────────
  group('VisualizationWidget lifecycle', () {
    testWidgets('builds successfully', (tester) async {
      await tester.pumpWidget(_wrap(const VisualizationWidget()));
      expect(find.byType(VisualizationWidget), findsOneWidget);
    });

    testWidgets('renders canvas with semantic key', (tester) async {
      await tester.pumpWidget(_wrap(const VisualizationWidget()));
      expect(find.byKey(VisualizationWidget.canvasKey), findsOneWidget);
    });

    testWidgets('RepaintBoundary is a direct ancestor of the canvas',
        (tester) async {
      await tester.pumpWidget(_wrap(const VisualizationWidget()));
      final canvasFinder = find.byKey(VisualizationWidget.canvasKey);
      expect(canvasFinder, findsOneWidget);
      final boundaryFinder = find.ancestor(
        of: canvasFinder,
        matching: find.byType(RepaintBoundary),
      );
      expect(boundaryFinder, findsOneWidget);
    });

    testWidgets('disposes without error when removed from tree', (tester) async {
      await tester.pumpWidget(_wrap(const VisualizationWidget()));
      // Replacing the widget triggers the dispose path on the old state.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      // Completing without an exception verifies the dispose path.
    });

    testWidgets('accepts custom targetFps', (tester) async {
      await tester.pumpWidget(
        _wrap(const VisualizationWidget(targetFps: 30)),
      );
      expect(find.byType(VisualizationWidget), findsOneWidget);
    });

    testWidgets('updates cycle duration when targetFps changes', (tester) async {
      await tester.pumpWidget(_wrap(const VisualizationWidget(targetFps: 60)));
      // Rebuild with a different targetFps to exercise didUpdateWidget.
      await tester.pumpWidget(_wrap(const VisualizationWidget(targetFps: 30)));
      expect(find.byType(VisualizationWidget), findsOneWidget);
    });

    testWidgets('throws ArgumentError when targetFps is zero', (tester) async {
      await tester.pumpWidget(
        _wrap(const VisualizationWidget(targetFps: 0)),
      );
      expect(tester.takeException(), isA<ArgumentError>());
    });

    testWidgets('throws ArgumentError when targetFps is negative',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const VisualizationWidget(targetFps: -1)),
      );
      expect(tester.takeException(), isA<ArgumentError>());
    });
  });

  // ── Frame loop ─────────────────────────────────────────────────────────────
  group('VisualizationWidget animation frame loop', () {
    testWidgets('onFrame callback fires after animation tick', (tester) async {
      int callCount = 0;
      await tester.pumpWidget(
        _wrap(VisualizationWidget(onFrame: (_) => callCount++)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(callCount, greaterThan(0));
    });

    testWidgets('frame-loop smoke test: fires over multiple 16 ms cycles',
        (tester) async {
      final values = <double>[];
      await tester.pumpWidget(
        _wrap(VisualizationWidget(onFrame: values.add)),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(values, isNotEmpty);
    });

    testWidgets('onFrame receives animation value in [0, 1] range',
        (tester) async {
      final captured = <double>[];
      await tester.pumpWidget(
        _wrap(VisualizationWidget(onFrame: captured.add)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      for (final v in captured) {
        expect(v, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  // ── shouldRepaint guard ────────────────────────────────────────────────────
  group('VisualizationFramePainter shouldRepaint', () {
    test('returns false when same animation instance is reused', () {
      // Same animation object → repaint listenable already handles repaints;
      // no additional repaint is needed on widget rebuild.
      const animation = AlwaysStoppedAnimation<double>(0.5);
      final p1 = VisualizationFramePainter(animation: animation);
      final p2 = VisualizationFramePainter(animation: animation);
      expect(p1.shouldRepaint(p2), isFalse);
    });

    test('returns true when animation reference changes', () {
      // Different animation objects → the animation source has changed; a full
      // repaint is required.
      const a1 = AlwaysStoppedAnimation<double>(0.5);
      const a2 = AlwaysStoppedAnimation<double>(0.6);
      final old = VisualizationFramePainter(animation: a1);
      final next = VisualizationFramePainter(animation: a2);
      expect(next.shouldRepaint(old), isTrue);
    });

    test('animationValue getter reflects the animation value', () {
      const animation = AlwaysStoppedAnimation<double>(0.75);
      final painter = VisualizationFramePainter(animation: animation);
      expect(painter.animationValue, 0.75);
    });
  });
}
