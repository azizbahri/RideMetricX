import 'package:flutter/material.dart';

/// Callback invoked on every animation tick with the current animation value
/// (0.0–1.0 within each cycle).
typedef FrameCallback = void Function(double value);

/// Core visualization rendering widget (FR-VZ-001).
///
/// Responsibilities:
/// - Owns a repeating [AnimationController] at [targetFps] to drive the frame
///   loop (default 60 fps).
/// - Wraps the render surface in a [RepaintBoundary] to isolate canvas repaints
///   from the rest of the widget tree.
/// - Drives a [VisualizationFramePainter] that short-circuits redundant canvas
///   redraws through its [VisualizationFramePainter.shouldRepaint] guard.
///
/// Downstream painters for 3D geometry (FR-VZ-002) and telemetry charts
/// (FR-VZ-003) should extend or compose [VisualizationFramePainter].
class VisualizationWidget extends StatefulWidget {
  const VisualizationWidget({
    super.key,
    this.targetFps = 60,
    this.onFrame,
  });

  /// Target frame rate used to derive the animation-controller cycle duration
  /// (`1000 / targetFps` milliseconds per cycle).
  final int targetFps;

  /// Optional callback invoked once per animation tick.  Useful for tests and
  /// for driving external state from the frame loop without subclassing.
  final FrameCallback? onFrame;

  // ── Semantic keys for widget tests ────────────────────────────────────────
  static const Key canvasKey = Key('viz_canvas');

  @override
  State<VisualizationWidget> createState() => _VisualizationWidgetState();
}

// ── State ─────────────────────────────────────────────────────────────────────

class _VisualizationWidgetState extends State<VisualizationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: _cycleDuration(),
    )
      ..addListener(_onTick)
      ..repeat();
  }

  @override
  void didUpdateWidget(VisualizationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetFps != widget.targetFps) {
      _animationController
        ..stop()
        ..duration = _cycleDuration()
        ..repeat();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Duration _cycleDuration() =>
      Duration(milliseconds: (1000 / widget.targetFps).round());

  void _onTick() {
    widget.onFrame?.call(_animationController.value);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, _) => CustomPaint(
          key: VisualizationWidget.canvasKey,
          painter: VisualizationFramePainter(
            animationValue: _animationController.value,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────

/// [CustomPainter] for the visualization render surface (FR-VZ-001).
///
/// The [shouldRepaint] guard returns `true` only when [animationValue] has
/// changed, preventing redundant canvas redraws on frames where nothing has
/// moved.  Downstream painters should extend this class and override [paint]
/// and [shouldRepaint] accordingly.
class VisualizationFramePainter extends CustomPainter {
  const VisualizationFramePainter({required this.animationValue});

  /// Current animation tick value in the range 0.0–1.0.
  final double animationValue;

  @override
  void paint(Canvas canvas, Size size) {
    // Placeholder render surface.  Downstream painters (FR-VZ-002, FR-VZ-003)
    // add geometry here.
  }

  @override
  bool shouldRepaint(covariant VisualizationFramePainter oldDelegate) =>
      animationValue != oldDelegate.animationValue;
}
