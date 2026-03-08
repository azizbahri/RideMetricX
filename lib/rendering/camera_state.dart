import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Camera operation modes for the 3D visualization viewport (FR-VZ-005).
enum CameraMode {
  /// Rotates freely around the focal point using arcball mechanics.
  arcball,

  /// Orbits around a fixed look-at target; elevation is clamped above horizon.
  orbit,

  /// Rotation is disabled; only pan and zoom are active.
  fixed,
}

/// Immutable snapshot of the camera's position, orientation and constraints
/// (FR-VZ-005).
///
/// All angles are in radians. [distance] is in the same world-space units as
/// the scene geometry.
///
/// Use [copyWith] to derive a new state with updated fields; constraints are
/// automatically re-applied on every [copyWith] call.
class CameraState {
  const CameraState({
    this.mode = CameraMode.orbit,
    this.azimuthRad = 0.0,
    this.elevationRad = math.pi / 6, // 30°
    this.distance = 5.0,
    this.panOffset = Offset.zero,
    this.minDistance = 0.5,
    this.maxDistance = 50.0,
    this.minElevationRad = -math.pi / 2 + 0.01,
    this.maxElevationRad = math.pi / 2 - 0.01,
  });

  /// Current camera mode.
  final CameraMode mode;

  /// Horizontal rotation angle (radians). Kept in the range [0, 2π).
  final double azimuthRad;

  /// Vertical tilt angle (radians).
  /// Clamped to [[minElevationRad], [maxElevationRad]].
  final double elevationRad;

  /// Distance from the focal point.
  /// Clamped to [[minDistance], [maxDistance]].
  final double distance;

  /// 2-D pan offset applied after the view transform (viewport units).
  final Offset panOffset;

  // ── Constraints ──────────────────────────────────────────────────────────────

  /// Minimum allowed [distance] (closest zoom).
  final double minDistance;

  /// Maximum allowed [distance] (farthest zoom).
  final double maxDistance;

  /// Minimum allowed [elevationRad] (furthest downward tilt).
  final double minElevationRad;

  /// Maximum allowed [elevationRad] (furthest upward tilt).
  final double maxElevationRad;

  // ── Default (reset) state ────────────────────────────────────────────────────

  /// The canonical default state that [CameraController.reset] restores to.
  static const CameraState defaults = CameraState();

  // ── Mutation ─────────────────────────────────────────────────────────────────

  /// Returns a new [CameraState] with the supplied fields replaced.
  ///
  /// All angle and distance fields are automatically constrained:
  /// - [azimuthRad] is wrapped into `[0, 2π)`.
  /// - [elevationRad] is clamped to `[minElevationRad, maxElevationRad]`.
  /// - [distance] is clamped to `[minDistance, maxDistance]`.
  CameraState copyWith({
    CameraMode? mode,
    double? azimuthRad,
    double? elevationRad,
    double? distance,
    Offset? panOffset,
    double? minDistance,
    double? maxDistance,
    double? minElevationRad,
    double? maxElevationRad,
  }) {
    final newMinDist = minDistance ?? this.minDistance;
    final newMaxDist = maxDistance ?? this.maxDistance;
    final newMinEl = minElevationRad ?? this.minElevationRad;
    final newMaxEl = maxElevationRad ?? this.maxElevationRad;

    final rawAz = azimuthRad ?? this.azimuthRad;
    final rawEl = elevationRad ?? this.elevationRad;
    final rawDist = distance ?? this.distance;

    return CameraState(
      mode: mode ?? this.mode,
      azimuthRad: _wrapAngle(rawAz),
      elevationRad: rawEl.clamp(newMinEl, newMaxEl),
      distance: rawDist.clamp(newMinDist, newMaxDist),
      panOffset: panOffset ?? this.panOffset,
      minDistance: newMinDist,
      maxDistance: newMaxDist,
      minElevationRad: newMinEl,
      maxElevationRad: newMaxEl,
    );
  }

  /// Wraps [angle] into the range `[0, 2π)`.
  static double _wrapAngle(double angle) {
    const twoPi = 2 * math.pi;
    return ((angle % twoPi) + twoPi) % twoPi;
  }

  // ── Equality ─────────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraState &&
          other.mode == mode &&
          other.azimuthRad == azimuthRad &&
          other.elevationRad == elevationRad &&
          other.distance == distance &&
          other.panOffset == panOffset &&
          other.minDistance == minDistance &&
          other.maxDistance == maxDistance &&
          other.minElevationRad == minElevationRad &&
          other.maxElevationRad == maxElevationRad;

  @override
  int get hashCode => Object.hash(
        mode,
        azimuthRad,
        elevationRad,
        distance,
        panOffset,
        minDistance,
        maxDistance,
        minElevationRad,
        maxElevationRad,
      );

  @override
  String toString() => 'CameraState('
      'mode: $mode, '
      'azimuth: ${azimuthRad.toStringAsFixed(4)} rad, '
      'elevation: ${elevationRad.toStringAsFixed(4)} rad, '
      'distance: $distance, '
      'pan: $panOffset'
      ')';
}
