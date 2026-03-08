/// A single validation error emitted by [ValidationService].
///
/// Errors represent conditions that cause the validation to **fail**
/// (e.g. non-monotonic timestamps, NaN values in required fields).
class ValidationError {
  /// The canonical field name that triggered the error, if applicable.
  ///
  /// Uses `null` when the error applies to the stream as a whole
  /// (e.g. empty sample list).
  final String? field;

  /// Human-readable description of the problem.
  final String message;

  /// 0-based index into the validated sample list, if applicable.
  final int? sampleIndex;

  const ValidationError({
    required this.message,
    this.field,
    this.sampleIndex,
  });

  @override
  String toString() {
    final buf = StringBuffer('ValidationError: $message');
    if (field != null) buf.write(' [field=$field]');
    if (sampleIndex != null) buf.write(' [sample=$sampleIndex]');
    return buf.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValidationError &&
          field == other.field &&
          message == other.message &&
          sampleIndex == other.sampleIndex;

  @override
  int get hashCode => Object.hash(field, message, sampleIndex);
}
