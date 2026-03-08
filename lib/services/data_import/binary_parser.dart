import 'data_parser.dart';
import 'file_format_exception.dart';

/// Extension-point stub for binary format parsers (fixed-width struct,
/// HDF5, custom binary containers, etc.).
///
/// This stub intentionally throws [FileFormatException] to signal that
/// binary parsing is not yet implemented.  Concrete implementations should
/// extend [BinaryParser] and override [parse] (or accept raw bytes via a
/// separate `parseBytes` method once the interface is stabilised).
class BinaryParser extends DataParser {
  const BinaryParser();

  /// Always throws [FileFormatException] – binary parsing is not yet
  /// implemented in this version.
  @override
  List<Map<String, dynamic>> parse(String content) {
    throw const FileFormatException(
      'Binary format parsing is not yet supported. '
      'Convert the binary file to CSV or JSON before importing.',
    );
  }
}
