import '../../models/damping_clicks_config.dart';
import '../../models/linkage_config.dart';
import '../../models/motorcycle_config.dart';
import '../../models/rider_config.dart';
import '../../models/spring_config.dart';
import '../../models/suspension_config.dart';

/// Validates a [SuspensionConfig] for required-field and range constraints
/// as defined in FR-SM-006.
///
/// Use [validate] to retrieve a list of human-readable error messages.
/// An empty list indicates the configuration is valid.
///
/// Example:
/// ```dart
/// final errors = ConfigValidator.validate(config);
/// if (errors.isEmpty) {
///   // safe to proceed
/// } else {
///   errors.forEach(print);
/// }
/// ```
class ConfigValidator {
  ConfigValidator._();

  /// Validates [config] and returns a list of error messages.
  ///
  /// Returns an empty list when the configuration is fully valid.
  /// Each message identifies the failing field and the violated constraint.
  static List<String> validate(SuspensionConfig config) {
    final errors = <String>[];
    _validateMotorcycle(config.motorcycle, errors);
    _validateRider(config.rider, errors);
    _validateSpring(config.front.spring, 'front.spring', errors);
    _validateDampingClicks(config.front.damping, 'front.damping', errors);
    _validateFrontGeometry(config, errors);
    _validateSpring(config.rear.spring, 'rear.spring', errors);
    _validateDampingClicks(config.rear.damping, 'rear.damping', errors);
    _validateLinkage(config.rear.linkage, errors);
    _validateRearGeometry(config, errors);
    return errors;
  }

  // ── Motorcycle ──────────────────────────────────────────────────────────────

  static void _validateMotorcycle(
    MotorcycleConfig m,
    List<String> errors,
  ) {
    if (m.model.trim().isEmpty) {
      errors.add('motorcycle.model must not be empty.');
    }
    if (m.weightDryKg <= 0) {
      errors.add(
        'motorcycle.weightDryKg must be > 0 (got ${m.weightDryKg}).',
      );
    } else {
      if (m.weightDryKg < MotorcycleConfig.kMinWeightDryKg) {
        errors.add(
          'motorcycle.weightDryKg must be >= ${MotorcycleConfig.kMinWeightDryKg} kg '
          '(got ${m.weightDryKg}).',
        );
      }
      if (m.weightDryKg > MotorcycleConfig.kMaxWeightDryKg) {
        errors.add(
          'motorcycle.weightDryKg must be <= ${MotorcycleConfig.kMaxWeightDryKg} kg '
          '(got ${m.weightDryKg}).',
        );
      }
    }
  }

  // ── Rider ───────────────────────────────────────────────────────────────────

  static void _validateRider(RiderConfig r, List<String> errors) {
    if (r.weightKg <= 0) {
      errors.add('rider.weightKg must be > 0 (got ${r.weightKg}).');
    } else {
      if (r.weightKg < RiderConfig.kMinWeightKg) {
        errors.add(
          'rider.weightKg must be >= ${RiderConfig.kMinWeightKg} kg '
          '(got ${r.weightKg}).',
        );
      }
      if (r.weightKg > RiderConfig.kMaxWeightKg) {
        errors.add(
          'rider.weightKg must be <= ${RiderConfig.kMaxWeightKg} kg '
          '(got ${r.weightKg}).',
        );
      }
    }
    if (r.gearWeightKg < RiderConfig.kMinGearWeightKg) {
      errors.add(
        'rider.gearWeightKg must be >= ${RiderConfig.kMinGearWeightKg} kg '
        '(got ${r.gearWeightKg}).',
      );
    }
    if (r.gearWeightKg > RiderConfig.kMaxGearWeightKg) {
      errors.add(
        'rider.gearWeightKg must be <= ${RiderConfig.kMaxGearWeightKg} kg '
        '(got ${r.gearWeightKg}).',
      );
    }
  }

  // ── Spring ──────────────────────────────────────────────────────────────────

  static void _validateSpring(
    SpringConfig s,
    String prefix,
    List<String> errors,
  ) {
    if (s.springRateNPerMm <= 0) {
      errors.add(
        '$prefix.springRateNPerMm must be > 0 (got ${s.springRateNPerMm}).',
      );
    }
    if (s.preloadMm < 0) {
      errors.add('$prefix.preloadMm must be >= 0 (got ${s.preloadMm}).');
    }
    if (s.type == SpringType.dualRate) {
      if (s.dualRateBreakpointMm <= 0) {
        errors.add(
          '$prefix.dualRateBreakpointMm must be > 0 for dualRate spring '
          '(got ${s.dualRateBreakpointMm}).',
        );
      }
      if (s.secondarySpringRateNPerMm <= 0) {
        errors.add(
          '$prefix.secondarySpringRateNPerMm must be > 0 for dualRate spring '
          '(got ${s.secondarySpringRateNPerMm}).',
        );
      }
    }
  }

  // ── Damping clicks ──────────────────────────────────────────────────────────

