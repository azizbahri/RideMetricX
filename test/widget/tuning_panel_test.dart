// Widget tests for the TuningScreen (FR-UI-005).
//
// Covers:
//  • Slider and dropdown rendering
//  • Preset selection updates parameter values
//  • Reset action restores default parameters
//  • Run button disabled while simulation is running
//  • UI remains responsive during an async simulation run
//  • Debounced trigger: slider change schedules a run

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/models/suspension_parameters.dart';
import 'package:ride_metric_x/screens/tuning_screen.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Wraps [child] in a minimal [MaterialApp] so that [Theme] etc. are available.
Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Pumps a [TuningScreen] with an optional [simulationRunner] and
/// [debounceDuration].
Future<void> _pumpTuning(
  WidgetTester tester, {
  Future<void> Function(TuningParameters)? simulationRunner,
  Duration debounceDuration = Duration.zero,
}) async {
  await tester.pumpWidget(
    _wrap(
      TuningScreen(
        simulationRunner: simulationRunner,
        debounceDuration: debounceDuration,
      ),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Rendering ──────────────────────────────────────────────────────────────
  group('TuningScreen rendering', () {
    testWidgets('renders all four front-suspension sliders',
        (WidgetTester tester) async {
      await _pumpTuning(tester);

      expect(find.byKey(TuningScreen.frontSpringRateKey), findsOneWidget);
      expect(find.byKey(TuningScreen.frontCompressionKey), findsOneWidget);
      expect(find.byKey(TuningScreen.frontReboundKey), findsOneWidget);
      expect(find.byKey(TuningScreen.frontPreloadKey), findsOneWidget);
    });

    testWidgets('renders all four rear-suspension sliders',
        (WidgetTester tester) async {
      await _pumpTuning(tester);

      expect(find.byKey(TuningScreen.rearSpringRateKey), findsOneWidget);
      expect(find.byKey(TuningScreen.rearCompressionKey), findsOneWidget);
      expect(find.byKey(TuningScreen.rearReboundKey), findsOneWidget);
      expect(find.byKey(TuningScreen.rearPreloadKey), findsOneWidget);
    });

    testWidgets('renders preset dropdown', (WidgetTester tester) async {
      await _pumpTuning(tester);

      expect(find.byKey(TuningScreen.presetDropdownKey), findsOneWidget);
    });

    testWidgets('renders reset and run buttons', (WidgetTester tester) async {
      await _pumpTuning(tester);

      expect(find.byKey(TuningScreen.resetButtonKey), findsOneWidget);
      expect(find.byKey(TuningScreen.runButtonKey), findsOneWidget);
    });

    testWidgets('shows "Front Suspension" and "Rear Suspension" section titles',
        (WidgetTester tester) async {
      await _pumpTuning(tester);

      expect(find.text('Front Suspension'), findsOneWidget);
      expect(find.text('Rear Suspension'), findsOneWidget);
    });

    testWidgets('preset dropdown shows Soft, Default, and Firm options',
        (WidgetTester tester) async {
      await _pumpTuning(tester);

      // Open the dropdown.
      await tester.tap(find.byKey(TuningScreen.presetDropdownKey));
      await tester.pumpAndSettle();

      expect(find.text('Soft'), findsWidgets);
      expect(find.text('Default'), findsWidgets);
      expect(find.text('Firm'), findsWidgets);
    });

    testWidgets('run button label is "Run Simulation" when idle',
        (WidgetTester tester) async {
      await _pumpTuning(tester);

      expect(find.text('Run Simulation'), findsOneWidget);
    });
  });

  // ── Preset selection ───────────────────────────────────────────────────────
  group('Preset selection', () {
    testWidgets('selecting Soft preset updates front spring-rate display',
        (WidgetTester tester) async {
      await _pumpTuning(tester);

      await tester.tap(find.byKey(TuningScreen.presetDropdownKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DropdownMenuItem<String>),
          matching: find.text('Soft'),
        ),
      );
      await tester.pumpAndSettle();

      // Soft preset front spring rate is 15.0 N/mm.
      expect(
        find.text(
            '${TuningParameters.softPreset.front.springRate.toStringAsFixed(1)} N/mm'),
        findsOneWidget,
      );
    });

    testWidgets('selecting Firm preset updates rear spring-rate display',
        (WidgetTester tester) async {
      await _pumpTuning(tester);

      await tester.tap(find.byKey(TuningScreen.presetDropdownKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DropdownMenuItem<String>),
          matching: find.text('Firm'),
        ),
      );
      await tester.pumpAndSettle();

      // Firm preset rear spring rate is 45.0 N/mm.
      expect(
        find.text(
            '${TuningParameters.firmPreset.rear.springRate.toStringAsFixed(1)} N/mm'),
        findsOneWidget,
      );
    });

    testWidgets('selecting Default preset applies default values',
        (WidgetTester tester) async {
      await _pumpTuning(tester);

      // First switch to Soft.
      await tester.tap(find.byKey(TuningScreen.presetDropdownKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DropdownMenuItem<String>),
          matching: find.text('Soft'),
        ),
      );
      await tester.pumpAndSettle();

      // Then switch back to Default.
      await tester.tap(find.byKey(TuningScreen.presetDropdownKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DropdownMenuItem<String>),
          matching: find.text('Default'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
            '${TuningParameters.defaultPreset.front.springRate.toStringAsFixed(1)} N/mm'),
        findsOneWidget,
      );
    });
  });

  // ── Reset action ───────────────────────────────────────────────────────────
  group('Reset action', () {
    testWidgets('reset button restores Default preset values',
        (WidgetTester tester) async {
      await _pumpTuning(tester);

      // Switch to Firm.
      await tester.tap(find.byKey(TuningScreen.presetDropdownKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DropdownMenuItem<String>),
          matching: find.text('Firm'),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Reset.
      await tester.tap(find.byKey(TuningScreen.resetButtonKey));
      await tester.pumpAndSettle();

      // Front spring rate should be back to Default (25.0 N/mm).
      expect(
        find.text(
            '${TuningParameters.defaultPreset.front.springRate.toStringAsFixed(1)} N/mm'),
        findsOneWidget,
      );
    });

    testWidgets('reset triggers the simulation runner', (tester) async {
      int runCount = 0;
      await _pumpTuning(
        tester,
        simulationRunner: (_) async => runCount++,
      );

      await tester.tap(find.byKey(TuningScreen.resetButtonKey));
      await tester.pumpAndSettle();

      expect(runCount, 1);
    });
  });

  // ── Run button ─────────────────────────────────────────────────────────────
  group('Run button', () {
    testWidgets('tapping Run invokes the simulation runner',
        (WidgetTester tester) async {
      int runCount = 0;
      await _pumpTuning(
        tester,
        simulationRunner: (_) async => runCount++,
      );

      await tester.tap(find.byKey(TuningScreen.runButtonKey));
      await tester.pumpAndSettle();

      expect(runCount, 1);
    });

    testWidgets(
        'run button is disabled and shows "Running…" while simulation executes',
        (WidgetTester tester) async {
      final completer = Completer<void>();

      await _pumpTuning(
        tester,
        simulationRunner: (_) => completer.future,
      );

      // Start the simulation.
      // Two pumps are required: the first processes the tap and schedules the
      // zero-duration debounce timer; the second fires that timer so _execute()
      // runs and the state transitions to 'running'.
      await tester.tap(find.byKey(TuningScreen.runButtonKey));
      await tester
          .pump(); // process tap → schedules Timer(Duration.zero, _execute)
      await tester.pump(); // fire the timer → state becomes 'running' → rebuild

      // The button should now say "Running…" and be disabled.
      expect(find.text('Running…'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Running…'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);

      // Complete the simulation.
      completer.complete();
      await tester.pumpAndSettle();

      // Button returns to enabled.
      expect(find.text('Run Simulation'), findsOneWidget);
    });

    testWidgets('UI remains responsive (pumps frames) while sim runs',
        (WidgetTester tester) async {
      final completer = Completer<void>();
      await _pumpTuning(
        tester,
        simulationRunner: (_) => completer.future,
      );

      await tester.tap(find.byKey(TuningScreen.runButtonKey));
      await tester.pump();

      // The widget tree should still be valid mid-run (no exceptions).
      expect(tester.takeException(), isNull);

      // Tapping a slider while running does not throw.
      final slider = find.byKey(TuningScreen.frontSpringRateKey);
      // Drag the slider slightly — should not throw.
      await tester.drag(slider, const Offset(5.0, 0.0));
      await tester.pump();
      expect(tester.takeException(), isNull);

      completer.complete();
      await tester.pumpAndSettle();
    });
  });

  // ── Debounced trigger behaviour ────────────────────────────────────────────
  group('Debounced trigger', () {
    testWidgets('Run button tap debounces: single run after delay',
        (WidgetTester tester) async {
      int runCount = 0;
      await _pumpTuning(
        tester,
        simulationRunner: (_) async => runCount++,
        debounceDuration: const Duration(milliseconds: 300),
      );

      await tester.tap(find.byKey(TuningScreen.runButtonKey));

      // Before debounce elapses, simulation has not run.
      await tester.pump(const Duration(milliseconds: 299));
      expect(runCount, 0);

      // After debounce elapses and async call completes.
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(runCount, 1);
    });

    testWidgets('multiple rapid Run taps coalesce to a single run',
        (WidgetTester tester) async {
      int runCount = 0;
      await _pumpTuning(
        tester,
        simulationRunner: (_) async => runCount++,
        debounceDuration: const Duration(milliseconds: 300),
      );

      await tester.tap(find.byKey(TuningScreen.runButtonKey));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(TuningScreen.runButtonKey));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(TuningScreen.runButtonKey));

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(runCount, 1);
    });
  });
}
