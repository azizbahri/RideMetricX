/// Exception thrown when a file's contents cannot be decoded as valid IMU data.
///
/// Covers scenarios such as truncated binary files, invalid checksums,
/// mixed-encoding corruption, or partially-written records.
///
/// Use [FileFormatException] for purely structural format problems (unsupported
/// file type, malformed header, wrong file extension), and this exception when
/// the file structure is recognisable but the payload data is corrupt.
class CorruptedDataException implements Exception {
  /// Human-readable description of the corruption found.
  final String message;

  /// Name of the file in which corruption was detected, if known.
  final String? fileName;

  const CorruptedDataException(this.message, {this.fileName});

  @override
  String toString() {
    final filePart = fileName != null ? ' (file: $fileName)' : '';
    return 'CorruptedDataException: $message$filePart';
  }
}
