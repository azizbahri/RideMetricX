import '../../models/imu_sample.dart';

/// Parses IMU telemetry files in the canonical CSV format (FR-DC-004).
///
/// Expected header (first non-comment, non-empty line):
/// ```
/// timestamp_ms,accel_x_g,accel_y_g,accel_z_g,
/// gyro_x_dps,gyro_y_dps,gyro_z_dps,temp_c,sample_count
/// ```
/// Lines starting with `#` are treated as comments and skipped.
class CsvParser {
  const CsvParser._();

  /// Canonical column names in the required order (FR-DC-004).
  static const List<String> expectedHeaders = [
    'timestamp_ms',
    'accel_x_g',
    'accel_y_g',
    'accel_z_g',
    'gyro_x_dps',
    'gyro_y_dps',
    'gyro_z_dps',
    'temp_c',
    'sample_count',
  ];

  /// Parses [csvContent] and returns the list of [ImuSample] records.
  ///
  /// The first non-comment, non-empty line is treated as the header row and
  /// validated against [expectedHeaders] for exact column order and count.
  ///
  /// Throws [FormatException] if:
  /// - The content is empty after stripping comments.
  /// - The header column count or order does not match [expectedHeaders].
  /// - Any data row cannot be parsed.
  static List<ImuSample> parse(String csvContent) {
    final lines = csvContent
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();

    if (lines.isEmpty) {
      throw const FormatException('CSV content is empty.');
    }

    // Enforce exact canonical header order and column count.
    final headerCols =
        lines.first.split(',').map((c) => c.trim().toLowerCase()).toList();
    if (headerCols.length != expectedHeaders.length) {
      throw FormatException(
        'CSV header must have exactly ${expectedHeaders.length} columns '
        'in the canonical order: ${expectedHeaders.join(',')}. '
        'Found ${headerCols.length} columns.',
      );
    }
    for (int i = 0; i < expectedHeaders.length; i++) {
      if (headerCols[i] != expectedHeaders[i]) {
        throw FormatException(
          'CSV header column ${i + 1} must be "${expectedHeaders[i]}", '
          'but found "${headerCols[i]}". '
          'Expected canonical header: ${expectedHeaders.join(',')}.',
        );
      }
    }

    final samples = <ImuSample>[];
    for (int i = 1; i < lines.length; i++) {
      final cols = lines[i].split(',');
      try {
        samples.add(ImuSample.fromCsvRow(cols));
      } on FormatException catch (e) {
        throw FormatException('Error parsing CSV row $i: $e');
      }
    }
    return samples;
  }
}
