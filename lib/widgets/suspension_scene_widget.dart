import 'package:flutter/material.dart';

import '../models/suspension_material.dart';
import '../models/suspension_state.dart';
import '../rendering/scene_node.dart';
import '../rendering/suspension_model_painter.dart';
import 'visualization_widget.dart';

/// Top-level widget for the animated 3D suspension scene (FR-VZ-002,
/// FR-VZ-003, FR-VZ-004).
///
/// Owns an [AnimationController] frame loop (default 60 fps), a
/// [SuspensionSceneGraph] transform hierarchy, and a
/// [SuspensionModelPainter] that renders the scene each frame via
/// [CustomPaint] inside a [RepaintBoundary].
///
/// [state] drives both the scene-graph transforms and the painter geometry.
/// Supply a new [SuspensionState] to animate compression/extension in real
/// time.
///
/// Usage:
/// ```dart
/// SuspensionSceneWidget(
///   state: SuspensionState(
///     frontTravelMm: 50.0,
///     rearTravelMm: 30.0,
///     wheelRotationRad: math.pi / 4,
///   ),
/// )
/// ```
class SuspensionSceneWidget extends StatefulWidget {
  const SuspensionSceneWidget({
    super.key,
    this.state = const SuspensionState(),
    this.targetFps = 60,
    this.forkMaterial = SuspensionMaterial.aluminum,
    this.shockMaterial = SuspensionMaterial.aluminum,
    this.frameMaterial = SuspensionMaterial.carbon,
    this.strainMaterial = SuspensionMaterial.strainSensor,
    this.onFrame,
  });

  /// Current suspension animation state.
  final SuspensionState state;

  /// Target frame rate for the animation loop (must be > 0).
  final int targetFps;

  /// Material for the front-fork tubes.
  final SuspensionMaterial forkMaterial;

  /// Material for the rear shock body.
  final SuspensionMaterial shockMaterial;

  /// Material for the chassis frame members.
  final SuspensionMaterial frameMaterial;

  /// Material providing strain-colour integration for animated elements.
  final SuspensionMaterial strainMaterial;

  /// Optional frame callback forwarded on every animation tick.
  final FrameCallback? onFrame;

  // ── Semantic keys for widget tests ────────────────────────────────────────

  static const Key sceneKey = Key('suspension_scene');

  @override
  State<SuspensionSceneWidget> createState() => _SuspensionSceneWidgetState();
}

// ── State ──────────────────────────────────────────────────────────────────────

class _SuspensionSceneWidgetState extends State<SuspensionSceneWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late SuspensionSceneGraph _sceneGraph;
  late SuspensionModelPainter _painter;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: _cycleDuration(),
    )
      ..addListener(_onTick)
      ..repeat();
    _sceneGraph = SuspensionSceneGraph();
    _painter = _buildPainter();
  }

  @override
  void didUpdateWidget(SuspensionSceneWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetFps != widget.targetFps) {
      _animationController
        ..stop()
        ..duration = _cycleDuration()
        ..repeat();
    }
    if (oldWidget.state != widget.state ||
        oldWidget.forkMaterial != widget.forkMaterial ||
        oldWidget.shockMaterial != widget.shockMaterial ||
        oldWidget.frameMaterial != widget.frameMaterial ||
        oldWidget.strainMaterial != widget.strainMaterial) {
      _painter = _buildPainter();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// Derives the [AnimationController] cycle duration from [targetFps].
  ///
  /// Throws [ArgumentError] for non-positive values.
  Duration _cycleDuration() {
    if (widget.targetFps <= 0) {
      throw ArgumentError.value(
        widget.targetFps,
        'targetFps',
        'must be a positive integer',
      );
    }
    return Duration(microseconds: (1e6 / widget.targetFps).round());
  }

  void _onTick() => widget.onFrame?.call(_animationController.value);

  /// Synchronises [_sceneGraph] and constructs a fresh [SuspensionModelPainter]
  /// from the current widget configuration.
  SuspensionModelPainter _buildPainter() {
    _sceneGraph.updateState(
      frontTravelMm: widget.state.frontTravelMm,
      rearTravelMm: widget.state.rearTravelMm,
      wheelRotationRad: widget.state.wheelRotationRad,
    );
    return SuspensionModelPainter(
      animation: _animationController,
      state: widget.state,
      sceneGraph: _sceneGraph,
      forkMaterial: widget.forkMaterial,
      shockMaterial: widget.shockMaterial,
      frameMaterial: widget.frameMaterial,
      strainMaterial: widget.strainMaterial,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        key: SuspensionSceneWidget.sceneKey,
        painter: _painter,
        child: const SizedBox.expand(),
      ),
    );
  }
}
