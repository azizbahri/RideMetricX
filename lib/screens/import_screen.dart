import 'package:flutter/material.dart';

import '../models/imu_sample.dart';
import '../models/session_metadata.dart';
import '../models/validation_report.dart';
import '../services/data_import/import_service.dart';

/// Callback for picking a file; returns [FileSelection] on success,
/// or `null` when the user cancels.
typedef PickFileCallback = Future<FileSelection?> Function();

/// Callback invoked after a successful import with created session metadata.
typedef ImportCompletedCallback = void Function(List<SessionMetadata> sessions);

/// File import screen with front/rear sensor file selection,
/// import-progress tracking, cancellation support, and a validation summary.
///
/// Implements FR-UI-002 (import flow) and NFR-UI-002 (responsiveness).
///
/// [onPickFrontFile] and [onPickRearFile] are optional callbacks that provide
/// the file-picking mechanism; when omitted the corresponding "Select" button
/// is disabled.  Pass custom callbacks in tests to simulate file selection
/// without relying on platform-specific file-picker plugins.
///
/// [onNavigateToSessions] is an optional callback invoked when the user taps
/// the "Go to Sessions" button that appears after a successful import.
class ImportScreen extends StatefulWidget {
  const ImportScreen({
    super.key,
    this.onPickFrontFile,
    this.onPickRearFile,
    this.service,
    this.onNavigateToSessions,
    this.onImportCompleted,
  });

  /// Invoked when the user taps "Select" for the front sensor file.
  final PickFileCallback? onPickFrontFile;

  /// Invoked when the user taps "Select" for the rear sensor file.
  final PickFileCallback? onPickRearFile;

  /// Import service instance; defaults to [ImportService()] when omitted.
  /// Inject a custom instance in tests to control pipeline behaviour.
  final ImportService? service;

  /// Called when the user taps "Go to Sessions" after a successful import.
  /// When omitted the button is shown in a disabled state.
  final VoidCallback? onNavigateToSessions;

  /// Called when import finishes successfully with one or more imported
  /// session metadata entries.
  final ImportCompletedCallback? onImportCompleted;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  ImportService get _service => widget.service ?? const ImportService();

  // ── Per-position file selection ───────────────────────────────────────────

  FileSelection? _frontFile;
  FileSelection? _rearFile;

  // ── Import state ──────────────────────────────────────────────────────────

  bool _importing = false;
  double _progress = 0.0;
  bool _cancelled = false;
  String? _errorMessage;

  /// Incremented on every new import start and on cancel.
  ///
  /// Each [_runImport] call captures the generation at start time and skips
  /// state updates if the current generation has advanced, preventing stale
  /// stream events from a previous (or cancelled) import from corrupting a
  /// newly started import's state.
  int _generation = 0;

  // ── Results after a successful import ─────────────────────────────────────

  ImportSuccess? _frontResult;
  ImportSuccess? _rearResult;

  // ── Derived helpers ───────────────────────────────────────────────────────

  bool get _hasSelection => _frontFile != null || _rearFile != null;

  // ── File-selection actions ────────────────────────────────────────────────

  Future<void> _pickFront() async {
    final sel = await widget.onPickFrontFile?.call();
    if (sel != null && mounted) {
      setState(() {
        _frontFile = sel;
        _frontResult = null;
        _errorMessage = null;
      });
    }
  }

  Future<void> _pickRear() async {
    final sel = await widget.onPickRearFile?.call();
    if (sel != null && mounted) {
      setState(() {
        _rearFile = sel;
        _rearResult = null;
        _errorMessage = null;
      });
    }
  }

  void _clearFront() => setState(() {
        _frontFile = null;
        _frontResult = null;
        _errorMessage = null;
      });

  void _clearRear() => setState(() {
        _rearFile = null;
        _rearResult = null;
        _errorMessage = null;
      });

  // ── Import actions ────────────────────────────────────────────────────────

