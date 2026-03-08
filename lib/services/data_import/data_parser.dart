/// Abstract strategy interface for import-format parsers.
///
/// Each concrete parser is responsible for converting raw text content
/// into a list of canonical field maps.  Downstream code can then map
/// those maps to domain objects (e.g. [ImuSample]).
///
/// Implementations must throw [FileFormatException] on unrecoverable
/// parse errors and may include line/column context in the exception.
abstract class DataParser {
  const DataParser();

  /// Parses [content] and returns a list of record maps.
  ///
  /// Each map uses the canonical field names defined for the import schema
  /// (e.g. `timestamp_ms`, `accel_x_g`, …).
  ///
  /// Throws [FileFormatException] if [content] is malformed.
  List<Map<String, dynamic>> parse(String content);
}
