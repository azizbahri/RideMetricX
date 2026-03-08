import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'camera_state.dart';

/// Stateful controller that maps user gestures to [CameraState] transitions
/// (FR-VZ-005).
///
/// Notifies listeners whenever the camera state changes so that downstream
/// painters can schedule a repaint.
///
/// ### Gesture semantics
/// | Gesture | Mode | Effect |
/// |---------|------|--------|
/// | Drag    | arcball / orbit | [rotate] |
/// | Drag    | fixed           | [pan]    |
/// | Pinch   | any             | [zoom]   |
/// | Reset   | any             | [reset]  |
class CameraController extends ChangeNotifier {
  /// Creates a controller with [initialState] (defaults to
  /// [CameraState.defaults] when omitted).
  CameraController({CameraState? initialState})
      : _state = initialState ?? CameraState.defaults,
        _resetState = initialState ?? CameraState.defaults;

  CameraState _state;

  /// The state that [reset] restores to (set at construction time).
  final CameraState _resetState;

  // ── Accessors ─────────────────────────────────────────────────────────────────

  /// Current camera state.
  CameraState get state => _state;

  /// Shorthand for [state.mode].
  CameraMode get mode => _state.mode;

  // ── Mode ──────────────────────────────────────────────────────────────────────

  /// Switches to [mode], preserving all other state fields.
  ///
  /// No-op when [mode] equals the current mode.
  void setMode(CameraMode mode) {
    if (_state.mode == mode) return;
    _state = _state.copyWith(mode: mode);
    notifyListeners();
  }

  // ── Gestures ──────────────────────────────────────────────────────────────────

  /// Rotates the camera by [dAzimuthRad] (horizontal) and [dElevationRad]
  /// (vertical).
  ///
  /// Constraints ([CameraState.minElevationRad]/[CameraState.maxElevationRad]
  /// and azimuth wrap) are enforced by [CameraState.copyWith].
  ///
  /// No-op in [CameraMode.fixed].
  void rotate(double dAzimuthRad, double dElevationRad) {
    if (_state.mode == CameraMode.fixed) return;
    _state = _state.copyWith(
      azimuthRad: _state.azimuthRad + dAzimuthRad,
      elevationRad: _state.elevationRad + dElevationRad,
    );
    notifyListeners();
  }

  /// Pans the camera viewport by ([dx], [dy]) in screen units.
  void pan(double dx, double dy) {
    _state = _state.copyWith(
      panOffset: _state.panOffset + Offset(dx, dy),
    );
    notifyListeners();
  }

  /// Zooms by multiplying the current distance by `1 / scaleFactor`.
  ///
  /// A [scaleFactor] > 1 moves the camera closer (zoom in); < 1 moves it
  /// farther (zoom out). [CameraState.minDistance] and
  /// [CameraState.maxDistance] are enforced by [CameraState.copyWith].
  ///
  /// Non-positive [scaleFactor] values are silently ignored.
  void zoom(double scaleFactor) {
    if (scaleFactor <= 0) return;
    _state = _state.copyWith(distance: _state.distance / scaleFactor);
    notifyListeners();
  }

  /// Resets the camera to the state supplied at construction time.
  void reset() {
    _state = _resetState;
    notifyListeners();
  }
}
