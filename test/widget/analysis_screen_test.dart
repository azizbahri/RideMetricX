// Widget tests for AnalysisScreen and TelemetryChart (FR-UI-006).
//
// Covers:
//  • Tab rendering and selection
//  • Chart state (viewport) is retained across tab switches
//  • Legend labels match the supplied series
//  • Export button triggers the snackbar callback
//  • Large dataset renders without error (performance / decimation budget)
//  • Empty-screen state when no tabs are provided
//  • TelemetryChart.decimate reduces large point lists

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/models/telemetry_series.dart';
import 'package:ride_metric_x/screens/analysis_screen.dart';
import 'package:ride_metric_x/widgets/telemetry_chart.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Pumps an [AnalysisScreen] wrapped in a minimal app.
Future<void> _pumpAnalysis(
  WidgetTester tester, {
  List<ChartTab>? tabs,
}) async {
  await tester.pumpWidget(
    _wrap(AnalysisScreen(tabs: tabs)),
  );
  await tester.pump(); // settle initial frame
}

/// Builds a simple [ChartTab] with two series for use in tests.
ChartTab _makeTab({
  String title = 'Test Tab',
  List<TelemetrySeries>? series,
}) {
  return ChartTab(
    title: title,
    xLabel: 'ms',
    yLabel: 'val',
    series: series ??
        [
          TelemetrySeries(
            label: 'Series A',
            color: Colors.blue,
            points:
                List.generate(10, (i) => Offset(i.toDouble(), i.toDouble())),
          ),
          TelemetrySeries(
            label: 'Series B',
            color: Colors.red,
            points:
                List.generate(10, (i) => Offset(i.toDouble(), -i.toDouble())),
          ),
        ],
  );
}

/// Returns a [Finder] for the canvas [GestureDetector] of a chart keyed with
/// [chartId].  Charts are keyed `ValueKey('chart_$chartId')` and the canvas
/// is the derived key `ValueKey('chart_${chartId}_canvas')`.
Finder _canvasFinder(String chartId) =>
    find.byKey(ValueKey('chart_${chartId}_canvas'));

/// Returns a [Finder] for the export button of a chart keyed with [chartId].
Finder _exportFinder(String chartId) =>
    find.byKey(ValueKey('chart_${chartId}_export'));

