/// Metrics produced by a telemetry analysis pass.
///
/// These values drive [RecommendationEngine] to generate actionable
/// tuning suggestions.
class AnalysisMetrics {
  const AnalysisMetrics({
    this.frontBottomingEvents = 0,
    this.rearBottomingEvents = 0,
    this.frontTravelUsagePercent = 100.0,
    this.rearTravelUsagePercent = 100.0,
    this.harshRideDetected = false,
    this.tooMuchReboundDetected = false,
  });

  /// Number of times the front suspension bottomed out during the session.
  final int frontBottomingEvents;

  /// Number of times the rear suspension bottomed out during the session.
  final int rearBottomingEvents;

  /// Percentage of front suspension travel used (0–100).
  final double frontTravelUsagePercent;

  /// Percentage of rear suspension travel used (0–100).
  final double rearTravelUsagePercent;

  /// Whether high-frequency chassis acceleration was detected.
  final bool harshRideDetected;

  /// Whether oscillations indicating excessive rebound were detected.
  final bool tooMuchReboundDetected;

  /// Total bottoming events across both ends.
  int get totalBottomingEvents => frontBottomingEvents + rearBottomingEvents;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnalysisMetrics &&
          frontBottomingEvents == other.frontBottomingEvents &&
          rearBottomingEvents == other.rearBottomingEvents &&
          frontTravelUsagePercent == other.frontTravelUsagePercent &&
          rearTravelUsagePercent == other.rearTravelUsagePercent &&
          harshRideDetected == other.harshRideDetected &&
          tooMuchReboundDetected == other.tooMuchReboundDetected;

  @override
  int get hashCode => Object.hash(
        frontBottomingEvents,
        rearBottomingEvents,
        frontTravelUsagePercent,
        rearTravelUsagePercent,
        harshRideDetected,
        tooMuchReboundDetected,
      );

  @override
  String toString() =>
      'AnalysisMetrics('
      'frontBottoming: $frontBottomingEvents, '
      'rearBottoming: $rearBottomingEvents, '
      'frontTravel: ${frontTravelUsagePercent.toStringAsFixed(1)}%, '
      'rearTravel: ${rearTravelUsagePercent.toStringAsFixed(1)}%, '
      'harshRide: $harshRideDetected, '
      'tooMuchRebound: $tooMuchReboundDetected)';
}