  static void _validateDampingClicks(
    DampingClicksConfig d,
    String prefix,
    List<String> errors,
  ) {
    _checkClickRange(
      d.compressionLowSpeedClicks,
      '$prefix.compressionLowSpeedClicks',
      errors,
    );
    _checkClickRange(
      d.compressionHighSpeedClicks,
      '$prefix.compressionHighSpeedClicks',
      errors,
    );
    _checkClickRange(
      d.reboundLowSpeedClicks,
      '$prefix.reboundLowSpeedClicks',
      errors,
    );
    _checkClickRange(
      d.reboundHighSpeedClicks,
      '$prefix.reboundHighSpeedClicks',
      errors,
    );
  }

  static void _checkClickRange(
    double clicks,
    String fieldName,
    List<String> errors,
  ) {
    if (clicks < DampingClicksConfig.kMinClicks) {
      errors.add(
        '$fieldName must be >= ${DampingClicksConfig.kMinClicks} '
        '(got $clicks).',
      );
    }
    if (clicks > DampingClicksConfig.kMaxClicks) {
      errors.add(
        '$fieldName must be <= ${DampingClicksConfig.kMaxClicks} '
        '(got $clicks).',
      );
    }
  }

  // ── Front geometry ──────────────────────────────────────────────────────────

  static void _validateFrontGeometry(
    SuspensionConfig config,
    List<String> errors,
  ) {
    final g = config.front.geometry;
    if (g.wheelTravelMaxMm <= 0) {
      errors.add(
        'front.geometry.wheelTravelMaxMm must be > 0 '
        '(got ${g.wheelTravelMaxMm}).',
      );
    }
    if (g.unsprungMassKg < 0) {
      errors.add(
        'front.geometry.unsprungMassKg must be >= 0 '
        '(got ${g.unsprungMassKg}).',
      );
    }
    if (g.rakeDeg < 0 || g.rakeDeg > 90) {
      errors.add(
        'front.geometry.rakeDeg must be in [0, 90] degrees '
        '(got ${g.rakeDeg}).',
      );
    }
    if (g.trailMm < 0) {
      errors.add(
        'front.geometry.trailMm must be >= 0 (got ${g.trailMm}).',
      );
    }
  }

  // ── Rear geometry ───────────────────────────────────────────────────────────

  static void _validateRearGeometry(
    SuspensionConfig config,
    List<String> errors,
  ) {
    final g = config.rear.geometry;
    if (g.wheelTravelMaxMm <= 0) {
      errors.add(
        'rear.geometry.wheelTravelMaxMm must be > 0 '
        '(got ${g.wheelTravelMaxMm}).',
      );
    }
    if (g.unsprungMassKg < 0) {
      errors.add(
        'rear.geometry.unsprungMassKg must be >= 0 '
        '(got ${g.unsprungMassKg}).',
      );
    }
    if (g.leverRatio <= 0) {
      errors.add(
        'rear.geometry.leverRatio must be > 0 (got ${g.leverRatio}).',
      );
    }
  }

  // ── Linkage ─────────────────────────────────────────────────────────────────

  static void _validateLinkage(LinkageConfig l, List<String> errors) {
    if (l.wheelTravelMaxMm <= 0) {
      errors.add(
        'rear.linkage.wheelTravelMaxMm must be > 0 '
        '(got ${l.wheelTravelMaxMm}).',
      );
    }
    switch (l.type) {
      case LinkageType.constant:
        if (l.constantRatio <= 0) {
          errors.add(
            'rear.linkage.constantRatio must be > 0 '
            '(got ${l.constantRatio}).',
          );
        }
      case LinkageType.progressive:
        if (l.r0 <= 0) {
          errors.add(
            'rear.linkage.r0 must be > 0 for progressive linkage '
            '(got ${l.r0}).',
          );
        }
      case LinkageType.lookupTable:
        if (l.travelPoints.length < 2) {
          errors.add(
            'rear.linkage travelPoints must have at least 2 entries for '
            'lookupTable linkage (got ${l.travelPoints.length}).',
          );
        }
        if (l.ratioPoints.length != l.travelPoints.length) {
          errors.add(
            'rear.linkage ratioPoints length (${l.ratioPoints.length}) must '
            'match travelPoints length (${l.travelPoints.length}).',
          );
        }
        if (l.travelPoints.length >= 2 &&
            l.ratioPoints.length == l.travelPoints.length) {
          for (var i = 1; i < l.travelPoints.length; i++) {
            final previous = l.travelPoints[i - 1];
            final current = l.travelPoints[i];
            if (current <= previous) {
              errors.add(
                'rear.linkage.travelPoints must be strictly ascending; '
                'travelPoints[$i] (= $current) must be > '
                'travelPoints[${i - 1}] (= $previous).',
              );
            }
          }
          for (var i = 0; i < l.ratioPoints.length; i++) {
            final ratio = l.ratioPoints[i];
            if (ratio <= 0) {
              errors.add(
                'rear.linkage.ratioPoints[$i] must be > 0 (got $ratio).',
              );
            }
          }
        }
    }
  }
}
