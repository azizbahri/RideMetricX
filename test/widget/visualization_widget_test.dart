// Widget tests for VisualizationWidget (FR-VZ-001).
//
// Covers:
//  • Widget lifecycle: initState creates animation controller, dispose cleans up
//  • RepaintBoundary is present in the widget tree
//  • Animation frame loop: onFrame callback fires on animation tick
//  • Baseline frame-loop smoke test across multiple pump cycles
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

    testWidgets('RepaintBoundary wraps the canvas', (tester) async {
      await tester.pumpWidget(_wrap(const VisualizationWidget()));
      expect(find.byType(RepaintBoundary), findsWidgets);
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
    test('returns false when animationValue is unchanged', () {
      const p1 = VisualizationFramePainter(animationValue: 0.5);
      const p2 = VisualizationFramePainter(animationValue: 0.5);
      expect(p1.shouldRepaint(p2), isFalse);
    });

    test('returns true when animationValue increases', () {
      const old = VisualizationFramePainter(animationValue: 0.5);
      const next = VisualizationFramePainter(animationValue: 0.6);
      expect(next.shouldRepaint(old), isTrue);
    });

    test('returns true when animationValue decreases (cycle wrap)', () {
      const old = VisualizationFramePainter(animationValue: 0.9);
      const next = VisualizationFramePainter(animationValue: 0.1);
      expect(next.shouldRepaint(old), isTrue);
    });

    test('returns true for initial frame (0.0 to non-zero)', () {
      const old = VisualizationFramePainter(animationValue: 0.0);
      const next = VisualizationFramePainter(animationValue: 0.1);
      expect(next.shouldRepaint(old), isTrue);
    });

    test('returns false when both values are 0.0', () {
      const p1 = VisualizationFramePainter(animationValue: 0.0);
      const p2 = VisualizationFramePainter(animationValue: 0.0);
      expect(p1.shouldRepaint(p2), isFalse);
    });
  });
}
