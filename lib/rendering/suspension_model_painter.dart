import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/suspension_material.dart';
import '../models/suspension_state.dart';
import '../widgets/visualization_widget.dart';

/// Canvas-based pseudo-3D painter for the motorcycle suspension model
/// (FR-VZ-002, FR-VZ-003).
///
/// Extends [VisualizationFramePainter] and overrides [paint] to draw a
/// schematic side-view of the suspension using Canvas primitives.  The colour
/// of each animated component integrates [SuspensionMaterial.getStrainColor]
/// with the current compression ratio from [state], giving a real-time
/// green → red strain indication (FR-VZ-003).
///
/// Geometry is expressed in a normalised 0–1 coordinate space and mapped to
/// canvas pixels via [_toScreen] at paint time so the view auto-scales to any
/// widget size.
class SuspensionModelPainter extends VisualizationFramePainter {
  SuspensionModelPainter({
    required super.animation,
    required this.state,
    this.forkMaterial = SuspensionMaterial.aluminum,
    this.shockMaterial = SuspensionMaterial.aluminum,
    this.frameMaterial = SuspensionMaterial.carbon,
    this.strainMaterial = SuspensionMaterial.strainSensor,
  });

  /// Current suspension animation state driving geometry and colour.
  final SuspensionState state;

  /// Material for the front-fork tubes.
  final SuspensionMaterial forkMaterial;

  /// Material for the rear shock body.
  final SuspensionMaterial shockMaterial;

  /// Material for the main chassis frame.
  final SuspensionMaterial frameMaterial;

  /// Material used for strain-colour overlays on animated elements.
  final SuspensionMaterial strainMaterial;

  // ── Layout constants (normalised 0–1 space) ──────────────────────────────

  static const double _kWheelRadius = 0.10;
  static const double _kForkStroke = 0.025;
  static const double _kForkLowerExtra = 0.008;
  static const double _kShockStroke = 0.020;
  static const double _kFrameStroke = 0.018;

