/// Spring type for a suspension element.
enum SpringType {
  /// Force = k × displacement.
  linear,

  /// Force = k₁ × x + k₂ × x².
  progressive,

  /// Two distinct spring rates separated by a breakpoint displacement.
  dualRate,
}

/// Configuration for a suspension spring element.
class SpringConfig {
  const SpringConfig({
    required this.type,
    required this.springRateNPerMm,
    this.preloadMm = 0.0,
    this.progressiveRateNPerMm2 = 0.0,
    this.dualRateBreakpointMm = 0.0,
    this.secondarySpringRateNPerMm = 0.0,
  });

  /// Spring type (linear, progressive, or dual-rate).
  final SpringType type;

  /// Primary spring rate in N/mm.
  ///
  /// For dual-rate springs this is the rate applied before [dualRateBreakpointMm].
  final double springRateNPerMm;

  /// Static preload applied to the spring in mm.
  ///
  /// Positive values indicate the spring is pre-compressed at rest.
  final double preloadMm;

  /// Progressive rate coefficient k₂ in N/mm².
  ///
  /// Used only when [type] is [SpringType.progressive].
  /// Force = springRateNPerMm × x + progressiveRateNPerMm2 × x².
  final double progressiveRateNPerMm2;

  /// Displacement threshold in mm at which the spring rate changes.
  ///
  /// Used only when [type] is [SpringType.dualRate].
  final double dualRateBreakpointMm;

  /// Spring rate in N/mm applied beyond [dualRateBreakpointMm].
  ///
  /// Used only when [type] is [SpringType.dualRate].
  final double secondarySpringRateNPerMm;

  /// Returns a copy with any provided fields replaced.
  SpringConfig copyWith({
    SpringType? type,
    double? springRateNPerMm,
    double? preloadMm,
    double? progressiveRateNPerMm2,
    double? dualRateBreakpointMm,
    double? secondarySpringRateNPerMm,
  }) {
    return SpringConfig(
      type: type ?? this.type,
      springRateNPerMm: springRateNPerMm ?? this.springRateNPerMm,
      preloadMm: preloadMm ?? this.preloadMm,
      progressiveRateNPerMm2:
          progressiveRateNPerMm2 ?? this.progressiveRateNPerMm2,
      dualRateBreakpointMm: dualRateBreakpointMm ?? this.dualRateBreakpointMm,
      secondarySpringRateNPerMm:
          secondarySpringRateNPerMm ?? this.secondarySpringRateNPerMm,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpringConfig &&
          type == other.type &&
          springRateNPerMm == other.springRateNPerMm &&
          preloadMm == other.preloadMm &&
          progressiveRateNPerMm2 == other.progressiveRateNPerMm2 &&
          dualRateBreakpointMm == other.dualRateBreakpointMm &&
          secondarySpringRateNPerMm == other.secondarySpringRateNPerMm;

  @override
  int get hashCode => Object.hash(
        type,
        springRateNPerMm,
        preloadMm,
        progressiveRateNPerMm2,
        dualRateBreakpointMm,
        secondarySpringRateNPerMm,
      );

  @override
  String toString() =>
      'SpringConfig(type: $type, springRateNPerMm: $springRateNPerMm, '
      'preloadMm: $preloadMm, progressiveRateNPerMm2: $progressiveRateNPerMm2, '
      'dualRateBreakpointMm: $dualRateBreakpointMm, '
      'secondarySpringRateNPerMm: $secondarySpringRateNPerMm)';
}
