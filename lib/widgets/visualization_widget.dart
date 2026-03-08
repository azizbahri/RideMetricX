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
/// - Drives a [VisualizationFramePainter] that registers itself as a repaint
///   listener on the animation controller, triggering canvas repaints directly
///   on the render object without rebuilding the widget tree.
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
  /// (`1_000_000 / targetFps` microseconds per cycle).
  ///
  /// Must be a positive integer; throws [ArgumentError] otherwise.
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
  late VisualizationFramePainter _painter;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: _cycleDuration(),
    )
      ..addListener(_onTick)
      ..repeat();
    _painter = VisualizationFramePainter(animation: _animationController);
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

  /// Returns the per-cycle [Duration] for [widget.targetFps].
  ///
  /// Throws [ArgumentError] when [VisualizationWidget.targetFps] is not a
  /// positive integer, preventing a division-by-zero or [Duration.zero] being
  /// passed to [AnimationController].
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

  void _onTick() {
    widget.onFrame?.call(_animationController.value);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        key: VisualizationWidget.canvasKey,
        painter: _painter,
        child: const SizedBox.expand(),
      ),
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────

/// [CustomPainter] for the visualization render surface (FR-VZ-001).
///
/// Registers [animation] as its repaint listenable so that the render object
/// repaints on every animation tick without rebuilding the widget tree.
/// [animationValue] reads the current tick value directly from [animation]
/// on every [paint] call.
///
/// [shouldRepaint] returns `true` only when the underlying [animation]
/// reference changes (e.g. the controller is replaced), preventing full
/// repaint on widget rebuilds that do not alter the animation source.
/// Animation-driven repaints bypass [shouldRepaint] and go directly to
/// [paint] via `markNeedsPaint`.
///
/// Downstream painters should extend this class and override [paint] and
/// [shouldRepaint] accordingly.
class VisualizationFramePainter extends CustomPainter {
  VisualizationFramePainter({required Animation<double> animation})
      : _animation = animation,
        super(repaint: animation);

  final Animation<double> _animation;

  /// Current animation tick value in the range 0.0–1.0, read fresh on every
  /// [paint] call via the underlying [Animation].
  double get animationValue => _animation.value;

  @override
  void paint(Canvas canvas, Size size) {
    // Placeholder render surface.  Downstream painters (FR-VZ-002, FR-VZ-003)
    // add geometry here.
  }

  @override
  bool shouldRepaint(covariant VisualizationFramePainter oldDelegate) =>
      _animation != oldDelegate._animation;
}
