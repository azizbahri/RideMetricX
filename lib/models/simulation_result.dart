import 'package:flutter/foundation.dart';

import 'suspension_parameters.dart';

/// A single predicted suspension state at one simulation timestep.
@immutable
class SimulationSample {
  const SimulationSample({
    required this.timeMs,
    required this.displacementMm,
    required this.velocityMps,
    required this.springForceN,
    required this.dampingForceN,
  });

  /// Elapsed time in milliseconds from the start of the simulation.
  final double timeMs;

  /// Predicted suspension displacement in mm (positive = compressed).
  final double displacementMm;

  /// Suspension velocity in m/s (positive = compressing).
  final double velocityMps;

  /// Spring force contribution in Newtons.
  final double springForceN;

  /// Damping force contribution in Newtons.
  final double dampingForceN;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SimulationSample &&
          timeMs == other.timeMs &&
          displacementMm == other.displacementMm &&
          velocityMps == other.velocityMps &&
          springForceN == other.springForceN &&
          dampingForceN == other.dampingForceN;

  @override
  int get hashCode => Object.hash(
        timeMs,
        displacementMm,
        velocityMps,
        springForceN,
        dampingForceN,
      );

  @override
  String toString() =>
      'SimulationSample(t=${timeMs.toStringAsFixed(1)}ms, '
      'x=${displacementMm.toStringAsFixed(2)}mm, '
      'v=${velocityMps.toStringAsFixed(3)}m/s)';
}

/// Aggregate metrics computed over an entire simulation run for one suspension
/// end.
@immutable
class SimulationMetrics {
  const SimulationMetrics({
    required this.maxDisplacementMm,
    required this.rmsDisplacementMm,
    required this.bottomingEvents,
    required this.toppingEvents,
  });

  /// Peak suspension displacement in mm.
  final double maxDisplacementMm;

  /// Root-mean-square suspension displacement in mm.
  final double rmsDisplacementMm;

  /// Number of distinct bottoming events (displacement ≥ 95 % of max travel).
  final int bottomingEvents;

  /// Number of distinct topping-out events (displacement ≤ 5 % of max travel).
  final int toppingEvents;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SimulationMetrics &&
          maxDisplacementMm == other.maxDisplacementMm &&
          rmsDisplacementMm == other.rmsDisplacementMm &&
          bottomingEvents == other.bottomingEvents &&
          toppingEvents == other.toppingEvents;

  @override
  int get hashCode => Object.hash(
        maxDisplacementMm,
        rmsDisplacementMm,
        bottomingEvents,
        toppingEvents,
      );

  @override
  String toString() =>
      'SimulationMetrics(max=${maxDisplacementMm.toStringAsFixed(1)}mm, '
      'rms=${rmsDisplacementMm.toStringAsFixed(1)}mm, '
      'bottom=$bottomingEvents, top=$toppingEvents)';
}

/// The full output of a [SimulationEngine] run.
@immutable
class SimulationResult {
  const SimulationResult({
    required this.frontSamples,
    required this.rearSamples,
    required this.frontMetrics,
    required this.rearMetrics,
    required this.parameters,
  });

  /// Predicted front-suspension samples over the simulation window.
  final List<SimulationSample> frontSamples;

  /// Predicted rear-suspension samples over the simulation window.
  final List<SimulationSample> rearSamples;

  /// Aggregate metrics for the front suspension.
  final SimulationMetrics frontMetrics;

  /// Aggregate metrics for the rear suspension.
  final SimulationMetrics rearMetrics;

  /// The tuning parameters that produced this result.
  final TuningParameters parameters;

  @override
  String toString() =>
      'SimulationResult(front=${frontSamples.length} samples, '
      'rear=${rearSamples.length} samples, '
      'frontMetrics=$frontMetrics, rearMetrics=$rearMetrics)';
}
