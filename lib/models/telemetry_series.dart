import 'dart:ui';

/// Plot rendering style for a [TelemetrySeries].
enum PlotType {
  /// Connect data points with straight line segments.
  line,

  /// Draw an individual marker at each data point.
  scatter,
}

/// A single named data series for telemetry plotting.
///
/// [points] contains (x, y) coordinates where x is typically elapsed time in
/// milliseconds and y is the channel value (e.g. m/s², deg/s).
class TelemetrySeries {
  /// Human-readable name shown in the chart legend.
  final String label;

  /// Stroke colour used to draw this series.
  final Color color;

  /// Ordered list of data points. Each [Offset] has dx = x-axis value and
  /// dy = y-axis value.
  final List<Offset> points;

  /// How this series should be rendered.
  final PlotType plotType;

  const TelemetrySeries({
    required this.label,
    required this.color,
    required this.points,
    this.plotType = PlotType.line,
  });
}
