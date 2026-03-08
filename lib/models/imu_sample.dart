/// Canonical IMU sample schema for RideMetricX data collection.
///
/// Fields match the hardware datalogger CSV/binary output for front/rear
/// suspension sensors (FR-DC-004).
class ImuSample {
  /// Milliseconds since recording start (monotonically increasing).
  final int timestampMs;

  /// Accelerometer X-axis reading in g (1 g ≈ 9.81 m/s²).
  final double accelXG;

  /// Accelerometer Y-axis reading in g.
  final double accelYG;

  /// Accelerometer Z-axis reading in g.
  final double accelZG;

  /// Gyroscope X-axis reading in degrees per second.
  final double gyroXDps;

  /// Gyroscope Y-axis reading in degrees per second.
  final double gyroYDps;

  /// Gyroscope Z-axis reading in degrees per second.
  final double gyroZDps;

  /// Board temperature in Celsius (used for sensor compensation).
  final double tempC;

  /// Monotonically increasing sample counter for dropped-sample detection.
  final int sampleCount;

  const ImuSample({
    required this.timestampMs,
    required this.accelXG,
    required this.accelYG,
    required this.accelZG,
    required this.gyroXDps,
    required this.gyroYDps,
    required this.gyroZDps,
    required this.tempC,
    required this.sampleCount,
  });

  /// Parses a single CSV data row (9 fields, no header).
  ///
  /// Expected column order (FR-DC-004):
  /// `timestamp_ms, accel_x_g, accel_y_g, accel_z_g,
  ///  gyro_x_dps, gyro_y_dps, gyro_z_dps, temp_c, sample_count`
  factory ImuSample.fromCsvRow(List<String> row) {
    if (row.length != 9) {
      throw FormatException(
        'CSV row must have exactly 9 columns, got ${row.length}.',
      );
    }
    return ImuSample(
      timestampMs: int.parse(row[0].trim()),
      accelXG: double.parse(row[1].trim()),
      accelYG: double.parse(row[2].trim()),
      accelZG: double.parse(row[3].trim()),
      gyroXDps: double.parse(row[4].trim()),
      gyroYDps: double.parse(row[5].trim()),
      gyroZDps: double.parse(row[6].trim()),
      tempC: double.parse(row[7].trim()),
      sampleCount: int.parse(row[8].trim()),
    );
  }

  /// Returns all fields as a [Map] using the canonical CSV column names.
  Map<String, dynamic> toMap() => {
    'timestamp_ms': timestampMs,
    'accel_x_g': accelXG,
    'accel_y_g': accelYG,
    'accel_z_g': accelZG,
    'gyro_x_dps': gyroXDps,
    'gyro_y_dps': gyroYDps,
    'gyro_z_dps': gyroZDps,
    'temp_c': tempC,
    'sample_count': sampleCount,
  };

  @override
  String toString() =>
      'ImuSample(t=${timestampMs}ms, az=${accelZG}g, n=$sampleCount)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImuSample &&
          timestampMs == other.timestampMs &&
          sampleCount == other.sampleCount;

  @override
  int get hashCode => Object.hash(timestampMs, sampleCount);
}