  // ── Paint ─────────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    _drawFrame(canvas, size);
    _drawFrontFork(canvas, size);
    _drawRearShock(canvas, size);
    _drawWheels(canvas, size);
  }

  // ── Chassis frame (FR-VZ-002) ─────────────────────────────────────────────

  void _drawFrame(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = frameMaterial.baseColor
      ..strokeWidth = _kFrameStroke * size.shortestSide
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Simplified truss: headstock → swingarm pivot → seat tube
    final headstock = _toScreen(size, 0.35, 0.35);
    final swingarmPivot = _toScreen(size, 0.65, 0.42);
    final seat = _toScreen(size, 0.65, 0.28);

    canvas.drawLine(headstock, swingarmPivot, paint);
    canvas.drawLine(swingarmPivot, seat, paint);
    canvas.drawLine(seat, headstock, paint);
  }

  // ── Front fork (FR-VZ-002) ────────────────────────────────────────────────

  void _drawFrontFork(Canvas canvas, Size size) {
    final ratio = state.frontCompressionRatio;

    // Strain-colour integration (FR-VZ-003)
    final tubeColor = strainMaterial.getStrainColor(ratio);

    final tubePaint = Paint()
      ..color = tubeColor
      ..strokeWidth = _kForkStroke * size.shortestSide
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Fork lowers painted in the fork material base colour (slightly thicker)
    final lowerPaint = Paint()
      ..color = forkMaterial.baseColor
      ..strokeWidth = (_kForkStroke + _kForkLowerExtra) * size.shortestSide
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const topNx = 0.33;
    const topNy = 0.30;
    const bottomBaseNy = 0.72;
    // Travel range: 15 % of canvas height
    final bottomNy = bottomBaseNy - ratio * 0.15;

    for (final offsetX in [-0.015, 0.015]) {
      // Upper tube (strain-coloured)
      canvas.drawLine(
        _toScreen(size, topNx + offsetX, topNy),
        _toScreen(size, topNx + offsetX, bottomNy - 0.05),
        tubePaint,
      );
      // Lower leg (fork material colour)
      canvas.drawLine(
        _toScreen(size, topNx + offsetX, bottomNy - 0.05),
        _toScreen(size, topNx + offsetX, bottomNy),
        lowerPaint,
      );
    }
  }

  // ── Rear shock (FR-VZ-002) ────────────────────────────────────────────────

  void _drawRearShock(Canvas canvas, Size size) {
    final ratio = state.rearCompressionRatio;

    // Strain-colour integration (FR-VZ-003)
    final shockColor = strainMaterial.getStrainColor(ratio);

    final shockPaint = Paint()
      ..color = shockColor
      ..strokeWidth = _kShockStroke * size.shortestSide
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Shock spans from frame mount (top) to swingarm pivot (bottom),
    // shortening on compression.
    const topNx = 0.63;
    const topNy = 0.30;
    const bottomNx = 0.70;
    const bottomBaseNy = 0.58;
    final bottomNy = bottomBaseNy - ratio * 0.10;

    canvas.drawLine(
      _toScreen(size, topNx, topNy),
      _toScreen(size, bottomNx, bottomNy),
      shockPaint,
    );

    // Piston-body highlight (shock material)
    final highlightPaint = Paint()
      ..color = shockMaterial.highlightColor
      ..strokeWidth = (_kShockStroke - 0.006) * size.shortestSide
      ..style = PaintingStyle.stroke;

    final midNy = (topNy + bottomNy) * 0.5;
    canvas.drawLine(
      _toScreen(size, topNx, topNy),
      _toScreen(size, bottomNx - 0.01, midNy),
      highlightPaint,
    );
  }

  // ── Wheels (FR-VZ-002) ────────────────────────────────────────────────────

  void _drawWheels(Canvas canvas, Size size) {
    final radius = _kWheelRadius * size.shortestSide;
    final frontRatio = state.frontCompressionRatio;
    final rearRatio = state.rearCompressionRatio;

    // Front wheel axle rises with compression
    _drawWheel(
      canvas,
      _toScreen(size, 0.33, 0.75 - frontRatio * 0.15),
      radius,
      state.wheelRotationRad,
    );

    // Rear wheel axle rises with compression
    _drawWheel(
      canvas,
      _toScreen(size, 0.72, 0.75 - rearRatio * 0.10),
      radius,
      state.wheelRotationRad,
    );
  }

  void _drawWheel(
    Canvas canvas,
    Offset center,
    double radius,
    double rotationRad,
  ) {
    // Tyre ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF424242)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.25,
    );

    // Hub
    canvas.drawCircle(
      center,
      radius * 0.15,
      Paint()
        ..color = SuspensionMaterial.aluminum.baseColor
        ..style = PaintingStyle.fill,
    );

    // Rotating spokes
    const spokeCount = 6;
    final spokePaint = Paint()
      ..color = SuspensionMaterial.aluminum.shadowColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < spokeCount; i++) {
      final angle = rotationRad + (i * math.pi * 2 / spokeCount);
      canvas.drawLine(
        center,
        Offset(
          center.dx + radius * 0.85 * math.cos(angle),
          center.dy + radius * 0.85 * math.sin(angle),
        ),
        spokePaint,
      );
    }
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  /// Maps normalised coordinates [nx], [ny] ∈ [0, 1] to canvas pixels.
  Offset _toScreen(Size size, double nx, double ny) =>
      Offset(nx * size.width, ny * size.height);

  // ── shouldRepaint ─────────────────────────────────────────────────────────

  @override
  bool shouldRepaint(covariant SuspensionModelPainter oldDelegate) {
    return super.shouldRepaint(oldDelegate) ||
        state != oldDelegate.state ||
        forkMaterial != oldDelegate.forkMaterial ||
        shockMaterial != oldDelegate.shockMaterial ||
        frameMaterial != oldDelegate.frameMaterial ||
        strainMaterial != oldDelegate.strainMaterial;
  }
}
