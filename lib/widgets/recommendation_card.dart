import 'package:flutter/material.dart';

import '../models/recommendation.dart';
import '../models/suspension_parameters.dart';

// ── RecommendationCard ────────────────────────────────────────────────────────

/// Displays a single [Recommendation] with a severity badge, expandable
/// rationale, and an optional one-click apply button (FR-UI-007).
class RecommendationCard extends StatefulWidget {
  const RecommendationCard({
    super.key,
    required this.recommendation,
    this.onApply,
  });

  final Recommendation recommendation;

  /// Called when the user taps "Apply Suggestion".  Receives the
  /// [TuningParameters] encoded in [Recommendation.suggestedParameters].
  final void Function(TuningParameters)? onApply;

  // ── Semantic keys for tests ──────────────────────────────────────────────

  /// Key for the rationale text of the card identified by [id].
  static Key rationaleKey(String id) => Key('rec_rationale_$id');

  /// Key for the apply button of the card identified by [id].
  static Key applyKey(String id) => Key('rec_apply_$id');

  @override
  State<RecommendationCard> createState() => _RecommendationCardState();
}

class _RecommendationCardState extends State<RecommendationCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final rec = widget.recommendation;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, rec, colorScheme),
          if (_expanded) _buildDetails(context, rec),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    Recommendation rec,
    ColorScheme colorScheme,
  ) {
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _SeverityBadge(severity: rec.severity),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                rec.title,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              color: colorScheme.outline,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetails(BuildContext context, Recommendation rec) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 8),
          Text(
            rec.rationale,
            key: RecommendationCard.rationaleKey(rec.id),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          if (rec.suggestedParameters != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: RecommendationCard.applyKey(rec.id),
                onPressed: widget.onApply != null
                    ? () => widget.onApply!(rec.suggestedParameters!)
                    : null,
                icon: const Icon(Icons.tune, size: 16),
                label: const Text('Apply Suggestion'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── RecommendationsPanel ──────────────────────────────────────────────────────

/// Displays a prioritised list of [Recommendation] cards under a header
/// (FR-UI-007).
///
/// When [recommendations] is empty the panel shows a positive "No issues
/// found" message.  Pass [onApply] to wire up the one-click apply action.
class RecommendationsPanel extends StatelessWidget {
  const RecommendationsPanel({
    super.key,
    required this.recommendations,
    this.onApply,
  });

  /// Ordered list of recommendations (typically pre-sorted by severity).
  final List<Recommendation> recommendations;

  /// Forwarded to each [RecommendationCard.onApply].
  final void Function(TuningParameters)? onApply;

  // ── Semantic keys ──────────────────────────────────────────────────────────

  /// Key for the top-level panel column.
  static const Key panelKey = Key('recommendations_panel');

  /// Key for the "no issues" message shown when [recommendations] is empty.
  static const Key noIssuesKey = Key('recommendations_no_issues');

  @override
  Widget build(BuildContext context) {
    return Column(
      key: panelKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(context),
        if (recommendations.isEmpty)
          _buildNoIssues(context)
        else
          for (final rec in recommendations)
            RecommendationCard(
              key: ValueKey('rec_card_${rec.id}'),
              recommendation: rec,
              onApply: onApply,
            ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline, color: colorScheme.primary, size: 20),
          const SizedBox(width: 8),
          Text(
            'Recommendations',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 8),
          if (recommendations.isNotEmpty)
            Badge(
              label: Text('${recommendations.length}'),
              backgroundColor: colorScheme.primary,
            ),
        ],
      ),
    );
  }

  Widget _buildNoIssues(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            color: colorScheme.tertiary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              key: RecommendationsPanel.noIssuesKey,
              'No issues found – suspension settings look good!',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── _SeverityBadge ────────────────────────────────────────────────────────────

class _SeverityBadge extends StatelessWidget {
  const _SeverityBadge({required this.severity});

  final RecommendationSeverity severity;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, color, label) = switch (severity) {
      RecommendationSeverity.high => (
          Icons.warning_amber_rounded,
          colorScheme.error,
          'HIGH',
        ),
      RecommendationSeverity.medium => (
          Icons.info_outline,
          colorScheme.tertiary,
          'MED',
        ),
      RecommendationSeverity.low => (
          Icons.circle_outlined,
          colorScheme.outline,
          'LOW',
        ),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
