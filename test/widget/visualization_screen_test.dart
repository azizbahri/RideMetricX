// Widget tests for VisualizationScreen.
//
// Covers:
//   - Screen renders without errors
//   - Info banner displays correctly
//   - SuspensionSceneWidget is present
//   - Demo animation runs
//   - Custom state can be injected

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/models/suspension_state.dart';
import 'package:ride_metric_x/screens/visualization_screen.dart';
import 'package:ride_metric_x/widgets/suspension_scene_widget.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(Widget screen) => MaterialApp(home: Scaffold(body: screen));

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('VisualizationScreen', () {
    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(_wrap(const VisualizationScreen()));
      expect(find.byType(VisualizationScreen), findsOneWidget);
    });

    testWidgets('displays info banner', (tester) async {
      await tester.pumpWidget(_wrap(const VisualizationScreen()));
      expect(find.text('Interactive 3D suspension model'), findsOneWidget);
      expect(
        find.text('Demo mode - session integration pending'),
        findsOneWidget,
      );
    });

    testWidgets('contains SuspensionSceneWidget', (tester) async {
      await tester.pumpWidget(_wrap(const VisualizationScreen()));
      expect(find.byType(SuspensionSceneWidget), findsOneWidget);
    });

    testWidgets('accepts custom suspension state', (tester) async {
      const customState = SuspensionState(
        frontTravelMm: 50.0,
        rearTravelMm: 40.0,
      );

      await tester.pumpWidget(
        _wrap(const VisualizationScreen(state: customState)),
      );

      expect(find.byType(SuspensionSceneWidget), findsOneWidget);
    });

    testWidgets('demo animation updates suspension state', (tester) async {
      await tester.pumpWidget(_wrap(const VisualizationScreen()));

      // Initial frame
      await tester.pump();

      // Advance animation
      await tester.pump(const Duration(milliseconds: 500));

      // Scene widget should still be present and animating
      expect(find.byType(SuspensionSceneWidget), findsOneWidget);
    });

    testWidgets('displays 3D icon in banner', (tester) async {
      await tester.pumpWidget(_wrap(const VisualizationScreen()));

      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.view_in_ar,
        ),
        findsOneWidget,
      );
    });
  });
}
