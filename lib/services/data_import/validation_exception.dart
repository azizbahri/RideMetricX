import '../../models/validation_error.dart';

/// Exception thrown when imported data fails domain validation rules.
///
/// Carries the [ValidationError] objects that triggered the failure so that
/// callers can surface precise diagnostics to the user.
///
/// Distinct from [FileFormatException]: a format exception occurs when the
/// file cannot be decoded at all; a validation exception occurs when the file
/// is parseable but the content violates data-quality constraints (e.g.
/// non-monotonic timestamps, out-of-range sensor values).
class ValidationException implements Exception {
  /// Human-readable description of the validation failure.
  final String message;

  /// Individual validation errors that triggered this exception.
  ///
  /// May be empty when the failure is stream-level rather than sample-level
  /// (e.g. empty sample list).
  final List<ValidationError> errors;

  const ValidationException(this.message, {this.errors = const []});

  @override
  String toString() {
    if (errors.isEmpty) return 'ValidationException: $message';
    return 'ValidationException: $message (${errors.length} error(s))';
  }
}
