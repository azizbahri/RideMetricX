import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/telemetry_series.dart';
import '../services/simulation/debouncer.dart';

/// How long after the last gesture event before viewport-aware decimation
/// is recalculated.  Chosen to balance responsiveness with computation cost:
/// short enough to feel snappy after panning/zooming, long enough to avoid
/// running the decimation loop repeatedly during a fast gesture.
const Duration _kViewportDecimationDelay = Duration(milliseconds: 300);

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

// ── Downsampling ──────────────────────────────────────────────────────────────

/// Selects the downsampling algorithm applied before rendering.
///
/// Both algorithms operate on [List<Offset>] where [Offset.dx] is the x value
/// (e.g. elapsed time in ms) and [Offset.dy] is the y value.
enum DownsampleMethod {
  /// Min/max envelope bucketing.
  ///
  /// Divides the series into equal-width buckets and retains the point with
  /// the minimum *and* maximum y-value from each bucket.  Fast and suitable
  /// for detecting peaks, but may introduce slight visual jitter on smooth
  /// signals.
  minMax,

  /// Largest Triangle Three Buckets (LTTB).
  ///
  /// For each bucket, selects the single point whose retention would maximise
  /// the triangle area formed with the previously selected point and the
  /// average of the next bucket.  This maximises preserved visual information,
  /// producing a faithful representation of the original signal shape and
  /// making it the preferred method for telemetry replay (FR-VZ-006,
  /// NFR-VZ-001).
  lttb,
}

// ── TelemetryChart ────────────────────────────────────────────────────────────

/// A telemetry chart with zoom/pan/select interactions (FR-VZ-006).
///
/// Renders one or more [TelemetrySeries] over a shared x-axis. Zoom and pan
/// are handled via scale/drag gestures. Tapping the canvas places a crosshair
/// at the selected **data-space** position, so it stays anchored to the same
/// data point after any subsequent pan or zoom. An export button calls
/// [onExport] when set.
///
/// Large datasets are automatically downsampled to [maxRenderedPoints] per
/// series using the algorithm chosen by [downsampleMethod] (default:
/// [DownsampleMethod.lttb]) before every paint, keeping each frame below the
/// 16 ms budget required by NFR-VZ-001.
///
/// The chart state (viewport, crosshair) is kept alive across [TabBarView]
/// transitions via [AutomaticKeepAliveClientMixin].
///
/// ## Test targeting
/// Internal elements (canvas, export button, reset button) are given keys
/// derived from this widget's own [key]. If the chart is given
/// `key: ValueKey('chart_myTab')`, its canvas has key
/// `ValueKey('chart_myTab_canvas')`, its export button
/// `ValueKey('chart_myTab_export')`, and its reset button
/// `ValueKey('chart_myTab_reset')`.  Use `find.descendant` with the chart's
/// per-instance key to target these elements without ambiguity when multiple
/// [TelemetryChart] instances are alive simultaneously.
class TelemetryChart extends StatefulWidget {
  const TelemetryChart({
    super.key,
    required this.series,
    this.xLabel = 'Time (ms)',
    this.yLabel = 'Value',
    this.onExport,
    this.maxRenderedPoints = 2000,
    this.downsampleMethod = DownsampleMethod.lttb,
  });

  /// The data series to plot. May be empty (renders empty axes).
  final List<TelemetrySeries> series;

  /// Label shown below the x-axis.
  final String xLabel;

  /// Label shown to the left of the y-axis (rendered rotated).
  final String yLabel;

  /// Called when the user taps the export button. If `null` the button is
  /// disabled.
  final VoidCallback? onExport;

  /// Maximum number of points rendered per series after downsampling.
  /// Limits rendering cost for large datasets (NFR-VZ-001).
  final int maxRenderedPoints;

  /// Algorithm used to reduce each series to [maxRenderedPoints] before
  /// painting.  Defaults to [DownsampleMethod.lttb].
  final DownsampleMethod downsampleMethod;

