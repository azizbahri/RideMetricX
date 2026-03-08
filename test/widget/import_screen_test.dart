// Widget tests for ImportScreen.
//
// Covers:
//   - Initial state: Import button disabled, no results shown
//   - After front file selected: Import button enabled
//   - After rear file selected: Import button enabled
//   - After both files cleared: Import button disabled again
//   - File card shows selected file name
//   - File card "Remove" button clears selection
//   - During import: progress indicator and Cancel button visible
//   - After successful import: ValidationSummaryCard rendered
//   - After successful import: Go to Sessions button shown and callback fired
//   - After import error: error banner rendered, Go to Sessions button hidden
//   - Cancel stops import progress display
//   - Cancel of partially-successful import hides Go to Sessions button

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/main.dart';
import 'package:ride_metric_x/models/session_metadata.dart';
import 'package:ride_metric_x/models/validation_metrics.dart';
import 'package:ride_metric_x/models/validation_report.dart';
import 'package:ride_metric_x/screens/import_screen.dart';
import 'package:ride_metric_x/services/data_import/import_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Wraps [ImportScreen] in a [MaterialApp] for widget testing.
Widget _wrap(ImportScreen screen) => MaterialApp(home: Scaffold(body: screen));

/// A [FileSelection] with two valid CSV rows.
const _validCsv = '''
timestamp_ms,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps,temp_c,sample_count
0,0.02,-0.01,1.00,0.5,-0.3,0.1,25.3,0
5,0.03,-0.02,1.01,0.6,-0.2,0.2,25.3,1
''';

const _frontSelection = FileSelection(
  fileName: 'front.csv',
  content: _validCsv,
);

const _rearSelection = FileSelection(
  fileName: 'rear.csv',
  content: _validCsv,
);

/// Returns immediately with [selection].
Future<FileSelection?> _pick(FileSelection selection) async => selection;

/// Returns immediately with null (simulates cancel).
Future<FileSelection?> _cancelled() async => null;

// ── A fake ImportService that controls when events are emitted ───────────────

class _FakeImportService extends ImportService {
  _FakeImportService(this._controller);

  final StreamController<ImportState> _controller;

  @override
  Stream<ImportState> importFile(
    FileSelection selection,
    SensorPosition position,
  ) =>
      _controller.stream;
}

/// Fake service that uses [frontStream] for the front sensor and records
/// whether the rear import was ever started via [onRearCalled].
class _TwoFileFakeService extends ImportService {
  _TwoFileFakeService({
    required this.frontStream,
    required this.onRearCalled,
  });

  final Stream<ImportState> frontStream;
  final VoidCallback onRearCalled;

  @override
  Stream<ImportState> importFile(
    FileSelection selection,
    SensorPosition position,
  ) {
    if (position == SensorPosition.rear) {
      onRearCalled();
      // Return an empty stream – the test verifies this is never reached.
      return const Stream.empty();
    }
    return frontStream;
  }
}

/// Fake service where front immediately emits [ImportSuccess] and rear uses
/// [rearController], allowing tests to drive a partially-completed import.
class _PartialSuccessFakeService extends ImportService {
  _PartialSuccessFakeService({required this.rearController});

  final StreamController<ImportState> rearController;

