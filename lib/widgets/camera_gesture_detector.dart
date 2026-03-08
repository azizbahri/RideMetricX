import 'package:flutter/material.dart';

import '../rendering/camera_controller.dart';
import '../rendering/camera_state.dart';

/// Widget that translates touch / mouse gestures into camera operations on
/// [controller] (FR-VZ-005).
///
/// ### Gesture mapping
/// | Gesture            | Mode            | Operation              |
/// |--------------------|-----------------|------------------------|
/// | Single-pointer drag| arcball / orbit | [CameraController.rotate] |
/// | Single-pointer drag| fixed           | [CameraController.pan]    |
/// | Two-finger pinch   | any             | [CameraController.zoom]   |
/// | Double-tap         | any             | [CameraController.reset]  |
///
/// [rotateSensitivity] and [panSensitivity] scale the raw pixel deltas before
/// they are forwarded to the controller.
class CameraGestureDetector extends StatefulWidget {
  const CameraGestureDetector({
    super.key,
    required this.controller,
    required this.child,
    this.rotateSensitivity = 0.01,
    this.panSensitivity = 1.0,
  }) : assert(rotateSensitivity > 0, 'rotateSensitivity must be positive'),
       assert(panSensitivity > 0, 'panSensitivity must be positive');

  /// The camera controller driven by the detected gestures.
  final CameraController controller;

  /// The widget subtree rendered inside the gesture-sensitive area.
  final Widget child;

  /// Multiplier applied to drag pixel deltas when rotating.
  final double rotateSensitivity;

  /// Multiplier applied to drag pixel deltas when panning.
  final double panSensitivity;

  @override
  State<CameraGestureDetector> createState() => _CameraGestureDetectorState();
}

class _CameraGestureDetectorState extends State<CameraGestureDetector> {
  // Tracks the scale factor from the previous onScaleUpdate callback so we can
  // derive a frame-to-frame delta rather than applying the cumulative scale.
  double _lastScale = 1.0;

  // Tracks the number of active pointers captured at scale-start so that
  // rotate/pan is suppressed during a multi-finger pinch gesture.
  int _pointerCount = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: _onDoubleTap,
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      child: widget.child,
    );
  }

  void _onDoubleTap() => widget.controller.reset();

  void _onScaleStart(ScaleStartDetails details) {
    _lastScale = 1.0;
    _pointerCount = details.pointerCount;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final mode = widget.controller.mode;

    // ── Rotate / pan from drag delta (single-pointer only) ───────────────────
    // During a multi-finger pinch the focal-point midpoint may drift, which
    // would cause unintended rotation/pan.  Guard to single-pointer drags only.
    if (_pointerCount == 1) {
      final dx = details.focalPointDelta.dx;
      final dy = details.focalPointDelta.dy;

      if (mode == CameraMode.fixed) {
        widget.controller.pan(
          dx * widget.panSensitivity,
          dy * widget.panSensitivity,
        );
      } else {
        // arcball / orbit: drag → rotate
        widget.controller.rotate(
          dx * widget.rotateSensitivity,
          dy * widget.rotateSensitivity,
        );
      }
    }

    // ── Pinch zoom ────────────────────────────────────────────────────────────
    final scale = details.scale;
    if (scale != _lastScale && scale > 0) {
      widget.controller.zoom(scale / _lastScale);
      _lastScale = scale;
    }
  }
}
