/// Result of a suspension sag calculation.
class SagResult {
  const SagResult({required this.freeSagMm, required this.staticSagMm});

  /// Free sag in mm: suspension compression under bike weight only.
  final double freeSagMm;

  /// Static (race) sag in mm: suspension compression under bike + rider weight.
  final double staticSagMm;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SagResult &&
          freeSagMm == other.freeSagMm &&
          staticSagMm == other.staticSagMm;

  @override
  int get hashCode => Object.hash(freeSagMm, staticSagMm);

  @override
  String toString() =>
      'SagResult(freeSagMm: $freeSagMm, staticSagMm: $staticSagMm)';
}
