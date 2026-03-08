import 'dart:math' as math;

import '../models/analysis_metrics.dart';
import '../models/recommendation.dart';
import '../models/suspension_parameters.dart';

/// Generates and prioritises [Recommendation]s from [AnalysisMetrics].
///
/// Call [generate] after a simulation or analysis pass. The returned list is
/// sorted descending by severity (high → medium → low).
class RecommendationEngine {
  const RecommendationEngine();

  /// Generates recommendations from [metrics] relative to [current] parameters.
  ///
  /// Suggested parameters for each recommendation are computed by clamping
  /// adjusted click values to within [SuspensionParameters] bounds.
  List<Recommendation> generate(
    AnalysisMetrics metrics,
    TuningParameters current,
  ) {
    final results = <Recommendation>[];

    _checkBottoming(metrics, current, results);
    _checkTravelUnderutilisation(metrics, current, results);
    _checkHarshRide(metrics, current, results);
    _checkTooMuchRebound(metrics, current, results);
    _checkFrontRearImbalance(metrics, current, results);

    // Descending severity: high first.
    results.sort(
      (a, b) => b.severity.priorityScore.compareTo(a.severity.priorityScore),
    );

    return List.unmodifiable(results);
  }

  // ── Individual checks ──────────────────────────────────────────────────────

  void _checkBottoming(
    AnalysisMetrics m,
    TuningParameters current,
    List<Recommendation> out,
  ) {
    final total = m.totalBottomingEvents;
    if (total == 0) return;

    final severity = total > 10
        ? RecommendationSeverity.high
        : total >= 5
            ? RecommendationSeverity.medium
            : RecommendationSeverity.low;

    // Apply +4 compression clicks on the end that bottomed more.
    const delta = 4.0;
    final rearLeads = m.rearBottomingEvents >= m.frontBottomingEvents;
    final suggested = current.copyWith(
      front: rearLeads
          ? current.front
          : current.front.copyWith(
              compression: _clampClicks(current.front.compression + delta),
            ),
      rear: rearLeads
          ? current.rear.copyWith(
              compression: _clampClicks(current.rear.compression + delta),
            )
          : current.rear,
    );

    out.add(
      Recommendation(
        id: 'bottoming',
        type: RecommendationType.bottomingTooMuch,
        severity: severity,
        title: 'Bottoming detected $total time${total == 1 ? '' : 's'}',
        rationale:
            'The suspension hit its travel limit $total '
            'time${total == 1 ? '' : 's'}. Increasing compression damping '
            'by ~4 clicks will reduce bottoming while retaining suppleness '
            'over small bumps.',
        suggestedParameters: suggested,
      ),
    );
  }

  void _checkTravelUnderutilisation(
    AnalysisMetrics m,
    TuningParameters current,
    List<Recommendation> out,
  ) {
    final minUsage =
        math.min(m.frontTravelUsagePercent, m.rearTravelUsagePercent);
    if (minUsage >= 70.0) return;

    final underusedEnd =
        m.frontTravelUsagePercent < m.rearTravelUsagePercent ? 'front' : 'rear';
    final usagePct = minUsage.toStringAsFixed(0);

    // Suggest -2 compression clicks on both ends to free up travel.
    const delta = -2.0;
    final suggested = current.copyWith(
      front: current.front.copyWith(
        compression: _clampClicks(current.front.compression + delta),
      ),
      rear: current.rear.copyWith(
        compression: _clampClicks(current.rear.compression + delta),
      ),
    );

    out.add(
      Recommendation(
        id: 'travel_underutilised',
        type: RecommendationType.notUsingFullTravel,
        severity: RecommendationSeverity.medium,
        title: 'Travel underutilised ($usagePct% on $underusedEnd)',
        rationale:
            'Only $usagePct% of $underusedEnd travel is being used. '
            'Decreasing compression damping by ~2 clicks will let the '
            'suspension work through more of its available range, improving '
            'traction and comfort.',
        suggestedParameters: suggested,
      ),
    );
  }

  void _checkHarshRide(
    AnalysisMetrics m,
    TuningParameters current,
    List<Recommendation> out,
  ) {
    if (!m.harshRideDetected) return;

    const delta = -2.0;
    final suggested = current.copyWith(
      front: current.front.copyWith(
        compression: _clampClicks(current.front.compression + delta),
      ),
      rear: current.rear.copyWith(
        compression: _clampClicks(current.rear.compression + delta),
      ),
    );

    out.add(
      Recommendation(
        id: 'harsh_ride',
        type: RecommendationType.harshRide,
        severity: RecommendationSeverity.medium,
        title: 'Harsh ride quality detected',
        rationale:
            'High-frequency chassis acceleration suggests the suspension is '
            'too stiff for the terrain. Reducing compression damping by '
            '~2 clicks and verifying tire pressure is within the '
            'manufacturer specification should improve comfort.',
        suggestedParameters: suggested,
      ),
    );
  }

  void _checkTooMuchRebound(
    AnalysisMetrics m,
    TuningParameters current,
    List<Recommendation> out,
  ) {
    if (!m.tooMuchReboundDetected) return;

    const delta = 3.0;
    final suggested = current.copyWith(
      front: current.front.copyWith(
        rebound: _clampClicks(current.front.rebound + delta),
      ),
      rear: current.rear.copyWith(
        rebound: _clampClicks(current.rear.rebound + delta),
      ),
    );

    out.add(
      Recommendation(
        id: 'too_much_rebound',
        type: RecommendationType.tooMuchRebound,
        severity: RecommendationSeverity.medium,
        title: 'Excessive rebound oscillation detected',
        rationale:
            'The suspension is returning too quickly after compression, '
            'causing oscillations and slow settlement. Increasing rebound '
            'damping by ~3 clicks will slow the extension phase and '
            'improve stability.',
        suggestedParameters: suggested,
      ),
    );
  }

  void _checkFrontRearImbalance(
    AnalysisMetrics m,
    TuningParameters current,
    List<Recommendation> out,
  ) {
    final diff =
        (m.frontTravelUsagePercent - m.rearTravelUsagePercent).abs();
    if (diff < 20.0) return;

    final frontHeavy =
        m.frontTravelUsagePercent > m.rearTravelUsagePercent;
    final heavierEnd = frontHeavy ? 'front' : 'rear';
    final lighterEnd = frontHeavy ? 'rear' : 'front';

    // Reduce compression on the lighter end by 2 clicks to encourage more
    // travel usage.
    const delta = -2.0;
    final suggested = current.copyWith(
      front: frontHeavy
          ? current.front
          : current.front.copyWith(
              compression: _clampClicks(current.front.compression + delta),
            ),
      rear: frontHeavy
          ? current.rear.copyWith(
              compression: _clampClicks(current.rear.compression + delta),
            )
          : current.rear,
    );

    out.add(
      Recommendation(
        id: 'front_rear_imbalance',
        type: RecommendationType.imbalancedFrontRear,
        severity: RecommendationSeverity.medium,
        title:
            'Front/rear travel imbalanced '
            '(${m.frontTravelUsagePercent.toStringAsFixed(0)}% / '
            '${m.rearTravelUsagePercent.toStringAsFixed(0)}%)',
        rationale:
            'The $heavierEnd suspension is using significantly more travel '
            'than the $lighterEnd ($diff% difference). Reducing compression '
            'damping on the $lighterEnd by ~2 clicks will allow it to '
            'utilise more travel and balance the handling.',
        suggestedParameters: suggested,
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  double _clampClicks(double v) =>
      v.clamp(SuspensionParameters.kMinClicks, SuspensionParameters.kMaxClicks);
}