  Future<void> _startImport() async {
    if (!_hasSelection || _importing) return;
    final gen = ++_generation;
    setState(() {
      _importing = true;
      _progress = 0.0;
      _errorMessage = null;
      _frontResult = null;
      _rearResult = null;
      _cancelled = false;
    });
    try {
      if (_frontFile != null && !_cancelled) {
        await _runImport(_frontFile!, SensorPosition.front, gen);
      }
      if (_rearFile != null && !_cancelled && _errorMessage == null) {
        await _runImport(_rearFile!, SensorPosition.rear, gen);
      }

      // Persist imported metadata only when the run completed successfully.
      if (!_cancelled && _errorMessage == null) {
        final imported = _buildImportedSessions();
        if (imported.isNotEmpty) {
          widget.onImportCompleted?.call(imported);
        }
      }
    } finally {
      if (mounted && _generation == gen) setState(() => _importing = false);
    }
  }

  List<SessionMetadata> _buildImportedSessions() {
    final now = DateTime.now().toUtc();
    final baseId = now.toIso8601String();
    final hasFront = _frontResult != null;
    final hasRear = _rearResult != null;
    final both = hasFront && hasRear;

    String idFor(SensorPosition p) {
      if (!both) return baseId;
      return '$baseId-${p.name}';
    }

    String? pairFor(SensorPosition p) {
      if (!both) return null;
      final other = p == SensorPosition.front
          ? SensorPosition.rear
          : SensorPosition.front;
      return idFor(other);
    }

    final sessions = <SessionMetadata>[];
    if (_frontResult != null) {
      sessions.add(
        SessionMetadata(
          sessionId: idFor(SensorPosition.front),
          position: SensorPosition.front,
          recordedAt: now,
          samplingRateHz: _estimateSamplingRateHz(_frontResult!.samples),
          pairedSessionId: pairFor(SensorPosition.front),
        ),
      );
    }
    if (_rearResult != null) {
      sessions.add(
        SessionMetadata(
          sessionId: idFor(SensorPosition.rear),
          position: SensorPosition.rear,
          recordedAt: now,
          samplingRateHz: _estimateSamplingRateHz(_rearResult!.samples),
          pairedSessionId: pairFor(SensorPosition.rear),
        ),
      );
    }
    return sessions;
  }

  double _estimateSamplingRateHz(List<ImuSample> samples) {
    if (samples.length < 2) return 200.0;

    int totalDeltaMs = 0;
    int count = 0;
    for (int i = 1; i < samples.length; i++) {
      final prev = samples[i - 1];
      final curr = samples[i];
      final dt = curr.timestampMs - prev.timestampMs;
      if (dt > 0) {
        totalDeltaMs += dt;
        count++;
      }
    }

    if (count == 0) return 200.0;
    final avgDeltaMs = totalDeltaMs / count;
    final hz = 1000.0 / avgDeltaMs;
    return hz.isFinite && hz > 0 ? hz : 200.0;
  }

  Future<void> _runImport(
    FileSelection selection,
    SensorPosition position,
    int gen,
  ) async {
    await for (final state in _service.importFile(selection, position)) {
      if (_cancelled || !mounted || _generation != gen) break;
      if (state is ImportInProgress) {
        setState(() => _progress = state.progress);
      } else if (state is ImportSuccess) {
        setState(() {
          if (position == SensorPosition.front) {
            _frontResult = state;
          } else {
            _rearResult = state;
          }
        });
      } else if (state is ImportError) {
        setState(() => _errorMessage = state.message);
        break;
      }
    }
  }

