import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/telemetry_series.dart';

// ── Viewport ──────────────────────────────────────────────────────────────────

/// The data-space rectangle that is currently visible in the chart.
@immutable
class ChartViewport {
  final double xMin;
  final double xMax;
  final double yMin;
  final double yMax;

  const ChartViewport({
    required this.xMin,
    required this.xMax,
    required this.yMin,
    required this.yMax,
  });

  double get xRange => xMax - xMin;
  double get yRange => yMax - yMin;

  /// Returns `true` when the viewport has zero or negative extent and cannot
  /// be meaningfully rendered.
  bool get isDegenerate => xRange <= 0 || yRange <= 0;

  ChartViewport copyWith({
    double? xMin,
    double? xMax,
    double? yMin,
    double? yMax,
  }) =>
      ChartViewport(
        xMin: xMin ?? this.xMin,
        xMax: xMax ?? this.xMax,
        yMin: yMin ?? this.yMin,
        yMax: yMax ?? this.yMax,
      );

  @override
  bool operator ==(Object other) =>
      other is ChartViewport &&
      xMin == other.xMin &&
      xMax == other.xMax &&
      yMin == other.yMin &&
      yMax == other.yMax;

  @override
  int get hashCode => Object.hash(xMin, xMax, yMin, yMax);

  @override
  String toString() => 'ChartViewport(x: [$xMin, $xMax], y: [$yMin, $yMax])';
}

// ── TelemetryChart ────────────────────────────────────────────────────────────

/// A telemetry chart with zoom/pan/select interactions (FR-UI-006).
///
/// Renders one or more [TelemetrySeries] over a shared x-axis. Zoom and pan
/// are handled via scale/drag gestures. Tapping the canvas places a crosshair
/// at the selected data position. An export button calls [onExport] when set.
///
/// The chart state (viewport, crosshair) is kept alive across [TabBarView]
/// transitions via [AutomaticKeepAliveClientMixin].
class TelemetryChart extends StatefulWidget {
  const TelemetryChart({
    super.key,
    required this.series,
    this.xLabel = 'Time (ms)',
    this.yLabel = 'Value',
    this.onExport,
    this.maxRenderedPoints = 2000,
  });

  /// The data series to plot. May be empty (renders empty axes).
  final List<TelemetrySeries> series;

  /// Label shown below the x-axis.
  final String xLabel;

  /// Label shown to the left of the y-axis.
  final String yLabel;

  /// Called when the user taps the export button. If `null` the button is
  /// disabled.
  final VoidCallback? onExport;

  /// Maximum number of points rendered per series after decimation.
  /// Limits rendering cost for large datasets (NFR-UI-005).
  final int maxRenderedPoints;

  // ── Semantic keys for tests ────────────────────────────────────────────────
  static const Key exportButtonKey = Key('telemetry_chart_export');
  static const Key resetZoomKey = Key('telemetry_chart_reset_zoom');
  static const Key chartCanvasKey = Key('telemetry_chart_canvas');

  /// Reduces [points] to at most [maxPoints] while preserving signal shape by
  /// retaining the min/max envelope within each bucket.
  ///
  /// Exposed as a static method so unit tests can verify the decimation logic
  /// directly without pumping a widget.
  static List<Offset> decimate(List<Offset> points, int maxPoints) {
    return _decimate(points, maxPoints);
  }

  @override
  TelemetryChartState createState() => TelemetryChartState();
}

// ── State ─────────────────────────────────────────────────────────────────────

