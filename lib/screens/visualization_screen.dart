import 'package:flutter/material.dart';

import '../models/suspension_state.dart';
import '../widgets/suspension_scene_widget.dart';

/// Dedicated visualization screen displaying the 3D suspension scene
/// (FR-UI-004, FR-VZ-002).
///
/// Shows the animated motorcycle suspension model with camera controls.
/// Future enhancements can add camera mode toggles, playback controls,
/// and session data integration.
class VisualizationScreen extends StatefulWidget {
  const VisualizationScreen({super.key, this.state});

  /// Optional suspension state override for testing.
  /// When omitted, displays a demo animation with periodic compression/extension.
  final SuspensionState? state;

  @override
  State<VisualizationScreen> createState() => _VisualizationScreenState();
}

class _VisualizationScreenState extends State<VisualizationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _demoController;
  late Animation<double> _travelAnimation;

  @override
  void initState() {
    super.initState();
    _demoController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _travelAnimation = Tween<double>(begin: 0.0, end: 80.0).animate(
      CurvedAnimation(parent: _demoController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _demoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInfoBanner(context),
        Expanded(
          child: AnimatedBuilder(
            animation: _travelAnimation,
            builder: (context, _) {
              final state = widget.state ??
                  SuspensionState(
                    frontTravelMm: _travelAnimation.value,
                    rearTravelMm: _travelAnimation.value * 0.8,
                  );
              return SuspensionSceneWidget(state: state);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBanner(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.view_in_ar, size: 20, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Interactive 3D suspension model',
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ),
          Text(
            'Demo mode - session integration pending',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.outline,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
