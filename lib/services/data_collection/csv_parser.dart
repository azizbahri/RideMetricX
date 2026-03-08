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
  /// validated against [expectedHeaders].
  ///
  /// Throws [FormatException] if:
  /// - The content is empty after stripping comments.
  /// - A required column is absent from the header.
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

    // Validate header row.
    final headerCols =
        lines.first.split(',').map((c) => c.trim().toLowerCase()).toList();
    for (final required in expectedHeaders) {
      if (!headerCols.contains(required)) {
        throw FormatException(
          'CSV header is missing required column: "$required".',
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
