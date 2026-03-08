import 'dart:math' as math;

import '../../models/damping_config.dart';
import '../../models/ride_session.dart';
import '../../models/simulation_result.dart';
import '../../models/spring_config.dart';
import '../../models/suspension_parameters.dart';
import 'click_mapper.dart';
import 'damping_model.dart';
import 'spring_model.dart';

/// Orchestrates the suspension physics simulation (FR-SM-010).
///
/// For each suspension end (front and rear) the engine integrates a simplified
/// quarter-car mass–spring–damper model over a time series of road-input
/// accelerations:
///
/// ```
/// m·z'' = F_input(t) − F_spring(z) − F_damping(z')
/// ```
///
/// where:
/// - `z` is the suspension displacement in mm (positive = compressed),
/// - `F_spring` is computed via [SpringModel],
/// - `F_damping` is computed via [DampingModel], and
/// - click positions are mapped to damping coefficients via [ClickMapper].
///
/// When a [RideSession] is supplied, its preprocessed IMU acceleration samples
/// are used as the road-input forcing function.  Otherwise a representative
/// synthetic road profile is generated automatically.
///
/// Usage:
/// ```dart
/// const engine = SimulationEngine();
/// final result = await engine.simulate(tuning: TuningParameters.defaultPreset);
/// print(result.frontMetrics);
/// ```
class SimulationEngine {
  const SimulationEngine();

  // ── Physical defaults ──────────────────────────────────────────────────────

  /// Sprung mass acting on the front suspension in kg.
  static const double kFrontSprungMassKg = 113.0;

  /// Sprung mass acting on the rear suspension in kg.
  static const double kRearSprungMassKg = 120.0;

  /// Maximum front fork travel in mm.
  static const double kFrontMaxTravelMm = 210.0;

  /// Maximum rear shock travel in mm.
  static const double kRearMaxTravelMm = 200.0;

  /// Base compression damping coefficient at 0 clicks (N·s/mm).
  static const double kBaseCompressionCoeffNsPerMm = 3.0;

  /// Base rebound damping coefficient at 0 clicks (N·s/mm).
  static const double kBaseReboundCoeffNsPerMm = 3.0;

  /// Synthetic road-profile sample rate in Hz.
  static const double kSyntheticSampleRateHz = 200.0;

  /// Duration of the synthetic road profile in seconds.
  static const double kSyntheticDurationS = 10.0;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Runs a suspension simulation and returns the [SimulationResult].
  ///
  /// When [session] is provided its preprocessed front/rear samples are used
  /// as the road-input forcing function; missing ends fall back to synthetic
  /// data.  When [session] is omitted entirely a representative synthetic road
  /// profile is used for both ends.
  ///
  /// The heavy computation is offloaded to a microtask so the UI thread
  /// remains responsive during the simulation.
  Future<SimulationResult> simulate({
    required TuningParameters tuning,
    RideSession? session,
  }) {
    return Future.microtask(() => _runSimulation(tuning, session));
  }

  // ── Internal orchestration ─────────────────────────────────────────────────