  /// Reduces [points] to at most [maxPoints] while preserving signal shape by
  /// retaining the min/max envelope within each bucket.
  ///
  /// Returns an empty list when [maxPoints] ≤ 0.
  /// Exposed as a static method so unit tests can verify the decimation logic
  /// directly without pumping a widget.
  static List<Offset> decimate(List<Offset> points, int maxPoints) {
    return _decimate(points, maxPoints);
  }

  /// Viewport-aware variant of [decimate].
  ///
  /// Clips [points] to the x-range of [viewport] (plus a 10 % buffer on each
  /// side) and then decimates the visible subset.  When the user is zoomed
  /// into a small region of a large dataset, this gives significantly higher
  /// per-pixel resolution compared to decimating the entire dataset up-front.
  ///
  /// Like [decimate], each bucket contributes at most **2 points** (min and
  /// max y-value), so the returned list contains at most `2 × maxPoints`
  /// entries.
  ///
  /// Returns an empty list when [maxPoints] ≤ 0 or when no points fall in the
  /// (buffered) viewport window.
  static List<Offset> decimateForViewport(
    List<Offset> points,
    int maxPoints,
    ChartViewport viewport,
  ) {
    return _decimateViewport(points, maxPoints, viewport);
  }

  /// Reduces [points] to at most [maxPoints] using the **Largest Triangle
  /// Three Buckets** (LTTB) algorithm.
  ///
  /// LTTB selects, for each bucket, the single point that would create the
  /// largest triangle with its neighbours, thereby maximally preserving the
  /// perceived visual shape of the signal.  The first and last points are
  /// always retained.
  ///
  /// Returns an empty list when [maxPoints] ≤ 0.
  /// Exposed as a static method so unit tests can verify the algorithm
  /// directly without pumping a widget.
  static List<Offset> lttb(List<Offset> points, int maxPoints) {
    return _lttb(points, maxPoints);
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

  // Crosshair position in **data-space** coordinates, or null.
  // Storing data-space (not canvas-space) ensures the crosshair stays anchored
  // to the same data point after any pan or zoom.
  Offset? _crosshair;

  // Baseline captured at the start of each scale/pan gesture.
  ChartViewport? _gestureBaseViewport;
  Offset? _gestureFocalStart;

  // Canvas size captured by LayoutBuilder; used for pixel↔data conversions in
  // gesture handlers.  Avoids a RenderBox lookup on the wrong ancestor.
  Size _canvasSize = Size.zero;

  // Global decimation cache: avoid rebuilding the decimated list on every
  // render when the source series hasn't changed.
  List<TelemetrySeries>? _decimatedCache;
  List<TelemetrySeries>? _cachedOriginalSeries;
  int? _cachedMaxRenderedPoints;
  DownsampleMethod? _cachedDownsampleMethod;

  // Viewport-aware decimation cache: provides higher resolution within the
  // visible window when the user has zoomed into a small portion of the data.
  // Updated asynchronously (see [_kViewportDecimationDelay]) via the debouncer
  // so interactive panning/zooming stays smooth.
  List<TelemetrySeries>? _viewportDecimatedCache;
  ChartViewport? _cachedDecimationViewport;
  final Debouncer _viewportDecimationDebouncer =
      Debouncer(delay: _kViewportDecimationDelay);

  // Viewport-aware decimation cache: provides higher resolution within the
  // visible window when the user has zoomed into a small portion of the data.
  // Updated asynchronously (see [_kViewportDecimationDelay]) via the debouncer
  // so interactive panning/zooming stays smooth.
  List<TelemetrySeries>? _viewportDecimatedCache;
  ChartViewport? _cachedDecimationViewport;
  final Debouncer _viewportDecimationDebouncer =
      Debouncer(delay: _kViewportDecimationDelay);

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
      // Series changed: invalidate viewport-aware decimation cache so it is
      // rebuilt for the new data on the next debounce cycle.
      _viewportDecimatedCache = null;
      _cachedDecimationViewport = null;
    }
    if (oldWidget.maxRenderedPoints != widget.maxRenderedPoints) {
      // Point budget changed: the viewport-aware cache was built with the old
      // budget and is now stale.  Cancel any pending debounce and clear the
      // cache so the global decimation (which also auto-rebuilds) takes over
      // until the next debounce cycle populates a fresh viewport cache.
      _viewportDecimationDebouncer.cancel();
      _viewportDecimatedCache = null;
      _cachedDecimationViewport = null;
    }
    if (oldWidget.maxRenderedPoints != widget.maxRenderedPoints) {
      // Point budget changed: the viewport-aware cache was built with the old
      // budget and is now stale.  Cancel any pending debounce and clear the
      // cache so the global decimation (which also auto-rebuilds) takes over
      // until the next debounce cycle populates a fresh viewport cache.
      _viewportDecimationDebouncer.cancel();
      _viewportDecimatedCache = null;
      _cachedDecimationViewport = null;
    }
  }

  @override
  void dispose() {
    _viewportDecimationDebouncer.dispose();
    super.dispose();
  }

  @override
  void dispose() {
    _viewportDecimationDebouncer.dispose();
    super.dispose();
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

  // ── Downsampling cache ────────────────────────────────────────────────────

  /// Returns the decimated series list.
  ///
  /// Priority order:
  /// 1. Viewport-aware decimation cache (populated 300 ms after the last
  ///    gesture when the user is zoomed in) — highest resolution.
  /// 2. Global decimation cache (entire dataset reduced to
  ///    [TelemetryChart.maxRenderedPoints]) — fast fallback during gestures
  ///    and at the initial full-range view.
  List<TelemetrySeries> _getDecimated() {
    // Use the viewport-aware cache if it is ready.
    if (_viewportDecimatedCache != null) return _viewportDecimatedCache!;

    // Global decimation — reuse cached result when nothing changed.
    if (identical(_cachedOriginalSeries, widget.series) &&
        _cachedMaxRenderedPoints == widget.maxRenderedPoints &&
        _cachedDownsampleMethod == widget.downsampleMethod) {
      return _decimatedCache!;
    }
    _cachedOriginalSeries = widget.series;
    _cachedMaxRenderedPoints = widget.maxRenderedPoints;
    _cachedDownsampleMethod = widget.downsampleMethod;

    final downsample = widget.downsampleMethod == DownsampleMethod.lttb
        ? _lttb
        : _decimate;

    _decimatedCache = [
      for (final s in widget.series)
        TelemetrySeries(
          label: s.label,
          color: s.color,
          points: downsample(s.points, widget.maxRenderedPoints),
          plotType: s.plotType,
        ),
    ];
    return _decimatedCache!;
  }

  /// Schedules a debounced viewport-aware re-decimation.
  ///
  /// Only activates when the user has zoomed in enough for the viewport-aware
  /// approach to meaningfully improve resolution (viewport covers less than
  /// 80 % of the full data range).  At full zoom the global decimation is
  /// perfectly adequate and cheaper to keep.
  void _scheduleViewportDecimation() {
    _viewportDecimationDebouncer.run(() {
      if (!mounted) return;
      final vp = _viewport;
      final defaultVp = _defaultViewport;

      // If close to full view, clear any previous viewport-specific cache
      // so the global decimation is used again.
      if (!_viewportModified ||
          defaultVp.isDegenerate ||
          vp.xRange >= defaultVp.xRange * 0.8) {
        if (_viewportDecimatedCache != null) {
          setState(() {
            _viewportDecimatedCache = null;
            _cachedDecimationViewport = null;
          });
        }
        return;
      }

      // Skip rebuilding if the viewport hasn't changed meaningfully since the
      // last high-resolution decimation (within 5 % of xRange).
      final cached = _cachedDecimationViewport;
      if (cached != null) {
        final tolerance = vp.xRange * 0.05;
        if ((vp.xMin - cached.xMin).abs() < tolerance &&
            (vp.xMax - cached.xMax).abs() < tolerance) {
          return;
        }
      }

      final clipped = [
        for (final s in widget.series)
          TelemetrySeries(
            label: s.label,
            color: s.color,
            points:
                _decimateViewport(s.points, widget.maxRenderedPoints, vp),
            plotType: s.plotType,
          ),
      ];

      setState(() {
        _viewportDecimatedCache = clipped;
        _cachedDecimationViewport = vp;
      });
    });
  }

  // ── Key derivation ─────────────────────────────────────────────────────────

  /// Derives an instance-specific [Key] for an internal sub-element.
  ///
  /// If this widget has a [ValueKey<String>] key (e.g.
  /// `ValueKey('chart_myTab')`), the returned key is
  /// `ValueKey('chart_myTab_$suffix')`.  When no string key is present,
  /// returns `null` (no key assigned to the internal element).
  Key? _deriveKey(String suffix) {
    final k = widget.key;
    if (k is ValueKey<String>) return ValueKey('${k.value}_$suffix');
    return null;
  }

  // ── Gesture handlers ───────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails details) {
    _gestureBaseViewport = _viewport;
    _gestureFocalStart = details.localFocalPoint;
    // Clear the viewport-aware cache so the global decimation is used while
    // the user is actively gesturing.  This prevents the chart from rendering
    // a stale clipped subset (e.g. from the previous zoom level) until the
    // next debounce cycle repopulates the cache for the new viewport.
    _viewportDecimationDebouncer.cancel();
    _viewportDecimatedCache = null;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final base = _gestureBaseViewport;
    final focal = _gestureFocalStart;
    if (base == null || focal == null) return;

    // Use the canvas size captured by LayoutBuilder — localFocalPoint is in
    // the GestureDetector's coordinate space, which matches _canvasSize.
    final size = _canvasSize;
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
      _scheduleViewportDecimation();
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
      _scheduleViewportDecimation();
    }
  }

  void _onTapDown(TapDownDetails details) {
    final size = _canvasSize;
    if (size.isEmpty) return;

    // Map the tap's canvas-space position to the plot area, then convert to
    // data-space.  plotRect margins mirror those defined in _ChartPainter.
    const plotLeft = _ChartPainter._left;
    const plotTop = _ChartPainter._top;
    final plotWidth = size.width - _ChartPainter._left - _ChartPainter._right;
    final plotHeight = size.height - _ChartPainter._top - _ChartPainter._bottom;

    final local = details.localPosition;

    // Ignore taps that land outside the plot area (axis-label margins).
    if (local.dx < plotLeft ||
        local.dx > plotLeft + plotWidth ||
        local.dy < plotTop ||
        local.dy > plotTop + plotHeight) return;

    final dataX =
        _viewport.xMin + (local.dx - plotLeft) / plotWidth * _viewport.xRange;
    final dataY =
        _viewport.yMax - (local.dy - plotTop) / plotHeight * _viewport.yRange;

    setState(() => _crosshair = Offset(dataX, dataY));
  }

  void _resetZoom() {
    _viewportDecimationDebouncer.cancel();
    setState(() {
      _viewport = _defaultViewport;
      _viewportModified = false;
      _viewportDecimatedCache = null;
      _cachedDecimationViewport = null;
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
              key: _deriveKey('reset'),
              onPressed: _resetZoom,
              icon: const Icon(Icons.zoom_out_map, size: 18),
              label: const Text('Reset View'),
            ),
          IconButton(
            key: _deriveKey('export'),
            tooltip: 'Export as CSV',
            onPressed: widget.onExport,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(ColorScheme colorScheme, TextTheme textTheme) {
    final decimated = _getDecimated();

    return LayoutBuilder(
      builder: (_, constraints) {
        _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          key: _deriveKey('canvas'),
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
      },
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
///
/// Returns an empty list when [maxPoints] ≤ 0.
List<Offset> _decimate(List<Offset> points, int maxPoints) {
  if (maxPoints <= 0) return const [];
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

/// Clips [points] to the x-range of [viewport] (plus a 10 % buffer on each
/// side), then decimates the visible subset.
///
/// When the user is zoomed into a small region of a large dataset, this gives
/// significantly higher per-pixel resolution compared to decimating the entire
/// dataset up-front.  The 10 % buffer ensures data immediately off-screen is
/// available so panning by a small amount doesn't cause visible gaps while
/// the debouncer fires.
///
/// Returns an empty list when [maxPoints] ≤ 0 or no points fall within the
/// (buffered) viewport window.
///
/// **Performance:** when [points] appear x-sorted (non-decreasing dx), binary
/// search is used to find the visible slice in O(log N) instead of O(N),
/// which is critical for 1M+ point datasets.  Sortedness is detected by
/// probing the first 1 024 entries; unsorted data falls back to a linear scan.
List<Offset> _decimateViewport(
  List<Offset> points,
  int maxPoints,
  ChartViewport viewport,
) {
  if (maxPoints <= 0) return const [];

  // Add a 10 % buffer around the viewport so data near the edges is included.
  final xBuffer = viewport.xRange * 0.1;
  final xMin = viewport.xMin - xBuffer;
  final xMax = viewport.xMax + xBuffer;

  if (points.isEmpty) return const [];

  // Probe up to the first 1 024 points to determine whether the data is
  // x-sorted.  This is O(1) for practical purposes even on very large lists.
  var probablySorted = true;
  final probeCount = math.min(points.length, 1024);
  for (var i = 1; i < probeCount; i++) {
    if (points[i - 1].dx > points[i].dx) {
      probablySorted = false;
      break;
    }
  }

  final List<Offset> visible;
  if (probablySorted) {
    // Binary search for the first index with dx >= xMin.
    int lowerBound(double target) {
      var lo = 0;
      var hi = points.length;
      while (lo < hi) {
        final mid = (lo + hi) ~/ 2;
        if (points[mid].dx < target) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      return lo;
    }

    // Binary search for the last index with dx <= xMax.
    int upperBound(double target) {
      var lo = 0;
      var hi = points.length;
      while (lo < hi) {
        final mid = (lo + hi) ~/ 2;
        if (points[mid].dx <= target) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      return lo; // exclusive end index
    }

    final start = lowerBound(xMin);
    final end = upperBound(xMax);

    if (start >= end) return const [];
    visible = points.sublist(start, end);
  } else {
    // Fallback for unsorted data: linear scan.
    visible = [
      for (final p in points)
        if (p.dx >= xMin && p.dx <= xMax) p,
    ];
  }

  if (visible.isEmpty) return const [];
  return _decimate(visible, maxPoints);
}

// ── LTTB ──────────────────────────────────────────────────────────────────────

/// Reduces [points] to at most [maxPoints] using the **Largest Triangle Three
/// Buckets** (LTTB) algorithm (Sveinn Steinarsson, 2013).
///
/// The algorithm:
///  1. Always retains the first and last data point.
///  2. Divides the interior points into `maxPoints − 2` equal-width buckets.
///  3. For each bucket selects the point that maximises the area of the
///     triangle formed by: the previously selected point, the candidate, and
///     the average of the *next* bucket (or the final point for the last
///     bucket).
///
/// This approach preserves perceived signal shape better than uniform
/// decimation or min/max bucketing, satisfying the visual-fidelity goal of
/// FR-VZ-006 and the ≤16 ms frame budget of NFR-VZ-001.
///
/// Returns an empty list when [maxPoints] ≤ 0.
List<Offset> _lttb(List<Offset> points, int maxPoints) {
  if (maxPoints <= 0) return const [];
  if (points.length <= maxPoints) return points;
  if (maxPoints == 1) return [points.first];
  if (maxPoints == 2) return [points.first, points.last];

  final result = [points.first];

  // Number of buckets for the interior points (first and last are fixed).
  final bucketCount = maxPoints - 2;
  final bucketSize = (points.length - 2) / bucketCount;

  int lastSelected = 0; // index of the most recently selected point

  for (int i = 0; i < bucketCount; i++) {
    // Current bucket: slice of interior indices [bucketStart, bucketEnd).
    final bucketStart = (i * bucketSize + 1).floor();
    final bucketEnd =
        math.min(((i + 1) * bucketSize + 1).floor(), points.length - 1);

    // Average of the *next* bucket (or the final point for the last bucket).
    double nextAvgX, nextAvgY;
    if (i == bucketCount - 1) {
      nextAvgX = points.last.dx;
      nextAvgY = points.last.dy;
    } else {
      final nextStart = bucketEnd;
      final nextEnd =
          math.min(((i + 2) * bucketSize + 1).floor(), points.length - 1);
      final count = nextEnd - nextStart;
      if (count <= 0) {
        nextAvgX = points.last.dx;
        nextAvgY = points.last.dy;
      } else {
        double sumX = 0, sumY = 0;
        for (int j = nextStart; j < nextEnd; j++) {
          sumX += points[j].dx;
          sumY += points[j].dy;
        }
        nextAvgX = sumX / count;
        nextAvgY = sumY / count;
      }
    }

    // Select the point in the current bucket with the maximum triangle area.
    final prev = points[lastSelected];
    double maxArea = -1;
    int maxIdx = bucketStart;

    for (int j = bucketStart; j < bucketEnd; j++) {
      final p = points[j];
      // Twice the signed triangle area; absolute value = triangle area × 2.
      final area = ((prev.dx - nextAvgX) * (p.dy - prev.dy) -
              (prev.dx - p.dx) * (nextAvgY - prev.dy))
          .abs();
      if (area > maxArea) {
        maxArea = area;
        maxIdx = j;
      }
    }

    result.add(points[maxIdx]);
    lastSelected = maxIdx;
  }

  result.add(points.last);
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

  /// Crosshair position in **data-space** coordinates, or null.
  final Offset? crosshair;

  // Fixed margins (logical pixels) for axis labels.
  static const double _left = 58;
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

    // X-axis title.
    _drawText(
      canvas,
      xLabel,
      Offset(plotRect.center.dx, size.height - 3),
      TextAlign.center,
    );

    // Y-axis title: rotated 90° CCW, centred on the plot height.
    canvas.save();
    canvas.translate(10, plotRect.center.dy);
    canvas.rotate(-math.pi / 2);
    _drawText(canvas, yLabel, Offset.zero, TextAlign.center);
    canvas.restore();
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

  /// Draws the crosshair.  [dataPos] is in **data-space** and is converted to
  /// canvas coordinates here so that it stays anchored to the same data point
  /// as the viewport changes.
  void _drawCrosshair(Canvas canvas, Rect plotRect, Offset dataPos) {
    final cx = _toCanvasX(dataPos.dx, plotRect);
    final cy = _toCanvasY(dataPos.dy, plotRect);

    // Only draw when the selected point is within the current viewport.
    if (cx < plotRect.left ||
        cx > plotRect.right ||
        cy < plotRect.top ||
        cy > plotRect.bottom) return;

    final paint = Paint()
      ..color = axisColor.withAlpha(179)
      ..strokeWidth = 1.0;
    canvas.drawLine(
        Offset(cx, plotRect.top), Offset(cx, plotRect.bottom), paint);
    canvas.drawLine(
        Offset(plotRect.left, cy), Offset(plotRect.right, cy), paint);

    // Annotation with data-space coordinates (already available directly).
    _drawText(
      canvas,
      '(${_fmt(dataPos.dx)}, ${_fmt(dataPos.dy)})',
      Offset(cx + 4, cy - 14),
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
  bool shouldRepaint(_ChartPainter old) {
    if (viewport != old.viewport || crosshair != old.crosshair) return true;
    if (identical(series, old.series)) return false;
    if (series.length != old.series.length) return true;
    for (int i = 0; i < series.length; i++) {
      if (series[i] != old.series[i]) return true;
    }
    return false;
  }
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