  void _cancel() {
    _generation++; // Invalidate any running import stream.
    setState(() {
      _cancelled = true;
      _importing = false;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Import Data',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Select front and/or rear sensor files to import.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),

          // ── File selection cards ─────────────────────────────────────────
          _FileCard(
            label: 'Front Sensor',
            selection: _frontFile,
            enabled: !_importing,
            onPick: widget.onPickFrontFile != null ? _pickFront : null,
            onClear: _clearFront,
          ),
          const SizedBox(height: 12),
          _FileCard(
            label: 'Rear Sensor',
            selection: _rearFile,
            enabled: !_importing,
            onPick: widget.onPickRearFile != null ? _pickRear : null,
            onClear: _clearRear,
          ),

          const SizedBox(height: 24),

          // ── Action row ───────────────────────────────────────────────────
          Row(
            children: [
              FilledButton.icon(
                key: const Key('import_button'),
                onPressed: (_hasSelection && !_importing) ? _startImport : null,
                icon: const Icon(Icons.file_upload),
                label: const Text('Import'),
              ),
              if (_importing) ...[
                const SizedBox(width: 16),
                OutlinedButton(
                  key: const Key('cancel_button'),
                  onPressed: _cancel,
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),

          // ── Progress bar ─────────────────────────────────────────────────
          if (_importing) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text(
              '${(_progress * 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],

          // ── Error banner ─────────────────────────────────────────────────
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            _ErrorBanner(message: _errorMessage!),
          ],

          // ── Validation summaries ─────────────────────────────────────────
          if (_frontResult != null) ...[
            const SizedBox(height: 16),
            _ValidationSummaryCard(result: _frontResult!),
          ],
          if (_rearResult != null) ...[
            const SizedBox(height: 16),
            _ValidationSummaryCard(result: _rearResult!),
          ],

          // ── Post-import navigation ────────────────────────────────────────
          if (!_importing &&
              !_cancelled &&
              (_frontResult != null || _rearResult != null) &&
              _errorMessage == null) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('go_to_sessions_button'),
              onPressed: widget.onNavigateToSessions,
              icon: const Icon(Icons.history),
              label: const Text('Go to Sessions'),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Private sub-widgets ────────────────────────────────────────────────────────

/// Card showing the selected file for one sensor position.
class _FileCard extends StatelessWidget {
  const _FileCard({
    required this.label,
    required this.selection,
    required this.enabled,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final FileSelection? selection;
  final bool enabled;
  final VoidCallback? onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasFile = selection != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              hasFile ? Icons.insert_drive_file : Icons.upload_file_outlined,
              color: hasFile
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  if (hasFile)
                    Text(
                      selection!.fileName,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Text(
                      'No file selected',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                ],
              ),
            ),
            if (hasFile && enabled)
              IconButton(
                tooltip: 'Remove file',
                icon: const Icon(Icons.close),
                onPressed: onClear,
              )
            else if (!hasFile)
              TextButton(
                onPressed: enabled ? onPick : null,
                child: const Text('Select'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Red banner displayed when an import error occurs.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: cs.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: cs.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Validation summary card shown after a successful import.
class _ValidationSummaryCard extends StatelessWidget {
  const _ValidationSummaryCard({required this.result});

  final ImportSuccess result;

  @override
  Widget build(BuildContext context) {
    final report = result.report;
    final passed = report.passed;
    final posLabel = result.position == SensorPosition.front ? 'Front' : 'Rear';
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  passed ? Icons.check_circle : Icons.cancel,
                  color: passed ? cs.primary : cs.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$posLabel: ${result.fileName}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _MetricsRow(report: report),
            if (report.errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              _IssueList(
                label: 'Errors',
                items: report.errors.map((e) => e.message).toList(),
                color: cs.error,
              ),
            ],
            if (report.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              _IssueList(
                label: 'Warnings',
                items: report.warnings.map((w) => w.message).toList(),
                color: cs.secondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact row of metric chips.
class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.report});

  final ValidationReport report;

  @override
  Widget build(BuildContext context) {
    final m = report.metrics;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        _MetricChip(label: '${m.sampleCount} samples'),
        _MetricChip(label: '${m.durationMs} ms'),
        _MetricChip(
          label: '${m.effectiveSampleRateHz.toStringAsFixed(1)} Hz',
        ),
        if (m.gapCount > 0) _MetricChip(label: '${m.gapCount} gaps'),
        if (m.outlierCount > 0)
          _MetricChip(label: '${m.outlierCount} outliers'),
      ],
    );
  }
}

/// Single chip within [_MetricsRow].
class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label, style: Theme.of(context).textTheme.labelSmall),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

/// List of errors or warnings.
class _IssueList extends StatelessWidget {
  const _IssueList({
    required this.label,
    required this.items,
    required this.color,
  });

  final String label;
  final List<String> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style:
              Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
        ),
        ...items.map(
          (msg) => Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '• $msg',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }
}