  SimulationResult _runSimulation(
    TuningParameters tuning,
    RideSession? session,
  ) {
    final double dt;
    final List<double> frontInput;
    final List<double> rearInput;

    if (session != null &&
        (session.frontProcessed.isNotEmpty ||
            session.rearProcessed.isNotEmpty)) {
      final rateHz = session.frontMetadata?.samplingRateHz ??
          session.rearMetadata?.samplingRateHz ??
          kSyntheticSampleRateHz;
      dt = 1.0 / rateHz;

      frontInput = session.frontProcessed.isNotEmpty
          ? session.frontProcessed
              .map((s) => s.accelZLinear)
              .toList(growable: false)
          : _generateSyntheticAccel(dt, kSyntheticDurationS);

      rearInput = session.rearProcessed.isNotEmpty
          ? session.rearProcessed
              .map((s) => s.accelZLinear)
              .toList(growable: false)
          : _generateSyntheticAccel(dt, kSyntheticDurationS);
    } else {
      dt = 1.0 / kSyntheticSampleRateHz;
      frontInput = _generateSyntheticAccel(dt, kSyntheticDurationS);
      rearInput = _generateSyntheticAccel(dt, kSyntheticDurationS);
    }

    final frontSamples = _integrateOneSide(
      tuning.front,
      frontInput,
      dt,
      kFrontSprungMassKg,
      kFrontMaxTravelMm,
    );
    final rearSamples = _integrateOneSide(
      tuning.rear,
      rearInput,
      dt,
      kRearSprungMassKg,
      kRearMaxTravelMm,
    );

    return SimulationResult(
      frontSamples: frontSamples,
      rearSamples: rearSamples,
      frontMetrics: _computeMetrics(frontSamples, kFrontMaxTravelMm),
      rearMetrics: _computeMetrics(rearSamples, kRearMaxTravelMm),
      parameters: tuning,
    );
  }

  // ── Quarter-car integration ────────────────────────────────────────────────

  /// Integrates the quarter-car ODE for one suspension end using forward
  /// Euler and returns the resulting [SimulationSample] list.
  ///
  /// All forces are computed in SI units (N, m/s²) and displacement is
  /// tracked in mm.  The equations used at each timestep are:
  /// ```
  /// F_spring [N]   = k [N/mm] × z [mm]
  /// F_damping [N]  = c [N·s/mm] × (z' [mm/s] / 1000)
  /// z'' [mm/s²]    = 1000 × (a_input [m/s²] − (F_spring + F_damping) / m [kg])
  /// ```
  /// where `z` is displacement in mm (positive = compressed) and `z'` is
  /// velocity in mm/s.
  ///
  /// The initial displacement is set to the static sag position:
  /// `z₀ [mm] = (m [kg] × 9.81 [m/s²]) / k [N/mm]`
  List<SimulationSample> _integrateOneSide(
    SuspensionParameters params,
    List<double> accelInput,
    double dt,
    double sprungMassKg,
    double maxTravelMm,
  ) {
    final springConfig = SpringConfig(
      type: SpringType.linear,
      springRateNPerMm: params.springRate,
      preloadMm: params.preload,
    );

    final comprCoeffNsPerMm = ClickMapper.clicksToCoefficient(
      params.compression,
      kBaseCompressionCoeffNsPerMm,
    );
    final rebCoeffNsPerMm = ClickMapper.clicksToCoefficient(
      params.rebound,
      kBaseReboundCoeffNsPerMm,
    );

    final samples = <SimulationSample>[];

    // Start at static sag (equilibrium under gravity), clamped to valid range.
    double dispMm =
        ((sprungMassKg * 9.81) / params.springRate).clamp(0.0, maxTravelMm);
    double velMms = 0.0; // mm/s

    final double dtMs = dt * 1000.0; // for timeMs calculation

    for (int i = 0; i < accelInput.length; i++) {
      final timeMs = i * dtMs;
      final inputAccelMps2 = accelInput[i];

      // Clamp displacement to physical travel limits.
      final clampedDispMm = dispMm.clamp(0.0, maxTravelMm);

      // Spring force [N]: k [N/mm] × x [mm].
      final springForceN =
          SpringModel.calculateForce(
            springConfig,
            displacementMm: clampedDispMm,
          ).forceN;

      // Damping coefficient: compression when z' > 0, rebound otherwise.
      // Velocity converted from mm/s to m/s for DampingModel.
      final velMps = velMms / 1000.0;
      final dampCoeffNsPerMm =
          velMms >= 0 ? comprCoeffNsPerMm : rebCoeffNsPerMm;
      final dampForceN = DampingModel.calculateForce(
        DampingConfig(
          type: DampingType.linear,
          lowSpeedCoefficientNsPerMm: dampCoeffNsPerMm,
        ),
        velocityMps: velMps,
      ).forceN;

      samples.add(SimulationSample(
        timeMs: timeMs,
        displacementMm: clampedDispMm,
        velocityMps: velMps,
        springForceN: springForceN,
        dampingForceN: dampForceN,
      ));

      // Equation of motion:
      // m·z'' = m·a_input − F_spring − F_damping
      // z'' [mm/s²] = a_input [m/s²]×1000 − (F_spring + F_damping)/m×1000
      //             = 1000 × (a_input − (F_spring + F_damping) / m)
      final netAccelMps2 =
          inputAccelMps2 - (springForceN + dampForceN) / sprungMassKg;
      final netAccelMms2 = netAccelMps2 * 1000.0;

      // Forward Euler integration.
      velMms += netAccelMms2 * dt;
      dispMm += velMms * dt;
    }

    return samples;
  }

