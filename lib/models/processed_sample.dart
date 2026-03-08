import 'imu_sample.dart';

/// The output of the preprocessing pipeline for a single IMU sample.
///
/// Carries the original [raw] sensor reading alongside derived channels
/// computed by the pipeline:
/// - **gravity-removed linear acceleration** ([accelXLinear], [accelYLinear],
///   [accelZLinear]) expressed in m/s²,
/// - **integrated velocity** (m/s) — populated only when the integration
///   stage is enabled,
/// - **double-integrated position** (m) — populated only when the integration
///   stage is enabled.
class ProcessedSample {
  /// Original sensor reading before any processing.
  final ImuSample raw;

  /// Gravity-removed linear acceleration along the X-axis in m/s².
  final double accelXLinear;

  /// Gravity-removed linear acceleration along the Y-axis in m/s².
  final double accelYLinear;

  /// Gravity-removed linear acceleration along the Z-axis in m/s².
  final double accelZLinear;

  /// Integrated velocity along the X-axis in m/s, or `null` when the
  /// integration stage is disabled.
  final double? velocityX;

  /// Integrated velocity along the Y-axis in m/s, or `null` when the
  /// integration stage is disabled.
  final double? velocityY;

  /// Integrated velocity along the Z-axis in m/s, or `null` when the
  /// integration stage is disabled.
  final double? velocityZ;

  /// Double-integrated position along the X-axis in m, or `null` when the
  /// integration stage is disabled.
  final double? positionX;

  /// Double-integrated position along the Y-axis in m, or `null` when the
  /// integration stage is disabled.
  final double? positionY;

  /// Double-integrated position along the Z-axis in m, or `null` when the
  /// integration stage is disabled.
  final double? positionZ;

  const ProcessedSample({
    required this.raw,
    required this.accelXLinear,
    required this.accelYLinear,
    required this.accelZLinear,
    this.velocityX,
    this.velocityY,
    this.velocityZ,
    this.positionX,
    this.positionY,
    this.positionZ,
  });

  /// Serialises the processed sample to a [Map] using canonical field names.
  ///
  /// The map includes all fields from [raw] (via [ImuSample.toMap]) plus the
  /// derived channels.  Velocity and position fields are omitted when `null`.
  Map<String, dynamic> toMap() => {
        ...raw.toMap(),
        'accel_x_linear_ms2': accelXLinear,
        'accel_y_linear_ms2': accelYLinear,
        'accel_z_linear_ms2': accelZLinear,
        if (velocityX != null) 'velocity_x_ms': velocityX,
        if (velocityY != null) 'velocity_y_ms': velocityY,
        if (velocityZ != null) 'velocity_z_ms': velocityZ,
        if (positionX != null) 'position_x_m': positionX,
        if (positionY != null) 'position_y_m': positionY,
        if (positionZ != null) 'position_z_m': positionZ,
      };

  @override
  String toString() => 'ProcessedSample(t=${raw.timestampMs}ms, '
      'linX=${accelXLinear.toStringAsFixed(3)}, '
      'linY=${accelYLinear.toStringAsFixed(3)}, '
      'linZ=${accelZLinear.toStringAsFixed(3)})';
}
