/// Converts damper adjuster click positions to damping coefficients (FR-SM-007).
///
/// On typical motorcycle suspension adjusters, increasing the click count
/// (turning the adjuster outward/counter-clockwise from fully closed) adds
/// resistance, increasing the effective damping coefficient:
/// - **0 clicks** = softest setting (minimum coefficient = [baseCoefficient]).
/// - **[clicksRange] clicks** = hardest setting (maximum coefficient =
///   [baseCoefficient] × 3).
///
/// Usage:
/// ```dart
/// // 10 clicks on a 20-click adjuster with 10.0 N·s/mm base coefficient
/// final c = ClickMapper.clicksToCoefficient(10, 10.0);
/// print(c); // 20.0 N·s/mm  (factor = 1 + (10/20)×2 = 2.0)
/// ```
class ClickMapper {
  const ClickMapper._();

  /// Converts a clicker position to a damping coefficient.
  ///
  /// [clicks] is the adjuster position (0 = softest, [clicksRange] = hardest).
  /// [baseCoefficient] is the minimum damping coefficient at 0 clicks, in any
  /// consistent unit (e.g., N·s/mm).
  /// [clicksRange] is the total number of available clicks (default 20).
  ///
  /// The returned coefficient scales linearly from [baseCoefficient] (at
  /// 0 clicks) to 3 × [baseCoefficient] (at [clicksRange] clicks).
  ///
  /// Throws [ArgumentError] if:
  /// - [clicks] < 0 or [clicks] > [clicksRange], or
  /// - [clicksRange] ≤ 0, or
  /// - [baseCoefficient] ≤ 0.
  static double clicksToCoefficient(
    int clicks,
    double baseCoefficient, {
    int clicksRange = 20,
  }) {
    if (clicksRange <= 0) {
      throw ArgumentError.value(
        clicksRange,
        'clicksRange',
        'Click range must be positive.',
      );
    }
    if (baseCoefficient <= 0) {
      throw ArgumentError.value(
        baseCoefficient,
        'baseCoefficient',
        'Base coefficient must be positive.',
      );
    }
    if (clicks < 0) {
      throw ArgumentError.value(
        clicks,
        'clicks',
        'Click position must be non-negative.',
      );
    }
    if (clicks > clicksRange) {
      throw ArgumentError.value(
        clicks,
        'clicks',
        'Click position must not exceed clicksRange ($clicksRange).',
      );
    }

    final factor = 1.0 + (clicks / clicksRange) * 2.0; // 1× to 3×
    return baseCoefficient * factor;
  }
}
