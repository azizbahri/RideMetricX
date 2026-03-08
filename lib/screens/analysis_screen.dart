import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/telemetry_series.dart';
import '../widgets/telemetry_chart.dart';

// ── ChartTab ──────────────────────────────────────────────────────────────────

/// Defines a single named tab in the [AnalysisScreen] workspace.
class ChartTab {
  const ChartTab({
    required this.title,
    required this.series,
    this.xLabel = 'Time (ms)',
    this.yLabel = 'Value',
  });

  /// Tab label shown in the [TabBar].
  final String title;

  /// Data series rendered inside this tab's [TelemetryChart].
  final List<TelemetrySeries> series;

  /// X-axis label forwarded to [TelemetryChart].
  final String xLabel;

  /// Y-axis label forwarded to [TelemetryChart].
  final String yLabel;
}

// ── AnalysisScreen ────────────────────────────────────────────────────────────

/// Tabbed telemetry analysis workspace (FR-UI-006).
///
/// Renders one [TelemetryChart] per [ChartTab] inside a [TabBarView].  Chart
/// state (zoom / pan / crosshair) is preserved across tab switches via
/// [AutomaticKeepAliveClientMixin] inside [TelemetryChart].
///
/// When [tabs] is omitted the screen renders a built-in demo dataset so the
/// workspace is useful before real session data is wired up.
class AnalysisScreen extends StatelessWidget {
  const AnalysisScreen({super.key, this.tabs});

  /// Optional override for the chart tabs.  Inject a custom list in tests.
  final List<ChartTab>? tabs;

  // ── Semantic keys for tests ──────────────────────────────────────────────
  static const Key tabBarKey = Key('analysis_tab_bar');

  @override
  Widget build(BuildContext context) {
    final effectiveTabs = tabs ?? _buildDemoTabs();

    if (effectiveTabs.isEmpty) {
      return const _EmptyState();
    }

    return DefaultTabController(
      length: effectiveTabs.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTabBar(context, effectiveTabs),
          Expanded(
            child: TabBarView(
              children: [
                for (final tab in effectiveTabs) _ChartTabPage(tab: tab),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(BuildContext context, List<ChartTab> tabs) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 1,
      child: TabBar(
        key: tabBarKey,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: [
          for (final tab in tabs)
            Tab(key: ValueKey(tab.title), text: tab.title),
        ],
      ),
    );
  }
}

// ── Individual tab page ───────────────────────────────────────────────────────

/// Wraps a [TelemetryChart] with a [ScaffoldMessenger]-aware export handler.
class _ChartTabPage extends StatelessWidget {
  const _ChartTabPage({required this.tab});

  final ChartTab tab;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: TelemetryChart(
        // Stable key per tab title so tests can target specific charts when
        // AutomaticKeepAliveClientMixin keeps multiple tabs alive simultaneously.
        key: ValueKey('chart_${tab.title}'),
        series: tab.series,
        xLabel: tab.xLabel,
        yLabel: tab.yLabel,
        onExport: () => _onExport(context, tab),
      ),
    );
  }

  void _onExport(BuildContext context, ChartTab tab) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exporting "${tab.title}" as CSV…'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.show_chart, size: 64, color: colorScheme.outline),
          const SizedBox(height: 16),
          Text('No data to display', style: textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Import a session to start plotting',
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

// ── Demo data ─────────────────────────────────────────────────────────────────

/// Generates synthetic IMU-like tabs for the demo / empty-session state.
List<ChartTab> _buildDemoTabs() {
  const int sampleCount = 500;
  const double dt = 5.0; // ms per sample → 200 Hz

  // Synthetic front-sensor acceleration (damped oscillation).
  final frontAccel = List.generate(sampleCount, (i) {
    final t = i * dt;
    return Offset(
      t,
      1.2 * math.exp(-i / 120.0) * math.sin(i * 0.35) +
          0.3 * math.sin(i * 0.12),
    );
  });

  // Synthetic rear-sensor acceleration (phase-shifted).
  final rearAccel = List.generate(sampleCount, (i) {
    final t = i * dt;
    return Offset(
      t,
      0.9 * math.exp(-i / 100.0) * math.sin(i * 0.35 + 0.8) +
          0.25 * math.sin(i * 0.12 + 0.4),
    );
  });

  // Synthetic gyro (smoother, lower amplitude).
  final frontGyro = List.generate(sampleCount, (i) {
    final t = i * dt;
    return Offset(
      t,
      15.0 * math.exp(-i / 80.0) * math.sin(i * 0.28) +
          5.0 * math.sin(i * 0.08),
    );
  });

  final rearGyro = List.generate(sampleCount, (i) {
    final t = i * dt;
    return Offset(
      t,
      12.0 * math.exp(-i / 90.0) * math.sin(i * 0.28 + 1.0) +
          4.0 * math.sin(i * 0.08 + 0.6),
    );
  });

  // Scatter plot: peak-detection overlay on front acceleration.
  final peaks = <Offset>[];
  for (int i = 1; i < frontAccel.length - 1; i++) {
    if (frontAccel[i].dy > frontAccel[i - 1].dy &&
        frontAccel[i].dy > frontAccel[i + 1].dy &&
        frontAccel[i].dy.abs() > 0.4) {
      peaks.add(frontAccel[i]);
    }
  }

  return [
    ChartTab(
      title: 'Acceleration',
      xLabel: 'Time (ms)',
      yLabel: 'Accel (m/s²)',
      series: [
        TelemetrySeries(
          label: 'Front Z',
          color: Colors.blue,
          points: frontAccel,
        ),
        TelemetrySeries(
          label: 'Rear Z',
          color: Colors.orange,
          points: rearAccel,
        ),
        TelemetrySeries(
          label: 'Peaks',
          color: Colors.red,
          points: peaks,
          plotType: PlotType.scatter,
        ),
      ],
    ),
    ChartTab(
      title: 'Angular Rate',
      xLabel: 'Time (ms)',
      yLabel: 'Gyro (deg/s)',
      series: [
        TelemetrySeries(
          label: 'Front Z',
          color: Colors.teal,
          points: frontGyro,
        ),
        TelemetrySeries(
          label: 'Rear Z',
          color: Colors.deepPurple,
          points: rearGyro,
        ),
      ],
    ),
  ];
}
