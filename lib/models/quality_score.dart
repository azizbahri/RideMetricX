import 'sync_result.dart';
import 'validation_report.dart';

/// Quality band classification for a [QualityScore].
enum QualityBand {
  /// Score 90–100: all signals clean, sync well-aligned.
  excellent,

  /// Score 70–89: minor issues such as a few gaps or outliers.
  good,

  /// Score 50–69: notable data quality issues; use with caution.
  fair,

  /// Score 0–49: significant data quality problems; results may be unreliable.
  poor,
}

/// A 0–100 score summarising the overall quality of an imported ride session.
///
/// Derived from [ValidationMetrics] (NaN count, gap count, outlier count,
/// stuck fields) and an optional synchronisation [SyncResult.correlationCoefficient].
///
/// ## Scoring bands
/// | Band                    | Range  |
/// |-------------------------|--------|
/// | [QualityBand.excellent] | 90–100 |
/// | [QualityBand.good]      | 70–89  |
/// | [QualityBand.fair]      | 50–69  |
/// | [QualityBand.poor]      | 0–49   |
class QualityScore {
  /// Integer quality score in the range [0, 100].
  final int score;

  const QualityScore(this.score)
      : assert(score >= 0),
        assert(score <= 100);

  /// Classify the score into a [QualityBand].
  QualityBand get band {
    if (score >= 90) return QualityBand.excellent;
    if (score >= 70) return QualityBand.good;
    if (score >= 50) return QualityBand.fair;
    return QualityBand.poor;
  }

  /// Computes a [QualityScore] from optional front/rear [ValidationReport]s
  /// and an optional [SyncResult].
  ///
  /// When both front and rear reports are available the per-stream scores are
  /// averaged before the sync adjustment is applied.  The synchronisation
  /// correlation coefficient can add up to 5 bonus points (for very good
  /// alignment) or deduct up to 10 points (for poor alignment).
  static QualityScore compute({
    ValidationReport? frontReport,
    ValidationReport? rearReport,
    SyncResult? syncResult,
  }) {
    final reports = [
      if (frontReport != null) frontReport,
      if (rearReport != null) rearReport,
    ];

    if (reports.isEmpty) return const QualityScore(0);

    // Average the per-report raw scores.
    int total = 0;
    for (final report in reports) {
      total += _scoreReport(report);
    }
    int score = total ~/ reports.length;

    // Sync quality adjustment: correlationCoefficient ∈ [-1, 1].
    // < 0.5 → deduct up to 10 points; ≥ 0.9 → add up to 5 bonus points.
    if (syncResult != null) {
      final corr = syncResult.correlationCoefficient;
      if (corr < 0.5) {
        score -= ((0.5 - corr) * 20).round().clamp(0, 10);
      } else if (corr >= 0.9) {
        score += ((corr - 0.9) * 50).round().clamp(0, 5);
      }
    }

    return QualityScore(score.clamp(0, 100));
  }

  /// Scores a single [ValidationReport] on a 0–100 scale.
  ///
  /// Penalty breakdown:
  /// - NaN values: up to 30 points (based on fraction of all channel values).
  /// - Timestamp gaps: up to 20 points (based on fraction of samples).
  /// - Statistical outliers: up to 20 points (based on fraction of samples).
  /// - Stuck signal channels: 5 points each, up to 20 points total.
  static int _scoreReport(ValidationReport report) {
    final m = report.metrics;
    if (m.sampleCount == 0) return 0;

    int score = 100;
    final n = m.sampleCount;

    // NaN penalty: nanCount counts individual channel NaNs; each sample has
    // 7 sensor channels.  Max penalty: 30 points.
    final nanFraction = (m.nanCount / (n * 7.0)).clamp(0.0, 1.0);
    score -= (nanFraction * 300).round().clamp(0, 30);

    // Gap penalty: up to 20 points.
    final gapFraction = (m.gapCount / n).clamp(0.0, 1.0);
    score -= (gapFraction * 100).round().clamp(0, 20);

    // Outlier penalty: up to 20 points.
    final outlierFraction = (m.outlierCount / n).clamp(0.0, 1.0);
    score -= (outlierFraction * 100).round().clamp(0, 20);

    // Stuck-field penalty: 5 points per stuck channel, max 20 points.
    score -= (m.stuckFieldCount * 5).clamp(0, 20);

    return score.clamp(0, 100);
  }

  /// Serialises the score to a [Map] for persistence.
  Map<String, dynamic> toMap() => {
        'score': score,
        'band': band.name,
      };

  @override
  String toString() => 'QualityScore(score=$score, band=${band.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is QualityScore && score == other.score;

  @override
  int get hashCode => score.hashCode;
}
