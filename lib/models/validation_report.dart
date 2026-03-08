import 'validation_error.dart';
import 'validation_metrics.dart';
import 'validation_warning.dart';

/// Structured output produced by [ValidationService] after validating an
/// imported telemetry stream.
class ValidationReport {
  /// Validation errors that caused the stream to fail.
  ///
  /// If [passed] is `true`, this list is empty.
  final List<ValidationError> errors;

  /// Warnings that describe suspicious but non-fatal conditions.
  final List<ValidationWarning> warnings;

  /// Aggregate quality metrics computed over the stream.
  final ValidationMetrics metrics;

  /// `true` if no errors were found during validation.
  bool get passed => errors.isEmpty;

  /// `true` if any auto-corrections were applied to the stream.
  final bool wasCorrected;

  /// Human-readable audit log of each auto-correction applied.
  ///
  /// Empty when [wasCorrected] is `false`.
  final List<String> corrections;

  const ValidationReport({
    required this.errors,
    required this.warnings,
    required this.metrics,
    required this.wasCorrected,
    required this.corrections,
  });

  @override
  String toString() {
    final status = passed ? 'PASS' : 'FAIL';
    return 'ValidationReport($status, errors=${errors.length}, '
        'warnings=${warnings.length}, $metrics)';
  }
}
