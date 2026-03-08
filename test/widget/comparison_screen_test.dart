// Widget tests for ComparisonScreen and SnapshotRepository (FR-UI-007).
//
// Covers:
//  • Empty state when no snapshots exist
//  • Capture button adds a snapshot and updates the table
//  • Snapshot header and baseline chip rendering
//  • Delta metric visualisation (positive/negative/zero deltas)
//  • Comparison table renders all expected metric rows
//  • Multiple snapshots (3+) render side-by-side
//  • Clear all snapshots dialog and confirmation
//  • Snapshot save/restore consistency via TuningSnapshot.fromMap / toMap

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/models/suspension_parameters.dart';
import 'package:ride_metric_x/models/tuning_snapshot.dart';
import 'package:ride_metric_x/repositories/snapshot_repository.dart';
import 'package:ride_metric_x/screens/comparison_screen.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Pumps a [ComparisonScreen] with its own isolated [SnapshotRepository].
Future<SnapshotRepository> _pumpScreen(WidgetTester tester) async {
  final repo = SnapshotRepository();
  await tester.pumpWidget(_wrap(ComparisonScreen(repository: repo)));
  await tester.pump();
  return repo;
}

TuningSnapshot _makeSnapshot({
  String id = 'snap-1',
  String label = 'Snap 1',
  TuningParameters? parameters,
}) {
  return TuningSnapshot(
    id: id,
    label: label,
    createdAt: DateTime.utc(2025, 6, 1, 12, 0),
    parameters: parameters ?? TuningParameters.defaultPreset,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Empty state ─────────────────────────────────────────────────────────────
  group('ComparisonScreen empty state', () {
    testWidgets('shows empty state when no snapshots', (tester) async {
      await _pumpScreen(tester);

      expect(find.text('No snapshots yet'), findsOneWidget);
      expect(find.byKey(ComparisonScreen.snapshotTableKey), findsNothing);
    });

    testWidgets('capture button is always visible', (tester) async {
      await _pumpScreen(tester);

      expect(find.byKey(ComparisonScreen.captureButtonKey), findsOneWidget);
    });

    testWidgets('clear button is hidden when repository is empty',
        (tester) async {
      await _pumpScreen(tester);

      expect(find.byKey(ComparisonScreen.clearButtonKey), findsNothing);
    });
  });

  // ── Capture ──────────────────────────────────────────────────────────────────
  group('Snapshot capture', () {
    testWidgets('tapping capture button shows snackbar', (tester) async {
      await _pumpScreen(tester);

      await tester.tap(find.byKey(ComparisonScreen.captureButtonKey));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('tapping capture button shows the comparison table',
        (tester) async {
      await _pumpScreen(tester);

      await tester.tap(find.byKey(ComparisonScreen.captureButtonKey));
      await tester.pump();

      expect(find.byKey(ComparisonScreen.snapshotTableKey), findsOneWidget);
    });

    testWidgets('repository reflects captured snapshot', (tester) async {
      final repo = await _pumpScreen(tester);

      await tester.tap(find.byKey(ComparisonScreen.captureButtonKey));
      await tester.pump();

      expect(repo.length, 1);
    });
  });

  // ── Comparison table rendering ───────────────────────────────────────────────
  group('Comparison table rendering', () {
    testWidgets('table is visible after adding a snapshot via repository',
        (tester) async {
      final repo = SnapshotRepository()..add(_makeSnapshot());
      await tester.pumpWidget(_wrap(ComparisonScreen(repository: repo)));
      await tester.pump();

      expect(find.byKey(ComparisonScreen.snapshotTableKey), findsOneWidget);
    });

    testWidgets('snapshot label appears in the table header', (tester) async {
      final repo = SnapshotRepository()
        ..add(_makeSnapshot(label: 'My Setup'));
      await tester.pumpWidget(_wrap(ComparisonScreen(repository: repo)));
      await tester.pump();

      expect(find.text('My Setup'), findsOneWidget);
    });

    testWidgets('baseline chip is shown for the first snapshot', (tester) async {
      final repo = SnapshotRepository()..add(_makeSnapshot());
      await tester.pumpWidget(_wrap(ComparisonScreen(repository: repo)));
      await tester.pump();

      expect(find.text('baseline'), findsOneWidget);
    });

    testWidgets('metric labels appear in the table', (tester) async {
      final repo = SnapshotRepository()..add(_makeSnapshot());
      await tester.pumpWidget(_wrap(ComparisonScreen(repository: repo)));
      await tester.pump();

      expect(find.text('Front Spring Rate'), findsOneWidget);
      expect(find.text('Rear Spring Rate'), findsOneWidget);
      expect(find.text('Front Compression'), findsOneWidget);
      expect(find.text('Rear Compression'), findsOneWidget);
      expect(find.text('Front Rebound'), findsOneWidget);
      expect(find.text('Rear Rebound'), findsOneWidget);
      expect(find.text('Front Preload'), findsOneWidget);
      expect(find.text('Rear Preload'), findsOneWidget);
    });
  });

  // ── Multi-snapshot (3+) ───────────────────────────────────────────────────────
  group('Multi-snapshot comparison (3+ snapshots)', () {
    testWidgets('three snapshots all have their labels visible', (tester) async {
      final repo = SnapshotRepository()
        ..add(_makeSnapshot(id: 'a', label: 'Alpha'))
        ..add(_makeSnapshot(id: 'b', label: 'Beta'))
        ..add(_makeSnapshot(id: 'c', label: 'Gamma'));

      await tester.pumpWidget(_wrap(ComparisonScreen(repository: repo)));
      await tester.pump();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('Gamma'), findsOneWidget);
    });

    testWidgets('only first snapshot has baseline chip', (tester) async {
      final repo = SnapshotRepository()
        ..add(_makeSnapshot(id: 'a', label: 'Alpha'))
        ..add(_makeSnapshot(id: 'b', label: 'Beta'))
        ..add(_makeSnapshot(id: 'c', label: 'Gamma'));

      await tester.pumpWidget(_wrap(ComparisonScreen(repository: repo)));
      await tester.pump();

      // Only one baseline chip should appear.
      expect(find.text('baseline'), findsOneWidget);
    });

    testWidgets('clear button appears when snapshots are present', (tester) async {
      final repo = SnapshotRepository()
        ..add(_makeSnapshot(id: 'a'))
        ..add(_makeSnapshot(id: 'b'));

      await tester.pumpWidget(_wrap(ComparisonScreen(repository: repo)));
      await tester.pump();

      expect(find.byKey(ComparisonScreen.clearButtonKey), findsOneWidget);
    });
  });

  // ── Delta visualisation ───────────────────────────────────────────────────────
  group('Delta metric visualisation', () {
    testWidgets('positive delta shows + prefix', (tester) async {
      // Baseline: springRate=25. Comparison: springRate=40 → delta=+15.0
      final baseline = _makeSnapshot(
        id: 'base',
        label: 'Base',
        parameters: const TuningParameters(
          front: SuspensionParameters(
            springRate: 25.0,
            compression: 10.0,
            rebound: 10.0,
            preload: 5.0,
          ),
          rear: SuspensionParameters(
            springRate: 25.0,
            compression: 10.0,
            rebound: 10.0,
            preload: 5.0,
          ),
        ),
      );
      final comparison = _makeSnapshot(
        id: 'comp',
        label: 'Comp',
        parameters: const TuningParameters(
          front: SuspensionParameters(
            springRate: 40.0,
            compression: 10.0,
            rebound: 10.0,
            preload: 5.0,
          ),
          rear: SuspensionParameters(
            springRate: 25.0,
            compression: 10.0,
            rebound: 10.0,
            preload: 5.0,
          ),
        ),
      );

      final repo = SnapshotRepository()..add(baseline)..add(comparison);
      await tester.pumpWidget(_wrap(ComparisonScreen(repository: repo)));
      await tester.pump();

      // Positive delta string for front spring rate.
      expect(find.text('+15.0'), findsOneWidget);
    });

    testWidgets('negative delta shows - prefix without extra +', (tester) async {
      final baseline = _makeSnapshot(
        id: 'base',
        label: 'Base',
        parameters: const TuningParameters(
          front: SuspensionParameters(
            springRate: 40.0,
            compression: 10.0,
            rebound: 10.0,
            preload: 5.0,
          ),
          rear: SuspensionParameters(
            springRate: 40.0,
            compression: 10.0,
            rebound: 10.0,
            preload: 5.0,
          ),
        ),
      );
      final comparison = _makeSnapshot(
        id: 'comp',
        label: 'Comp',
        parameters: const TuningParameters(
          front: SuspensionParameters(
            springRate: 25.0,
            compression: 10.0,
            rebound: 10.0,
            preload: 5.0,
          ),
          rear: SuspensionParameters(
            springRate: 40.0,
            compression: 10.0,
            rebound: 10.0,
            preload: 5.0,
          ),
        ),
      );

      final repo = SnapshotRepository()..add(baseline)..add(comparison);
      await tester.pumpWidget(_wrap(ComparisonScreen(repository: repo)));
      await tester.pump();

      expect(find.text('-15.0'), findsOneWidget);
    });

    testWidgets('zero delta shows 0.0 without + or - prefix', (tester) async {
      final identical = const TuningParameters(
        front: SuspensionParameters(
          springRate: 30.0,
          compression: 12.0,
          rebound: 8.0,
          preload: 4.0,
        ),
        rear: SuspensionParameters(
          springRate: 30.0,
          compression: 12.0,
          rebound: 8.0,
          preload: 4.0,
        ),
      );

      final baseline = _makeSnapshot(
        id: 'base-zero',
        label: 'BaseZero',
        parameters: identical,
      );
      final comparison = _makeSnapshot(
        id: 'comp-zero',
        label: 'CompZero',
        parameters: identical,
      );

      final repo = SnapshotRepository()..add(baseline)..add(comparison);
      await tester.pumpWidget(_wrap(ComparisonScreen(repository: repo)));
      await tester.pump();

      // Zero delta should be rendered without a + or - prefix.
      expect(find.text('0.0'), findsWidgets);
      expect(find.text('+0.0'), findsNothing);
      expect(find.text('-0.0'), findsNothing);
    });
  });

  // ── Clear snapshots ───────────────────────────────────────────────────────────
  group('Clear snapshots', () {
    testWidgets('confirming clear removes all snapshots', (tester) async {
      final repo = SnapshotRepository()
        ..add(_makeSnapshot(id: 'a'))
        ..add(_makeSnapshot(id: 'b'));

      await tester.pumpWidget(_wrap(ComparisonScreen(repository: repo)));
      await tester.pump();

      // Tap clear button.
      await tester.tap(find.byKey(ComparisonScreen.clearButtonKey));
      await tester.pumpAndSettle();

      // Confirm in dialog.
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(repo.isEmpty, isTrue);
      expect(find.text('No snapshots yet'), findsOneWidget);
    });

    testWidgets('cancelling clear dialog keeps snapshots', (tester) async {
      final repo = SnapshotRepository()..add(_makeSnapshot(id: 'a'));

      await tester.pumpWidget(_wrap(ComparisonScreen(repository: repo)));
      await tester.pump();

      await tester.tap(find.byKey(ComparisonScreen.clearButtonKey));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repo.length, 1);
    });
  });

  // ── Snapshot save/restore consistency ────────────────────────────────────────
  group('Snapshot save/restore consistency', () {
    test('toMap → fromMap round-trip preserves all fields', () {
      const params = TuningParameters(
        front: SuspensionParameters(
          springRate: 22.5,
          compression: 8.0,
          rebound: 12.0,
          preload: 3.5,
        ),
        rear: SuspensionParameters(
          springRate: 28.0,
          compression: 9.0,
          rebound: 11.0,
          preload: 4.0,
        ),
      );

      final original = TuningSnapshot(
        id: 'test-id',
        label: 'Test Snapshot',
        createdAt: DateTime.utc(2025, 1, 15, 8, 30),
        parameters: params,
        notes: 'Rider notes here',
      );

      final restored = TuningSnapshot.fromMap(original.toMap());

      expect(restored.id, original.id);
      expect(restored.label, original.label);
      expect(restored.createdAt, original.createdAt);
      expect(restored.notes, original.notes);
      expect(restored.frontSpringRate, original.frontSpringRate);
      expect(restored.frontCompression, original.frontCompression);
      expect(restored.frontRebound, original.frontRebound);
      expect(restored.frontPreload, original.frontPreload);
      expect(restored.rearSpringRate, original.rearSpringRate);
      expect(restored.rearCompression, original.rearCompression);
      expect(restored.rearRebound, original.rearRebound);
      expect(restored.rearPreload, original.rearPreload);
    });

    test('toMap produces expected keys', () {
      final snap = _makeSnapshot();
      final map = snap.toMap();

      expect(map.containsKey('id'), isTrue);
      expect(map.containsKey('label'), isTrue);
      expect(map.containsKey('created_at'), isTrue);
      expect(map.containsKey('notes'), isTrue);
      expect(map.containsKey('front_spring_rate'), isTrue);
      expect(map.containsKey('front_compression'), isTrue);
      expect(map.containsKey('front_rebound'), isTrue);
      expect(map.containsKey('front_preload'), isTrue);
      expect(map.containsKey('rear_spring_rate'), isTrue);
      expect(map.containsKey('rear_compression'), isTrue);
      expect(map.containsKey('rear_rebound'), isTrue);
      expect(map.containsKey('rear_preload'), isTrue);
    });

    test('fromMap with missing notes field defaults to empty string', () {
      final map = _makeSnapshot().toMap()..remove('notes');
      final snap = TuningSnapshot.fromMap(map);
      expect(snap.notes, '');
    });
  });

  // ── SnapshotRepository ────────────────────────────────────────────────────────
  group('SnapshotRepository', () {
    test('add increases length and notifies listeners', () {
      final repo = SnapshotRepository();
      var notified = false;
      repo.addListener(() => notified = true);

      repo.add(_makeSnapshot());

      expect(repo.length, 1);
      expect(notified, isTrue);
    });

    test('add with duplicate id replaces existing snapshot', () {
      final repo = SnapshotRepository();
      repo.add(_makeSnapshot(id: 'x', label: 'Old'));
      repo.add(_makeSnapshot(id: 'x', label: 'New'));

      expect(repo.length, 1);
      expect(repo.snapshots.first.label, 'New');
    });

    test('remove decreases length and notifies listeners', () {
      final repo = SnapshotRepository()..add(_makeSnapshot(id: 'del'));
      var notified = false;
      repo.addListener(() => notified = true);

      repo.remove('del');

      expect(repo.isEmpty, isTrue);
      expect(notified, isTrue);
    });

    test('remove unknown id is a no-op', () {
      final repo = SnapshotRepository()..add(_makeSnapshot(id: 'a'));
      var notified = false;
      repo.addListener(() => notified = true);

      repo.remove('nonexistent');

      expect(repo.length, 1);
      expect(notified, isFalse);
    });

    test('clear empties the repository and notifies', () {
      final repo = SnapshotRepository()
        ..add(_makeSnapshot(id: 'a'))
        ..add(_makeSnapshot(id: 'b'));
      var notified = false;
      repo.addListener(() => notified = true);

      repo.clear();

      expect(repo.isEmpty, isTrue);
      expect(notified, isTrue);
    });

    test('clear on empty repository does not notify', () {
      final repo = SnapshotRepository();
      var notified = false;
      repo.addListener(() => notified = true);

      repo.clear();

      expect(notified, isFalse);
    });

    test('findById returns correct snapshot', () {
      final snap = _makeSnapshot(id: 'target');
      final repo = SnapshotRepository()..add(snap);

      expect(repo.findById('target'), snap);
    });

    test('findById returns null when not found', () {
      final repo = SnapshotRepository();
      expect(repo.findById('missing'), isNull);
    });
  });
}