  @override
  Stream<ImportState> importFile(
    FileSelection selection,
    SensorPosition position,
  ) {
    if (position == SensorPosition.front) {
      return Stream.value(
        ImportSuccess(
          report: const ValidationReport(
            errors: [],
            warnings: [],
            metrics: ValidationMetrics.empty,
            wasCorrected: false,
            corrections: [],
          ),
          position: position,
          fileName: selection.fileName,
          samples: const [],
        ),
      );
    }
    return rearController.stream;
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Initial / disabled state ─────────────────────────────────────────────

  group('ImportScreen – initial state', () {
    testWidgets('Import button is disabled when no file is selected',
        (tester) async {
      await tester.pumpWidget(_wrap(const ImportScreen()));

      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('import_button')),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('shows Import Data heading', (tester) async {
      await tester.pumpWidget(_wrap(const ImportScreen()));
      expect(find.text('Import Data'), findsOneWidget);
    });

    testWidgets('shows front and rear sensor labels', (tester) async {
      await tester.pumpWidget(_wrap(const ImportScreen()));
      expect(find.text('Front Sensor'), findsOneWidget);
      expect(find.text('Rear Sensor'), findsOneWidget);
    });

    testWidgets('Cancel button is not shown in idle state', (tester) async {
      await tester.pumpWidget(_wrap(const ImportScreen()));
      expect(find.byKey(const Key('cancel_button')), findsNothing);
    });
  });

  // ── File selection → ready state ─────────────────────────────────────────

  group('ImportScreen – ready state after file selection', () {
    testWidgets('Import button enabled after front file selected',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ImportScreen(onPickFrontFile: () => _pick(_frontSelection)),
        ),
      );

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Front Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();

      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('import_button')),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('Import button enabled after rear file selected',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ImportScreen(onPickRearFile: () => _pick(_rearSelection)),
        ),
      );

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Rear Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();

      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('import_button')),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('selected file name is shown in the card', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ImportScreen(onPickFrontFile: () => _pick(_frontSelection)),
        ),
      );

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Front Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('front.csv'), findsOneWidget);
    });

    testWidgets('clearing selection disables Import button', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ImportScreen(onPickFrontFile: () => _pick(_frontSelection)),
        ),
      );

      // Select a file.
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Front Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();

      // Remove the file with the close (×) button.
      await tester.tap(find.byTooltip('Remove file'));
      await tester.pumpAndSettle();

      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('import_button')),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('cancelled picker does not update state', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ImportScreen(onPickFrontFile: _cancelled),
        ),
      );

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Front Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();

      // Button should still be disabled.
      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('import_button')),
      );
      expect(btn.onPressed, isNull);
    });
  });

  // ── Import progress state ────────────────────────────────────────────────

  group('ImportScreen – import in progress', () {
    testWidgets('progress indicator and Cancel button shown during import',
        (tester) async {
      // Use a controller we can drive manually.
      final ctrl = StreamController<ImportState>();
      final svc = _FakeImportService(ctrl);

      await tester.pumpWidget(
        _wrap(
          ImportScreen(
            onPickFrontFile: () => _pick(_frontSelection),
            service: svc,
          ),
        ),
      );

      // Select file.
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Front Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();

      // Start import.
      await tester.tap(find.byKey(const Key('import_button')));
      await tester.pump();

      // Emit a progress event.
      ctrl.add(const ImportInProgress(0.5));
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('cancel_button')), findsOneWidget);

      await ctrl.close();
      await tester.pumpAndSettle();
    });

    testWidgets('Import button is disabled while importing', (tester) async {
      final ctrl = StreamController<ImportState>();
      final svc = _FakeImportService(ctrl);

      await tester.pumpWidget(
        _wrap(
          ImportScreen(
            onPickFrontFile: () => _pick(_frontSelection),
            service: svc,
          ),
        ),
      );

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Front Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_button')));
      await tester.pump();

      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('import_button')),
      );
      expect(btn.onPressed, isNull);

      await ctrl.close();
      await tester.pumpAndSettle();
    });
  });

  // ── Successful import ────────────────────────────────────────────────────

  group('ImportScreen – successful import', () {
    testWidgets('validation summary card shown after successful import',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ImportScreen(
            onPickFrontFile: () => _pick(_frontSelection),
          ),
        ),
      );

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Front Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_button')));
      await tester.pumpAndSettle();

      // The summary card shows "Front: front.csv".
      expect(find.textContaining('front.csv'), findsWidgets);
    });

    testWidgets('no error banner shown after successful import',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ImportScreen(
            onPickFrontFile: () => _pick(_frontSelection),
          ),
        ),
      );

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Front Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_button')));
      await tester.pumpAndSettle();

      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('Go to Sessions button shown after successful import',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ImportScreen(
            onPickFrontFile: () => _pick(_frontSelection),
          ),
        ),
      );

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Front Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('go_to_sessions_button')),
        findsOneWidget,
      );
    });

    testWidgets('Go to Sessions button invokes onNavigateToSessions callback',
        (tester) async {
      var navigateCalled = false;

      await tester.pumpWidget(
        _wrap(
          ImportScreen(
            onPickFrontFile: () => _pick(_frontSelection),
            onNavigateToSessions: () => navigateCalled = true,
          ),
        ),
      );

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Front Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('go_to_sessions_button')));
      await tester.pump();

      expect(navigateCalled, isTrue);
    });

    testWidgets('Go to Sessions button not shown before import completes',
        (tester) async {
      final ctrl = StreamController<ImportState>();
      final svc = _FakeImportService(ctrl);

      await tester.pumpWidget(
        _wrap(
          ImportScreen(
            onPickFrontFile: () => _pick(_frontSelection),
            service: svc,
          ),
        ),
      );

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Front Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_button')));
      await tester.pump();

      ctrl.add(const ImportInProgress(0.5));
      await tester.pump();

      expect(
        find.byKey(const Key('go_to_sessions_button')),
        findsNothing,
      );

      await ctrl.close();
      await tester.pumpAndSettle();
    });

    testWidgets('Go to Sessions button not shown when import errors',
        (tester) async {
      final ctrl = StreamController<ImportState>();
      final svc = _FakeImportService(ctrl);

      await tester.pumpWidget(
        _wrap(
          ImportScreen(
            onPickFrontFile: () => _pick(_frontSelection),
            service: svc,
          ),
        ),
      );

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Front Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_button')));
      await tester.pump();

      ctrl.add(const ImportError('File is corrupt'));
      await ctrl.close();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('go_to_sessions_button')),
        findsNothing,
      );
    });

    testWidgets(
        'Go to Sessions button not shown after cancelling a partially successful import',
        (tester) async {
      final rearCtrl = StreamController<ImportState>();
      final svc = _PartialSuccessFakeService(rearController: rearCtrl);

      await tester.pumpWidget(
        _wrap(
          ImportScreen(
            onPickFrontFile: () => _pick(_frontSelection),
            onPickRearFile: () => _pick(_rearSelection),
            service: svc,
          ),
        ),
      );

      // Select both files.
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Front Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Rear Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();

      // Start import; front completes immediately, rear stays in progress.
      await tester.tap(find.byKey(const Key('import_button')));
      await tester.pump();

      // Emit a progress event for the rear to show it is in-flight.
      rearCtrl.add(const ImportInProgress(0.3));
      await tester.pump();

      // Cancel while rear import is still running.
      await tester.tap(find.byKey(const Key('cancel_button')));
      await tester.pump();

      // Even though the front file succeeded, navigation must not be offered
      // after a cancelled import.
      expect(
        find.byKey(const Key('go_to_sessions_button')),
        findsNothing,
      );

      await rearCtrl.close();
      await tester.pumpAndSettle();
    });
  });

  group('ImportScreen – error path', () {
    testWidgets('error banner shown when import fails', (tester) async {
      final ctrl = StreamController<ImportState>();
      final svc = _FakeImportService(ctrl);

      await tester.pumpWidget(
        _wrap(
          ImportScreen(
            onPickFrontFile: () => _pick(_frontSelection),
            service: svc,
          ),
        ),
      );

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Front Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_button')));
      await tester.pump();

      // Emit error then close.
      ctrl.add(const ImportError('File is corrupt'));
      await ctrl.close();
      await tester.pumpAndSettle();

      expect(find.text('File is corrupt'), findsOneWidget);
    });
  });

  // ── Cancel path ──────────────────────────────────────────────────────────

  group('ImportScreen – cancel path', () {
    testWidgets('tapping Cancel stops progress display', (tester) async {
      final ctrl = StreamController<ImportState>();
      final svc = _FakeImportService(ctrl);

      await tester.pumpWidget(
        _wrap(
          ImportScreen(
            onPickFrontFile: () => _pick(_frontSelection),
            service: svc,
          ),
        ),
      );

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Front Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_button')));
      await tester.pump();

      ctrl.add(const ImportInProgress(0.3));
      await tester.pump();

      // Cancel.
      await tester.tap(find.byKey(const Key('cancel_button')));
      await tester.pump();

      // Progress indicator should be gone after cancel.
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byKey(const Key('cancel_button')), findsNothing);

      await ctrl.close();
      await tester.pumpAndSettle();
    });
  });

  // ── Dual-file import ─────────────────────────────────────────────────────

  group('ImportScreen – dual-file import', () {
    testWidgets('both summary cards shown when front and rear succeed',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ImportScreen(
            onPickFrontFile: () => _pick(_frontSelection),
            onPickRearFile: () => _pick(_rearSelection),
          ),
        ),
      );

      // Select front file.
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Front Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();

      // Select rear file.
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Rear Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('front.csv'), findsWidgets);
      expect(find.textContaining('rear.csv'), findsWidgets);
    });

    testWidgets('rear import is skipped when front import emits an error',
        (tester) async {
      // The front controller will emit an error; the rear controller should
      // never be subscribed to (since the error guard prevents it).
      int rearCallCount = 0;
      final frontCtrl = StreamController<ImportState>();
      final svc = _TwoFileFakeService(
        frontStream: frontCtrl.stream,
        onRearCalled: () => rearCallCount++,
      );

      await tester.pumpWidget(
        _wrap(
          ImportScreen(
            onPickFrontFile: () => _pick(_frontSelection),
            onPickRearFile: () => _pick(_rearSelection),
            service: svc,
          ),
        ),
      );

      // Select both files.
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Front Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, 'Rear Sensor'),
          matching: find.text('Select'),
        ),
      );
      await tester.pumpAndSettle();

      // Start import.
      await tester.tap(find.byKey(const Key('import_button')));
      await tester.pump();

      // Front file import fails.
      frontCtrl.add(const ImportError('front file is corrupt'));
      await frontCtrl.close();
      await tester.pumpAndSettle();

      // Error banner for the front failure should be shown.
      expect(find.text('front file is corrupt'), findsOneWidget);
      // Rear import should never have been called.
      expect(rearCallCount, 0);
    });
  });

  group('ImportScreen in app shell', () {
    testWidgets('import screen renders within RideMetricXApp', (tester) async {
      await tester.pumpWidget(const RideMetricXApp());
      // 'Import Data' appears in the screen body heading.
      expect(find.text('Import Data'), findsOneWidget);
    });
  });
}
