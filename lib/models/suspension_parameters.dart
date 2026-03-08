/// Parameters for a single suspension end (front or rear).
class SuspensionParameters {
  const SuspensionParameters({
    required this.springRate,
    required this.compression,
    required this.rebound,
    required this.preload,
  });

  /// Spring rate in N/mm. Valid range: [kMinSpringRate, kMaxSpringRate].
  final double springRate;

  /// Compression damping in clicks. Valid range: [kMinClicks, kMaxClicks].
  final double compression;

  /// Rebound damping in clicks. Valid range: [kMinClicks, kMaxClicks].
  final double rebound;

  /// Preload in mm. Valid range: [kMinPreload, kMaxPreload].
  final double preload;

  // ── Bounds ────────────────────────────────────────────────────────────────
  static const double kMinSpringRate = 10.0;
  static const double kMaxSpringRate = 50.0;
  static const double kMinClicks = 0.0;
  static const double kMaxClicks = 20.0;
  static const double kMinPreload = 0.0;
  static const double kMaxPreload = 10.0;

  /// Returns a copy with any provided fields replaced.
  SuspensionParameters copyWith({
    double? springRate,
    double? compression,
    double? rebound,
    double? preload,
  }) {
    return SuspensionParameters(
      springRate: springRate ?? this.springRate,
      compression: compression ?? this.compression,
      rebound: rebound ?? this.rebound,
      preload: preload ?? this.preload,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SuspensionParameters &&
          springRate == other.springRate &&
          compression == other.compression &&
          rebound == other.rebound &&
          preload == other.preload;

  @override
  int get hashCode => Object.hash(springRate, compression, rebound, preload);

  @override
  String toString() =>
      'SuspensionParameters(springRate: $springRate, compression: $compression, '
      'rebound: $rebound, preload: $preload)';
}

/// Combined front+rear tuning parameters with named presets.
class TuningParameters {
  const TuningParameters({required this.front, required this.rear});

  final SuspensionParameters front;
  final SuspensionParameters rear;

  // ── Presets ───────────────────────────────────────────────────────────────

  /// Balanced, stock-equivalent setup.
  static const TuningParameters defaultPreset = TuningParameters(
    front: SuspensionParameters(
      springRate: 25.0,
      compression: 10.0,
      rebound: 10.0,
      preload: 5.0,
    ),
    rear: SuspensionParameters(
      springRate: 30.0,
      compression: 10.0,
      rebound: 10.0,
      preload: 5.0,
    ),
  );

  /// Soft, comfort-oriented setup for low-speed or rough-terrain use.
  static const TuningParameters softPreset = TuningParameters(
    front: SuspensionParameters(
      springRate: 15.0,
      compression: 5.0,
      rebound: 5.0,
      preload: 2.0,
    ),
    rear: SuspensionParameters(
      springRate: 18.0,
      compression: 5.0,
      rebound: 5.0,
      preload: 2.0,
    ),
  );

  /// Firm, sport-oriented setup for high-speed or track use.
  static const TuningParameters firmPreset = TuningParameters(
    front: SuspensionParameters(
      springRate: 40.0,
      compression: 16.0,
      rebound: 16.0,
      preload: 8.0,
    ),
    rear: SuspensionParameters(
      springRate: 45.0,
      compression: 16.0,
      rebound: 16.0,
      preload: 8.0,
    ),
  );

  /// Returns a copy with any provided fields replaced.
  TuningParameters copyWith({
    SuspensionParameters? front,
    SuspensionParameters? rear,
  }) {
    return TuningParameters(
      front: front ?? this.front,
      rear: rear ?? this.rear,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TuningParameters && front == other.front && rear == other.rear;

  @override
  int get hashCode => Object.hash(front, rear);

  @override
  String toString() => 'TuningParameters(front: $front, rear: $rear)';
}