/// Public state class so that tests can obtain a reference via
/// `tester.state<TelemetryChartState>(...)` and inspect observable properties
/// such as [viewportModified].
class TelemetryChartState extends State<TelemetryChart>
    with AutomaticKeepAliveClientMixin {
  late ChartViewport _defaultViewport;
  late ChartViewport _viewport;
  bool _viewportModified = false;

  // Crosshair position in canvas-space coordinates, or null.
  Offset? _crosshair;

  // Baseline captured at the start of each scale/pan gesture.
  ChartViewport? _gestureBaseViewport;
  Offset? _gestureFocalStart;

  // ── Public API for tests ───────────────────────────────────────────────────

  /// The current data-space viewport.
  ChartViewport get viewport => _viewport;

  /// Whether the user has panned or zoomed away from the auto-fitted default.
  bool get viewportModified => _viewportModified;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _defaultViewport = _computeDefaultViewport();
    _viewport = _defaultViewport;
  }

  @override
  void didUpdateWidget(TelemetryChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.series != widget.series) {
      _defaultViewport = _computeDefaultViewport();
      if (!_viewportModified) {
        _viewport = _defaultViewport;
      }
    }
  }

  ChartViewport _computeDefaultViewport() {
    if (widget.series.isEmpty || widget.series.every((s) => s.points.isEmpty)) {
      return const ChartViewport(xMin: 0, xMax: 1, yMin: -1, yMax: 1);
    }

    double xMin = double.infinity, xMax = double.negativeInfinity;
    double yMin = double.infinity, yMax = double.negativeInfinity;

    for (final s in widget.series) {
      for (final p in s.points) {
        if (p.dx < xMin) xMin = p.dx;
        if (p.dx > xMax) xMax = p.dx;
        if (p.dy < yMin) yMin = p.dy;
        if (p.dy > yMax) yMax = p.dy;
      }
    }

    // Add a 5 % margin on every side so edge data isn't clipped.
    final xMargin = (xMax - xMin) * 0.05;
    final yMargin = math.max((yMax - yMin) * 0.05, 0.01);
    return ChartViewport(
      xMin: xMin - xMargin,
      xMax: xMax + xMargin,
      yMin: yMin - yMargin,
      yMax: yMax + yMargin,
    );
  }

  // ── Gesture handlers ───────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails details) {
    _gestureBaseViewport = _viewport;
    _gestureFocalStart = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final base = _gestureBaseViewport;
    final focal = _gestureFocalStart;
    if (base == null || focal == null) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    if (size.isEmpty) return;

    final delta = details.localFocalPoint - focal;

    if (details.pointerCount < 2) {
      // Single-finger pan: translate viewport by the cumulative drag delta.
      final dx = -delta.dx / size.width * base.xRange;
      final dy = delta.dy / size.height * base.yRange;
      setState(() {
        _viewport = ChartViewport(
          xMin: base.xMin + dx,
          xMax: base.xMax + dx,
          yMin: base.yMin + dy,
          yMax: base.yMax + dy,
        );
        _viewportModified = true;
      });
    } else {
      // Multi-finger pinch-to-zoom: scale viewport around the focal point.
      final scale = details.scale.clamp(0.1, 50.0);

      // Focal point expressed in data space (using the base viewport).
      final focalX = base.xMin + (focal.dx / size.width) * base.xRange;
      final focalY = base.yMax - (focal.dy / size.height) * base.yRange;

      final newXRange = base.xRange / scale;
      final newYRange = base.yRange / scale;

      final fracX = focal.dx / size.width;
      final fracY = focal.dy / size.height;

      setState(() {
        _viewport = ChartViewport(
          xMin: focalX - fracX * newXRange,
          xMax: focalX + (1.0 - fracX) * newXRange,
          yMin: focalY - (1.0 - fracY) * newYRange,
          yMax: focalY + fracY * newYRange,
        );
        _viewportModified = true;
      });
    }
  }

  void _onTapDown(TapDownDetails details) {
    setState(() {
      _crosshair = details.localPosition;
    });
  }

  void _resetZoom() {
    setState(() {
      _viewport = _defaultViewport;
      _viewportModified = false;
      _crosshair = null;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context); // required for AutomaticKeepAliveClientMixin
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(colorScheme),
        Expanded(child: _buildCanvas(colorScheme, textTheme)),
        _buildLegend(textTheme),
      ],
    );
  }

  Widget _buildToolbar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_viewportModified)
            TextButton.icon(
              key: TelemetryChart.resetZoomKey,
              onPressed: _resetZoom,
              icon: const Icon(Icons.zoom_out_map, size: 18),
              label: const Text('Reset View'),
            ),
          IconButton(
            key: TelemetryChart.exportButtonKey,
            tooltip: 'Export as CSV',
            onPressed: widget.onExport,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(ColorScheme colorScheme, TextTheme textTheme) {
    final decimated = [
      for (final s in widget.series)
        TelemetrySeries(
          label: s.label,
          color: s.color,
          points: _decimate(s.points, widget.maxRenderedPoints),
          plotType: s.plotType,
        ),
    ];

    return GestureDetector(
      key: TelemetryChart.chartCanvasKey,
      behavior: HitTestBehavior.opaque,
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onTapDown: _onTapDown,
      child: CustomPaint(
        painter: _ChartPainter(
          series: decimated,
          viewport: _viewport,
          xLabel: widget.xLabel,
          yLabel: widget.yLabel,
          crosshair: _crosshair,
          gridColor: colorScheme.outlineVariant,
          axisColor: colorScheme.outline,
          textStyle: textTheme.bodySmall!.copyWith(
            fontSize: 10,
            color: colorScheme.onSurface,
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildLegend(TextTheme textTheme) {
    if (widget.series.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          for (final s in widget.series) _LegendItem(series: s),
        ],
      ),
    );
  }
}

// ── Decimation ────────────────────────────────────────────────────────────────

/// Reduces [points] to at most [maxPoints] while preserving signal shape by
/// keeping the min and max y-value within each equal-width bucket.
List<Offset> _decimate(List<Offset> points, int maxPoints) {
  if (points.length <= maxPoints) return points;

  final result = <Offset>[];
  final bucketSize = points.length / maxPoints;

  for (int i = 0; i < maxPoints; i++) {
    final start = (i * bucketSize).round();
    final end = math.min(((i + 1) * bucketSize).round(), points.length);
    if (start >= end) continue;

    double minY = double.infinity, maxY = double.negativeInfinity;
    Offset? minPt, maxPt;

    for (int j = start; j < end; j++) {
      final p = points[j];
      if (p.dy < minY) {
        minY = p.dy;
        minPt = p;
      }
      if (p.dy > maxY) {
        maxY = p.dy;
        maxPt = p;
      }
    }

    if (minPt != null && maxPt != null) {
      // Emit min before max or max before min depending on x-order so the
      // resulting polyline stays monotonically ordered in x.
      if (minPt.dx <= maxPt.dx) {
        result.add(minPt);
        if (minPt != maxPt) result.add(maxPt);
      } else {
        result.add(maxPt);
        if (minPt != maxPt) result.add(minPt);
      }
    }
  }

  return result;
}

// ── CustomPainter ─────────────────────────────────────────────────────────────

class _ChartPainter extends CustomPainter {
  const _ChartPainter({
    required this.series,
    required this.viewport,
    required this.xLabel,
    required this.yLabel,
    required this.gridColor,
    required this.axisColor,
    required this.textStyle,
    this.crosshair,
  });

  final List<TelemetrySeries> series;
  final ChartViewport viewport;
  final String xLabel;
  final String yLabel;
  final Color gridColor;
  final Color axisColor;
  final TextStyle textStyle;
  final Offset? crosshair;

  // Fixed margins (logical pixels) for axis labels.
  static const double _left = 52;
  static const double _bottom = 40;
  static const double _top = 8;
  static const double _right = 8;

  @override
  void paint(Canvas canvas, Size size) {
    if (viewport.isDegenerate) return;

    final plotRect = Rect.fromLTRB(
      _left,
      _top,
      size.width - _right,
      size.height - _bottom,
    );
    if (plotRect.width <= 0 || plotRect.height <= 0) return;

    _drawGrid(canvas, plotRect);
    _drawAxes(canvas, plotRect);
    _drawAxisLabels(canvas, size, plotRect);

    canvas.save();
    canvas.clipRect(plotRect);
    _drawSeries(canvas, plotRect);
    if (crosshair != null) _drawCrosshair(canvas, plotRect, crosshair!);
    canvas.restore();
  }

  // ── Coordinate mapping ─────────────────────────────────────────────────────

  double _toCanvasX(double x, Rect r) =>
      r.left + (x - viewport.xMin) / viewport.xRange * r.width;

  double _toCanvasY(double y, Rect r) =>
      r.bottom - (y - viewport.yMin) / viewport.yRange * r.height;

  Offset _toCanvas(Offset data, Rect r) =>
      Offset(_toCanvasX(data.dx, r), _toCanvasY(data.dy, r));

  // ── Drawing helpers ────────────────────────────────────────────────────────

  void _drawGrid(Canvas canvas, Rect plotRect) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    const n = 5;
    for (int i = 0; i <= n; i++) {
      final frac = i / n;
      final y = plotRect.top + frac * plotRect.height;
      canvas.drawLine(
          Offset(plotRect.left, y), Offset(plotRect.right, y), paint);
      final x = plotRect.left + frac * plotRect.width;
      canvas.drawLine(
          Offset(x, plotRect.top), Offset(x, plotRect.bottom), paint);
    }
  }

  void _drawAxes(Canvas canvas, Rect plotRect) {
    final paint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.5;
    canvas.drawLine(plotRect.bottomLeft, plotRect.bottomRight, paint);
    canvas.drawLine(plotRect.bottomLeft, plotRect.topLeft, paint);
  }

  void _drawAxisLabels(Canvas canvas, Size size, Rect plotRect) {
    const n = 5;
    for (int i = 0; i <= n; i++) {
      final frac = i / n;
      // X-axis tick labels.
      final xValue = viewport.xMin + frac * viewport.xRange;
      _drawText(
        canvas,
        _fmt(xValue),
        Offset(plotRect.left + frac * plotRect.width, plotRect.bottom + 5),
        TextAlign.center,
      );
      // Y-axis tick labels.
      final yValue = viewport.yMin + frac * viewport.yRange;
      _drawText(
        canvas,
        _fmt(yValue),
        Offset(plotRect.left - 4, plotRect.bottom - frac * plotRect.height),
        TextAlign.right,
      );
    }
    // Axis title labels.
    _drawText(
      canvas,
      xLabel,
      Offset(plotRect.center.dx, size.height - 3),
      TextAlign.center,
    );
  }

  void _drawSeries(Canvas canvas, Rect plotRect) {
    for (final s in series) {
      if (s.points.isEmpty) continue;
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      if (s.plotType == PlotType.scatter) {
        paint.style = PaintingStyle.fill;
        for (final pt in s.points) {
          canvas.drawCircle(_toCanvas(pt, plotRect), 2.5, paint);
        }
      } else {
        paint.style = PaintingStyle.stroke;
        final path = Path();
        bool first = true;
        for (final pt in s.points) {
          final cp = _toCanvas(pt, plotRect);
          if (first) {
            path.moveTo(cp.dx, cp.dy);
            first = false;
          } else {
            path.lineTo(cp.dx, cp.dy);
          }
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  void _drawCrosshair(Canvas canvas, Rect plotRect, Offset canvasPos) {
    if (!plotRect.contains(canvasPos)) return;
    final paint = Paint()
      ..color = axisColor.withAlpha(179)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(canvasPos.dx, plotRect.top),
        Offset(canvasPos.dx, plotRect.bottom), paint);
    canvas.drawLine(Offset(plotRect.left, canvasPos.dy),
        Offset(plotRect.right, canvasPos.dy), paint);

    // Annotation with data-space coordinates.
    final xData = viewport.xMin +
        (canvasPos.dx - plotRect.left) / plotRect.width * viewport.xRange;
    final yData = viewport.yMin +
        (plotRect.bottom - canvasPos.dy) / plotRect.height * viewport.yRange;
    _drawText(
      canvas,
      '(${_fmt(xData)}, ${_fmt(yData)})',
      Offset(canvasPos.dx + 4, canvasPos.dy - 14),
      TextAlign.left,
    );
  }

  void _drawText(Canvas canvas, String text, Offset position, TextAlign align) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();

    double dx = position.dx;
    if (align == TextAlign.right) {
      dx -= tp.width;
    } else if (align == TextAlign.center) {
      dx -= tp.width / 2;
    }
    tp.paint(canvas, Offset(dx, position.dy - tp.height / 2));
  }

  String _fmt(double v) {
    if (v.abs() >= 10000 || (v.abs() < 0.01 && v != 0)) {
      return v.toStringAsExponential(1);
    }
    return v.toStringAsFixed(v.abs() >= 100 ? 0 : 1);
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      series != old.series ||
      viewport != old.viewport ||
      crosshair != old.crosshair;
}

// ── Legend item ───────────────────────────────────────────────────────────────

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.series});

  final TelemetrySeries series;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 16, height: 2, color: series.color),
        const SizedBox(width: 4),
        Text(
          series.label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
