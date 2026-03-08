/// Exception thrown when a file has an unsupported or invalid format.
///
/// Carries optional [line] and [column] for precise error location, plus
/// a human-readable [context] snippet from the failing input.
class FileFormatException implements Exception {
  /// Short description of the problem.
  final String message;

  /// 1-based line number within the source, if available.
  final int? line;

  /// 1-based column number within the source, if available.
  final int? column;

  /// Small excerpt of the failing input for diagnostic display.
  final String? context;

  const FileFormatException(
    this.message, {
    this.line,
    this.column,
    this.context,
  });

  @override
  String toString() {
    final buf = StringBuffer('FileFormatException: $message');
    if (line != null) {
      buf.write(' (line $line');
      if (column != null) buf.write(', col $column');
      buf.write(')');
    }
    if (context != null) buf.write(' — near: "$context"');
    return buf.toString();
  }
}
