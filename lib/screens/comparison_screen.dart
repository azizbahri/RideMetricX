import 'package:flutter/material.dart';

import '../models/suspension_parameters.dart';
import '../models/tuning_snapshot.dart';
import '../repositories/snapshot_repository.dart';

// ── App-scoped default repository ─────────────────────────────────────────────

/// App-scoped default repository shared across the application.
final _sharedRepository = SnapshotRepository();

// ── ComparisonScreen ──────────────────────────────────────────────────────────

/// Side-by-side comparison and multi-snapshot analysis screen (FR-UI-007).
///
/// Displays a scrollable table that places each captured [TuningSnapshot] in
/// its own column.  The first snapshot (oldest) is treated as the baseline;
/// all subsequent snapshots show delta values (Δ) relative to the baseline,
/// colour-coded green (lower value) / red (higher value) or neutral (no
/// change).
///
/// An optional [repository] may be supplied for testing; when omitted the
/// app-wide [_sharedRepository] is used.
class ComparisonScreen extends StatelessWidget {
  const ComparisonScreen({super.key, this.repository});

  final SnapshotRepository? repository;

  SnapshotRepository get _repo => repository ?? _sharedRepository;

  // ── Semantic keys for tests ──────────────────────────────────────────────
  static const Key captureButtonKey = Key('comparison_capture_button');
  static const Key clearButtonKey = Key('comparison_clear_button');
  static const Key snapshotTableKey = Key('comparison_snapshot_table');

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final snapshots = _repo.snapshots;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Toolbar(
              snapshotCount: snapshots.length,
              onCapture: () => _captureSnapshot(context),
              onClear: snapshots.isNotEmpty ? () => _confirmClear(context) : null,
            ),
            if (snapshots.isEmpty)
              const Expanded(child: _EmptyState())
            else
              Expanded(
                child: _ComparisonTable(
                  key: snapshotTableKey,
                  snapshots: snapshots.toList(),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Captures a snapshot from the default tuning parameters and adds it to
  /// the repository.  In production the current tuning state would be sourced
  /// from a shared data store; here demo parameters are used so the feature
  /// is immediately explorable.
  void _captureSnapshot(BuildContext context) {
    final repo = _repo;
    final count = repo.length + 1;
    final preset = _demoPresetForCount(count);
    final snapshot = TuningSnapshot(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: 'Snapshot $count',
      createdAt: DateTime.now().toUtc(),
      parameters: preset,
    );
    repo.add(snapshot);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${snapshot.label}" captured'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all snapshots?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _repo.clear();
    }
  }
}

// ── _Toolbar ──────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.snapshotCount,
    required this.onCapture,
    this.onClear,
  });

  final int snapshotCount;
  final VoidCallback onCapture;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Text(
              snapshotCount == 0
                  ? 'No snapshots'
                  : '$snapshotCount snapshot${snapshotCount == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
            if (onClear != null)
              IconButton(
                key: ComparisonScreen.clearButtonKey,
                icon: Icon(Icons.delete_outline, color: colorScheme.error),
                tooltip: 'Clear all snapshots',
                onPressed: onClear,
              ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: ComparisonScreen.captureButtonKey,
              onPressed: onCapture,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Capture'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _EmptyState ───────────────────────────────────────────────────────────────

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
          Icon(Icons.compare_arrows, size: 64, color: colorScheme.outline),
          const SizedBox(height: 16),
          Text('No snapshots yet', style: textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Tap Capture to save the current tuning setup',
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

// ── _ComparisonTable ──────────────────────────────────────────────────────────

/// Scrollable data table listing all snapshots side-by-side.
///
/// Rows correspond to individual tuning metrics; columns correspond to
/// snapshots.  The first snapshot column is the baseline; subsequent columns
/// show delta (Δ) values relative to it, colour-coded for quick scanning.
class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({super.key, required this.snapshots});

  final List<TuningSnapshot> snapshots;

  static const _metrics = <_MetricDef>[
    _MetricDef(
      label: 'Front Spring Rate',
      unit: 'N/mm',
      getValue: _frontSpringRate,
    ),
    _MetricDef(
      label: 'Front Compression',
      unit: 'clicks',
      getValue: _frontCompression,
    ),
    _MetricDef(
      label: 'Front Rebound',
      unit: 'clicks',
      getValue: _frontRebound,
    ),
    _MetricDef(label: 'Front Preload', unit: 'mm', getValue: _frontPreload),
    _MetricDef(
      label: 'Rear Spring Rate',
      unit: 'N/mm',
      getValue: _rearSpringRate,
    ),
    _MetricDef(
      label: 'Rear Compression',
      unit: 'clicks',
      getValue: _rearCompression,
    ),
    _MetricDef(
      label: 'Rear Rebound',
      unit: 'clicks',
      getValue: _rearRebound,
    ),
    _MetricDef(label: 'Rear Preload', unit: 'mm', getValue: _rearPreload),
  ];

  // Static getters used by [_MetricDef] to avoid closures in const lists.
  static double _frontSpringRate(TuningSnapshot s) => s.frontSpringRate;
  static double _frontCompression(TuningSnapshot s) => s.frontCompression;
  static double _frontRebound(TuningSnapshot s) => s.frontRebound;
  static double _frontPreload(TuningSnapshot s) => s.frontPreload;
  static double _rearSpringRate(TuningSnapshot s) => s.rearSpringRate;
  static double _rearCompression(TuningSnapshot s) => s.rearCompression;
  static double _rearRebound(TuningSnapshot s) => s.rearRebound;
  static double _rearPreload(TuningSnapshot s) => s.rearPreload;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Build column widths: metric label + one column per snapshot.
    const double labelColWidth = 160;
    const double dataColWidth = 120;

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: _buildTable(
            context,
            colorScheme,
            textTheme,
            labelColWidth,
            dataColWidth,
          ),
        ),
      ),
    );
  }

  Widget _buildTable(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
    double labelColWidth,
    double dataColWidth,
  ) {
    final baseline = snapshots.first;

    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {
        0: FixedColumnWidth(labelColWidth),
        for (int i = 0; i < snapshots.length; i++)
          i + 1: FixedColumnWidth(dataColWidth),
      },
      border: TableBorder(
        horizontalInside: BorderSide(
          color: colorScheme.outlineVariant,
          width: 0.5,
        ),
        verticalInside: BorderSide(
          color: colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      children: [
        // ── Header row ──────────────────────────────────────────────────────
        TableRow(
          decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest),
          children: [
            _headerCell('Metric', textTheme),
            for (int i = 0; i < snapshots.length; i++)
              _snapshotHeaderCell(
                snapshots[i],
                isBaseline: i == 0,
                textTheme: textTheme,
                colorScheme: colorScheme,
              ),
          ],
        ),
        // ── Data rows ────────────────────────────────────────────────────────
        for (final metric in _metrics)
          TableRow(
            children: [
              _metricLabelCell(metric, textTheme),
              for (int i = 0; i < snapshots.length; i++)
                _dataCell(
                  metric: metric,
                  snapshot: snapshots[i],
                  baseline: baseline,
                  isBaseline: i == 0,
                  textTheme: textTheme,
                  colorScheme: colorScheme,
                ),
            ],
          ),
      ],
    );
  }

  Widget _headerCell(String text, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Text(text, style: textTheme.labelLarge),
    );
  }

  Widget _snapshotHeaderCell(
    TuningSnapshot snapshot, {
    required bool isBaseline,
    required TextTheme textTheme,
    required ColorScheme colorScheme,
  }) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  snapshot.label,
                  style: textTheme.labelLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isBaseline) ...[
                const SizedBox(width: 4),
                Chip(
                  label: const Text('baseline'),
                  padding: EdgeInsets.zero,
                  labelPadding:
                      const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: colorScheme.primaryContainer,
                  labelStyle: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ],
          ),
          Text(
            _formatDate(snapshot.createdAt),
            style:
                textTheme.bodySmall?.copyWith(color: colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _metricLabelCell(_MetricDef metric, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(metric.label, style: textTheme.bodyMedium),
          Text(metric.unit, style: textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _dataCell({
    required _MetricDef metric,
    required TuningSnapshot snapshot,
    required TuningSnapshot baseline,
    required bool isBaseline,
    required TextTheme textTheme,
    required ColorScheme colorScheme,
  }) {
    final value = metric.getValue(snapshot);
    final baseValue = metric.getValue(baseline);
    final delta = value - baseValue;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value.toStringAsFixed(1),
            style: textTheme.bodyMedium?.copyWith(fontFeatures: const []),
          ),
          if (!isBaseline)
            _DeltaChip(delta: delta, colorScheme: colorScheme, textTheme: textTheme),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${_pad(local.month)}-${_pad(local.day)} '
        '${_pad(local.hour)}:${_pad(local.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

// ── _DeltaChip ────────────────────────────────────────────────────────────────

/// Compact inline chip showing the numeric delta relative to the baseline.
///
/// Positive deltas are coloured using [ColorScheme.error] (higher than
/// baseline); negative deltas use [ColorScheme.tertiary] (lower than
/// baseline); zero delta shows a neutral colour.
class _DeltaChip extends StatelessWidget {
  const _DeltaChip({
    required this.delta,
    required this.colorScheme,
    required this.textTheme,
  });

  final double delta;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final isZero = delta.abs() < 0.001;
    final isPositive = delta > 0;

    final Color bg;
    final Color fg;
    final String prefix;

    if (isZero) {
      bg = colorScheme.surfaceContainerHighest;
      fg = colorScheme.onSurfaceVariant;
      prefix = '';
    } else if (isPositive) {
      bg = colorScheme.errorContainer;
      fg = colorScheme.onErrorContainer;
      prefix = '+';
    } else {
      bg = colorScheme.tertiaryContainer;
      fg = colorScheme.onTertiaryContainer;
      prefix = '';
    }

    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$prefix${delta.toStringAsFixed(1)}',
        style: textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }
}

// ── _MetricDef ────────────────────────────────────────────────────────────────

/// Descriptor for a single row in the comparison table.
class _MetricDef {
  const _MetricDef({
    required this.label,
    required this.unit,
    required this.getValue,
  });

  final String label;
  final String unit;
  final double Function(TuningSnapshot) getValue;
}

// ── Demo preset cycling ───────────────────────────────────────────────────────

/// Returns a demo [TuningParameters] preset cycling through soft → default →
/// firm to produce interesting delta values when the user captures multiple
/// snapshots without a real session loaded.
TuningParameters _demoPresetForCount(int count) => switch (count % 3) {
      1 => TuningParameters.defaultPreset,
      2 => TuningParameters.softPreset,
      _ => TuningParameters.firmPreset,
    };
