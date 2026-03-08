/// Damping adjuster positions in clicks for a single suspension end (FR-SM-006).
///
/// Tracks the four independent adjusters found on modern motorcycle dampers:
/// Low-Speed Compression (LSC), High-Speed Compression (HSC),
/// Low-Speed Rebound (LSR), and High-Speed Rebound (HSR).
///
/// A value of 0 represents the full-hard (minimum damping) position;
/// higher click counts represent softer (more open) settings.
class DampingClicksConfig {
  const DampingClicksConfig({
    required this.compressionLowSpeedClicks,
    required this.compressionHighSpeedClicks,
    required this.reboundLowSpeedClicks,
    required this.reboundHighSpeedClicks,
  });

  /// Low-speed compression clicks (LSC).
  ///
  /// Controls damping for slow shaft velocities (e.g. weight transfer).
  /// Valid range: [[kMinClicks], [kMaxClicks]].
  final double compressionLowSpeedClicks;

  /// High-speed compression clicks (HSC).
  ///
  /// Controls damping for fast shaft velocities (e.g. sharp impacts).
  /// Valid range: [[kMinClicks], [kMaxClicks]].
  final double compressionHighSpeedClicks;

  /// Low-speed rebound clicks (LSR).
  ///
  /// Controls extension speed after slow compressions.
  /// Valid range: [[kMinClicks], [kMaxClicks]].
  final double reboundLowSpeedClicks;

  /// High-speed rebound clicks (HSR).
  ///
  /// Controls extension speed after fast compressions.
  /// Valid range: [[kMinClicks], [kMaxClicks]].
  final double reboundHighSpeedClicks;

  // ── Bounds ──────────────────────────────────────────────────────────────────

  /// Minimum adjuster position (full hard).
  static const double kMinClicks = 0.0;

  /// Maximum adjuster position (full soft).
  ///
  /// Most motorcycle dampers offer between 20 and 30 clicks of adjustment.
  static const double kMaxClicks = 30.0;

  // ── copyWith ────────────────────────────────────────────────────────────────

  /// Returns a copy with any provided fields replaced.
  DampingClicksConfig copyWith({
    double? compressionLowSpeedClicks,
    double? compressionHighSpeedClicks,
    double? reboundLowSpeedClicks,
    double? reboundHighSpeedClicks,
  }) {
    return DampingClicksConfig(
      compressionLowSpeedClicks:
          compressionLowSpeedClicks ?? this.compressionLowSpeedClicks,
      compressionHighSpeedClicks:
          compressionHighSpeedClicks ?? this.compressionHighSpeedClicks,
      reboundLowSpeedClicks:
          reboundLowSpeedClicks ?? this.reboundLowSpeedClicks,
      reboundHighSpeedClicks:
          reboundHighSpeedClicks ?? this.reboundHighSpeedClicks,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DampingClicksConfig &&
          compressionLowSpeedClicks == other.compressionLowSpeedClicks &&
          compressionHighSpeedClicks == other.compressionHighSpeedClicks &&
          reboundLowSpeedClicks == other.reboundLowSpeedClicks &&
          reboundHighSpeedClicks == other.reboundHighSpeedClicks;

  @override
  int get hashCode => Object.hash(
        compressionLowSpeedClicks,
        compressionHighSpeedClicks,
        reboundLowSpeedClicks,
        reboundHighSpeedClicks,
      );

  @override
  String toString() =>
      'DampingClicksConfig('
      'compressionLowSpeedClicks: $compressionLowSpeedClicks, '
      'compressionHighSpeedClicks: $compressionHighSpeedClicks, '
      'reboundLowSpeedClicks: $reboundLowSpeedClicks, '
      'reboundHighSpeedClicks: $reboundHighSpeedClicks)';
}