  // ── Synthetic road profile ─────────────────────────────────────────────────

  /// Generates a synthetic road-input acceleration profile (m/s²).
  ///
  /// The profile is a superposition of sinusoids that approximate typical
  /// off-road terrain:
  /// - Low frequency (0.5–1.5 Hz): large-amplitude body motions.
  /// - Mid frequency (3–8 Hz): individual bump inputs.
  /// - High frequency (15–30 Hz): road-surface chatter.
  ///
  /// A fixed random seed ensures the profile is reproducible across runs.
  List<double> _generateSyntheticAccel(double dt, double durationS) {
    final n = (durationS / dt).round();
    final rng = math.Random(42); // deterministic seed

    return List<double>.generate(n, (i) {
      final t = i * dt;

      final low = 0.8 * math.sin(2 * math.pi * 0.7 * t) +
          0.5 * math.sin(2 * math.pi * 1.3 * t + 0.5);

      final mid = 0.4 * math.sin(2 * math.pi * 5.0 * t) +
          0.3 * math.sin(2 * math.pi * 7.5 * t + 1.2);

      final high = 0.15 * math.sin(2 * math.pi * 18.0 * t + 0.3) +
          0.10 * math.sin(2 * math.pi * 25.0 * t + 0.8);

      final noise = 0.05 * (rng.nextDouble() * 2.0 - 1.0);

      return low + mid + high + noise;
    });
  }

  // ── Metrics ────────────────────────────────────────────────────────────────

  /// Computes aggregate [SimulationMetrics] from a completed sample list.
  SimulationMetrics _computeMetrics(
    List<SimulationSample> samples,
    double maxTravelMm,
  ) {
    if (samples.isEmpty) {
      return const SimulationMetrics(
        maxDisplacementMm: 0,
        rmsDisplacementMm: 0,
        bottomingEvents: 0,
        toppingEvents: 0,
      );
    }

    double maxDisp = 0.0;
    double sumSq = 0.0;
    int bottomingEvents = 0;
    int toppingEvents = 0;
    bool wasBottoming = false;
    bool wasTopping = false;

    // Bottoming: displacement >= 95 % of max travel.
    final bottomingThreshMm = maxTravelMm * 0.95;
    // Topping out: displacement <= 5 % of max travel (analogous to bottoming
    // at 95 %, counting events near full extension rather than full compression).
    final toppingThreshMm = maxTravelMm * 0.05;

    for (final s in samples) {
      final d = s.displacementMm;
      if (d > maxDisp) maxDisp = d;
      sumSq += d * d;

      final isBottoming = d >= bottomingThreshMm;
      if (isBottoming && !wasBottoming) bottomingEvents++;
      wasBottoming = isBottoming;

      final isTopping = d <= toppingThreshMm;
      if (isTopping && !wasTopping) toppingEvents++;
      wasTopping = isTopping;
    }

    return SimulationMetrics(
      maxDisplacementMm: maxDisp,
      rmsDisplacementMm: math.sqrt(sumSq / samples.length),
      bottomingEvents: bottomingEvents,
      toppingEvents: toppingEvents,
    );
  }
}
