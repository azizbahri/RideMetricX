/// A single validation warning emitted by [ValidationService].
///
/// Warnings represent conditions that are suspicious but do not
/// necessarily invalidate the data stream (e.g. large timestamp gaps,
/// outlier values, stuck-sensor signals).
class ValidationWarning {
  /// The canonical field name that triggered the warning, if applicable.
  ///
  /// Uses `null` when the warning applies to the stream as a whole.
  final String? field;

  /// Human-readable description of the concern.
  final String message;

  /// 0-based index into the validated sample list, if applicable.
  final int? sampleIndex;

  const ValidationWarning({
    required this.message,
    this.field,
    this.sampleIndex,
  });

  @override
  String toString() {
    final buf = StringBuffer('ValidationWarning: $message');
    if (field != null) buf.write(' [field=$field]');
    if (sampleIndex != null) buf.write(' [sample=$sampleIndex]');
    return buf.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValidationWarning &&
          field == other.field &&
          message == other.message &&
          sampleIndex == other.sampleIndex;

  @override
  int get hashCode => Object.hash(field, message, sampleIndex);
}
