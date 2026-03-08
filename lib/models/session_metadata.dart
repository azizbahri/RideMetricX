/// Mounting position of the IMU sensor.
enum SensorPosition { front, rear }

/// Session-level metadata for a single IMU recording.
///
/// Captures synchronization information required to align front and rear
/// sensor streams (FR-DC-005 / TC-DC-007).
class SessionMetadata {
  /// Unique session identifier (e.g., ISO-8601 timestamp string).
  final String sessionId;

  /// Mounting position of this sensor.
  final SensorPosition position;

  /// UTC wall-clock time when recording started, if available.
  final DateTime? recordedAt;

  /// Nominal sampling rate in Hz (default 200 Hz per FR-DC-001).
  final double samplingRateHz;

  /// Millisecond offset to align this session with the paired sensor.
  ///
  /// Positive value means this sensor started [syncOffsetMs] milliseconds
  /// *after* the paired sensor.  Must stay within ±100 ms over a 2-hour
  /// session (TC-DC-007).
  final int syncOffsetMs;

  /// Session ID of the paired (front/rear) sensor recording, if any.
  final String? pairedSessionId;

  const SessionMetadata({
    required this.sessionId,
    required this.position,
    this.recordedAt,
    this.samplingRateHz = 200.0,
    this.syncOffsetMs = 0,
    this.pairedSessionId,
  });

  /// Whether this session is paired with another sensor session.
  bool get hasPair => pairedSessionId != null;

  @override
  String toString() =>
      'SessionMetadata(id=$sessionId, position=${position.name}, '
      'rate=${samplingRateHz}Hz, syncOffset=${syncOffsetMs}ms)';
}