/// Returns a [Finder] for the "Reset View" button of a chart keyed with
/// [chartId].
Finder _resetFinder(String chartId) =>
    find.byKey(ValueKey('chart_${chartId}_reset'));

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Rendering ───────────────────────────────────────────────────────────────
  group('AnalysisScreen rendering', () {
    testWidgets('renders tab bar when tabs are provided',
        (WidgetTester tester) async {
      await _pumpAnalysis(tester, tabs: [_makeTab(title: 'Accel')]);

      expect(find.byKey(AnalysisScreen.tabBarKey), findsOneWidget);
    });

    testWidgets('tab bar contains correct tab labels',
        (WidgetTester tester) async {
      await _pumpAnalysis(
        tester,
        tabs: [_makeTab(title: 'Accel'), _makeTab(title: 'Gyro')],
      );

      expect(find.text('Accel'), findsOneWidget);
      expect(find.text('Gyro'), findsOneWidget);
    });

    testWidgets('shows empty state when tabs list is empty',
        (WidgetTester tester) async {
      await _pumpAnalysis(tester, tabs: const []);

      expect(find.text('No data to display'), findsOneWidget);
      expect(find.byKey(AnalysisScreen.tabBarKey), findsNothing);
    });

    testWidgets('shows TelemetryChart for the active tab',
        (WidgetTester tester) async {
      await _pumpAnalysis(tester, tabs: [_makeTab()]);

      expect(find.byType(TelemetryChart), findsOneWidget);
    });

    testWidgets('demo data renders when no tabs argument is given',
        (WidgetTester tester) async {
      await _pumpAnalysis(tester);

      // The demo builds at least 2 tabs.
      expect(find.byKey(AnalysisScreen.tabBarKey), findsOneWidget);
      expect(find.byType(TelemetryChart), findsOneWidget);
    });
  });

  // ── Tab selection ────────────────────────────────────────────────────────────
  group('AnalysisScreen tab selection', () {
    testWidgets('tapping second tab shows second chart',
        (WidgetTester tester) async {
      final tab1 = _makeTab(
        title: 'Accel',
        series: [
          const TelemetrySeries(
              label: 'Front Z', color: Colors.blue, points: [Offset.zero]),
        ],
      );
      final tab2 = _makeTab(
        title: 'Gyro',
        series: [
          const TelemetrySeries(
              label: 'Gyro X', color: Colors.green, points: [Offset.zero]),
        ],
      );

      await _pumpAnalysis(tester, tabs: [tab1, tab2]);

      // Initially tab1 is selected; its legend label is visible.
      expect(find.text('Front Z'), findsOneWidget);

      // Tap the second tab.
      await tester.tap(find.text('Gyro'));
      await tester.pumpAndSettle();

      // Now tab2's legend label should be visible.
      expect(find.text('Gyro X'), findsOneWidget);
    });

    testWidgets('switching back to first tab restores it',
        (WidgetTester tester) async {
      final tab1 = _makeTab(title: 'A');
      final tab2 = _makeTab(title: 'B');

      await _pumpAnalysis(tester, tabs: [tab1, tab2]);

      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();

      // Tab A's chart must be in the tree. Use the per-tab stable key to
      // avoid ambiguity if AutomaticKeepAliveClientMixin keeps tab B alive.
      expect(find.byKey(const ValueKey('chart_A')), findsOneWidget);
    });
  });

  // ── State retention ──────────────────────────────────────────────────────────
  group('Chart state retention across tab switches', () {
    testWidgets(
        'TelemetryChartState is the same instance after round-trip tab switch',
        (WidgetTester tester) async {
      final tab1 = _makeTab(title: 'Tab1');
      final tab2 = _makeTab(title: 'Tab2');

      await _pumpAnalysis(tester, tabs: [tab1, tab2]);

      // Capture the state instance of the chart in tab1.
      // Use the stable per-tab key to avoid ambiguity when
      // AutomaticKeepAliveClientMixin keeps multiple charts in the tree.
      final tab1ChartFinder = find.byKey(const ValueKey('chart_Tab1'));
      final stateBeforeSwitch =
          tester.state<TelemetryChartState>(tab1ChartFinder);

      // Switch to tab2.
      await tester.tap(find.text('Tab2'));
      await tester.pumpAndSettle();

      // Switch back to tab1.
      await tester.tap(find.text('Tab1'));
      await tester.pumpAndSettle();

      // The state instance must be the same object (kept alive, not recreated).
      final stateAfterSwitch =
          tester.state<TelemetryChartState>(tab1ChartFinder);
      expect(identical(stateBeforeSwitch, stateAfterSwitch), isTrue);
    });

    testWidgets('viewport remains modified after tab round-trip',
        (WidgetTester tester) async {
      final tab1 = _makeTab(title: 'Tab1');
      final tab2 = _makeTab(title: 'Tab2');

      await _pumpAnalysis(tester, tabs: [tab1, tab2]);

      // Drag the chart canvas vertically to modify the viewport.
      // A horizontal drag would be intercepted by the TabBarView's PageView
      // gesture recognizer; vertical drags are unambiguous.
      await tester.drag(_canvasFinder('Tab1'), const Offset(0, 40));
      await tester.pump();

      // Verify the viewport was modified (Reset View button appears).
      expect(_resetFinder('Tab1'), findsOneWidget);

      // Switch to tab2 and back.
      await tester.tap(find.text('Tab2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tab1'));
      await tester.pumpAndSettle();

      // The viewport modification should still be in effect.
      expect(_resetFinder('Tab1'), findsOneWidget);
    });
  });

  // ── Series correctness ───────────────────────────────────────────────────────
  group('Plotted series correctness', () {
    testWidgets('legend shows all series labels in the active tab',
        (WidgetTester tester) async {
      const seriesALabel = 'Accel Z Front';
      const seriesBLabel = 'Gyro Z Rear';

      final tab = _makeTab(
        title: 'Mixed',
        series: [
          const TelemetrySeries(
            label: seriesALabel,
            color: Colors.blue,
            points: [Offset(0, 1), Offset(1, 2)],
          ),
          const TelemetrySeries(
            label: seriesBLabel,
            color: Colors.orange,
            points: [Offset(0, 0.5), Offset(1, 0.8)],
            plotType: PlotType.scatter,
          ),
        ],
      );

      await _pumpAnalysis(tester, tabs: [tab]);

      expect(find.text(seriesALabel), findsOneWidget);
      expect(find.text(seriesBLabel), findsOneWidget);
    });

    testWidgets('switching tabs shows the correct series for each tab',
        (WidgetTester tester) async {
      final tabA = _makeTab(
        title: 'A',
        series: [
          const TelemetrySeries(
              label: 'AlphaChannel', color: Colors.blue, points: [Offset.zero]),
        ],
      );
      final tabB = _makeTab(
        title: 'B',
        series: [
          const TelemetrySeries(
              label: 'BetaChannel', color: Colors.red, points: [Offset.zero]),
        ],
      );

      await _pumpAnalysis(tester, tabs: [tabA, tabB]);

      expect(find.text('AlphaChannel'), findsOneWidget);
      expect(find.text('BetaChannel'), findsNothing);

      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();

      expect(find.text('BetaChannel'), findsOneWidget);
      expect(find.text('AlphaChannel'), findsNothing);
    });

    testWidgets('empty series list renders chart without legend',
        (WidgetTester tester) async {
      const tab = ChartTab(
        title: 'Empty',
        series: [],
        xLabel: 'ms',
        yLabel: 'val',
      );

      await _pumpAnalysis(tester, tabs: [tab]);

      // Chart is present but no legend rows.
      expect(find.byType(TelemetryChart), findsOneWidget);
      // No series labels rendered in a legend.
      expect(find.text('Series A'), findsNothing);
    });
  });

  // ── Export action ─────────────────────────────────────────────────────────────
  group('Export action', () {
    testWidgets('tapping export button shows snackbar',
        (WidgetTester tester) async {
      await _pumpAnalysis(tester, tabs: [_makeTab(title: 'Accel')]);

      await tester.tap(_exportFinder('Accel'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('Accel'),
        ),
        findsOneWidget,
      );
    });
  });

  // ── Reset view ────────────────────────────────────────────────────────────────
  group('Reset view button', () {
    testWidgets('reset button is hidden initially',
        (WidgetTester tester) async {
      await _pumpAnalysis(tester, tabs: [_makeTab()]);

      expect(_resetFinder('Test Tab'), findsNothing);
    });

    testWidgets('reset button appears after viewport is panned',
        (WidgetTester tester) async {
      await _pumpAnalysis(tester, tabs: [_makeTab()]);

      await tester.drag(_canvasFinder('Test Tab'), const Offset(30, 0));
      await tester.pump();

      expect(_resetFinder('Test Tab'), findsOneWidget);
    });

    testWidgets('tapping reset button hides the reset button',
        (WidgetTester tester) async {
      await _pumpAnalysis(tester, tabs: [_makeTab()]);

      // Pan to make the button appear.
      await tester.drag(_canvasFinder('Test Tab'), const Offset(30, 0));
      await tester.pump();

      // Tap the reset button.
      await tester.tap(_resetFinder('Test Tab'));
      await tester.pump();

      // Button should disappear again.
      expect(_resetFinder('Test Tab'), findsNothing);
    });
  });

  // ── Performance / decimation budget ──────────────────────────────────────────
  group('Large dataset rendering budget (NFR-UI-005)', () {
    testWidgets('chart renders 100 000-point series without error',
        (WidgetTester tester) async {
      final points = List.generate(
        100000,
        (i) => Offset(i.toDouble(), math.sin(i * 0.01)),
      );

      final tab = ChartTab(
        title: 'BigData',
        series: [
          TelemetrySeries(label: 'Signal', color: Colors.blue, points: points),
        ],
        xLabel: 'ms',
        yLabel: 'g',
      );

      await _pumpAnalysis(tester, tabs: [tab]);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    test('decimate reduces a 100 000-point list to ≤ 2× maxRenderedPoints', () {
      const maxPoints = 2000;
      final points = List.generate(
        100000,
        (i) => Offset(i.toDouble(), math.sin(i * 0.01)),
      );

      final result = TelemetryChart.decimate(points, maxPoints);

      // Each bucket contributes at most 2 points (min + max).
      expect(result.length, lessThanOrEqualTo(2 * maxPoints));
      expect(result, isNotEmpty);
    });

    test('decimate returns original list when it is shorter than maxPoints',
        () {
      final points =
          List.generate(100, (i) => Offset(i.toDouble(), i.toDouble()));

      final result = TelemetryChart.decimate(points, 2000);

      expect(identical(result, points), isTrue);
    });

    test('decimate handles empty input', () {
      final result = TelemetryChart.decimate(const [], 500);
      expect(result, isEmpty);
    });

    test('decimate with maxPoints = 0 returns empty list', () {
      final points =
          List.generate(10, (i) => Offset(i.toDouble(), i.toDouble()));
      final result = TelemetryChart.decimate(points, 0);
      expect(result, isEmpty);
    });
  });

  // ── TelemetryChart.decimateForViewport ─────────────────────────────────────

  group('TelemetryChart.decimateForViewport', () {
    /// Full-range viewport that covers all 1 000 points (x: 0 – 999).
    const fullViewport = ChartViewport(
      xMin: 0,
      xMax: 999,
      yMin: -1,
      yMax: 1,
    );

    /// Zoomed-in viewport covering only x: 0 – 99 (10 % of the data).
    const zoomedViewport = ChartViewport(
      xMin: 0,
      xMax: 99,
      yMin: -1,
      yMax: 1,
    );

    late List<Offset> points1k;

    setUp(() {
      points1k = List.generate(
        1000,
        (i) => Offset(i.toDouble(), math.sin(i * 0.01)),
      );
    });

    test('returns empty list when maxPoints is 0', () {
      final result =
          TelemetryChart.decimateForViewport(points1k, 0, fullViewport);
      expect(result, isEmpty);
    });

    test('returns empty list when no points fall in viewport', () {
      const outOfRange =
          ChartViewport(xMin: 2000, xMax: 3000, yMin: -1, yMax: 1);
      final result =
          TelemetryChart.decimateForViewport(points1k, 200, outOfRange);
      expect(result, isEmpty);
    });

    test('result is bounded by 2 × maxPoints', () {
      const maxPoints = 200;
      final result = TelemetryChart.decimateForViewport(
          points1k, maxPoints, zoomedViewport);
      expect(result.length, lessThanOrEqualTo(2 * maxPoints));
      expect(result, isNotEmpty);
    });

    test(
        'zoomed-in result has higher point density than global decimation '
        'for large dataset', () {
      // 100 000 points is large enough to demonstrate the density
      // improvement while keeping CI fast (no 1M trig calls).
      // y-values use a sawtooth (modulo) to avoid math.sin overhead.
      const totalPoints = 100000;
      const maxRendered = 2000;
      final bigPoints = List.generate(
        totalPoints,
        (i) => Offset(i.toDouble(), (i % 200).toDouble()),
      );

      // Viewport covers only the first 1 % of the data range (x: 0–999).
      const viewport = ChartViewport(
        xMin: 0,
        xMax: 999,
        yMin: -1,
        yMax: 201,
      );

      final globalResult = TelemetryChart.decimate(bigPoints, maxRendered);
      final viewportResult = TelemetryChart.decimateForViewport(
          bigPoints, maxRendered, viewport);

      // Global decimation spreads 2 000 points across the entire 100 K range.
      // In the first 1% window (x 0–999) there should be only ~20 global
      // points, whereas viewport-aware decimation provides up to 4 000 (2 ×
      // maxRendered) for exactly that window — a ≥10× improvement in density.
      final globalInWindow =
          globalResult.where((p) => p.dx >= 0 && p.dx <= 999).length;
      expect(
        viewportResult.length,
        greaterThan(globalInWindow * 5),
        reason: 'viewport decimation should give at least 5× more points '
            'inside the zoomed window than global decimation',
      );
    });

    test('includes buffer region beyond viewport edges', () {
      // Viewport: x 400–600. Buffer (10 %) adds 20 units on each side.
      const viewport =
          ChartViewport(xMin: 400, xMax: 600, yMin: -1, yMax: 1);
      final result =
          TelemetryChart.decimateForViewport(points1k, 500, viewport);

      // With a 10 % buffer the window is x [380, 620].  There should be
      // points with dx < 400 and dx > 600 in the result (unless maxPoints
      // decimation removed them, which it shouldn't for a 500-point budget).
      expect(result.any((p) => p.dx < 400), isTrue,
          reason: 'buffer region below viewport.xMin should be included');
      expect(result.any((p) => p.dx > 600), isTrue,
          reason: 'buffer region above viewport.xMax should be included');
    });
  });
}
