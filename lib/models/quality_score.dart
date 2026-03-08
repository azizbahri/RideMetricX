import 'sync_result.dart';
import 'validation_report.dart';

// ── Scoring constants ─────────────────────────────────────────────────────────

/// Number of independently scored sensor channels per [ImuSample].
///
/// Used to normalise [ValidationMetrics.nanCount] into a per-channel fraction.
const int _sensorChannelCount = 7;

/// Correlation threshold below which a sync penalty is applied.
const double _minGoodCorrelation = 0.5;

/// Scale factor for the poor-correlation penalty
/// (max penalty = [_maxCorrPenalty] points when corr == 0).
const double _poorCorrPenaltyScale = 20.0;

/// Maximum sync correlation penalty in score points.
const int _maxCorrPenalty = 10;

/// Correlation threshold above which a sync bonus is applied.
const double _excellentCorrThreshold = 0.9;

/// Scale factor for the excellent-correlation bonus.
const double _excellentCorrBonusScale = 50.0;

/// Maximum sync correlation bonus in score points.
const int _maxCorrBonus = 5;

/// Maximum NaN penalty in score points.
const int _maxNanPenalty = 30;

/// Maximum gap penalty in score points.
const int _maxGapPenalty = 20;

/// Maximum outlier penalty in score points.
const int _maxOutlierPenalty = 20;

/// Score deduction per stuck sensor channel, capped at [_maxStuckPenalty].
const int _stuckChannelPenaltyPoints = 5;

/// Maximum total stuck-channel penalty in score points.
const int _maxStuckPenalty = 20;

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
    // < _minGoodCorrelation → deduct up to _maxCorrPenalty points;
    // ≥ _excellentCorrThreshold → add up to _maxCorrBonus bonus points.
    if (syncResult != null) {
      final corr = syncResult.correlationCoefficient;
      if (corr < _minGoodCorrelation) {
        score -= ((_minGoodCorrelation - corr) * _poorCorrPenaltyScale)
            .round()
            .clamp(0, _maxCorrPenalty);
      } else if (corr >= _excellentCorrThreshold) {
        score += ((corr - _excellentCorrThreshold) * _excellentCorrBonusScale)
            .round()
            .clamp(0, _maxCorrBonus);
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
    // _sensorChannelCount channels.  Penalty scales linearly from 0 to
    // _maxNanPenalty across the full 0–1 fraction.
    final nanFraction =
        (m.nanCount / (n * _sensorChannelCount.toDouble())).clamp(0.0, 1.0);
    score -= (nanFraction * _maxNanPenalty).round().clamp(0, _maxNanPenalty);

    // Gap penalty: scales linearly from 0 to _maxGapPenalty.
    final gapFraction = (m.gapCount / n).clamp(0.0, 1.0);
    score -= (gapFraction * _maxGapPenalty).round().clamp(0, _maxGapPenalty);

    // Outlier penalty: scales linearly from 0 to _maxOutlierPenalty.
    final outlierFraction = (m.outlierCount / n).clamp(0.0, 1.0);
    score -= (outlierFraction * _maxOutlierPenalty)
        .round()
        .clamp(0, _maxOutlierPenalty);

    // Stuck-field penalty: _stuckChannelPenaltyPoints per channel, max _maxStuckPenalty.
    score -= (m.stuckFieldCount * _stuckChannelPenaltyPoints)
        .clamp(0, _maxStuckPenalty);

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
