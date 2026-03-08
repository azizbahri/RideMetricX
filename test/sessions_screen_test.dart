import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/models/session_metadata.dart';
import 'package:ride_metric_x/repositories/session_repository.dart';
import 'package:ride_metric_x/screens/sessions_screen.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

SessionMetadata _makeSession({
  String id = 'session-001',
  SensorPosition position = SensorPosition.front,
  DateTime? recordedAt,
  double samplingRateHz = 200.0,
  String? pairedSessionId,
}) {
  return SessionMetadata(
    sessionId: id,
    position: position,
    recordedAt: recordedAt ?? DateTime(2024, 6, 15, 10, 30),
    samplingRateHz: samplingRateHz,
    pairedSessionId: pairedSessionId,
  );
}

/// Pumps [SessionsScreen] inside a minimal [MaterialApp] + [Scaffold].
Future<void> pumpSessionsScreen(
  WidgetTester tester,
  SessionRepository repo,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SessionsScreen(repository: repo)),
    ),
  );
}

// ---------------------------------------------------------------------------
// Repository unit tests
// ---------------------------------------------------------------------------

void main() {
  group('SessionRepository', () {
    late SessionRepository repo;

    setUp(() => repo = SessionRepository());

    test('starts empty', () {
      expect(repo.sessions, isEmpty);
      expect(repo.isEmpty, isTrue);
    });

    test('add inserts session and notifies listeners', () {
      var notified = false;
      repo.addListener(() => notified = true);
      final session = _makeSession();

      repo.add(session);

      expect(repo.sessions, hasLength(1));
      expect(repo.isEmpty, isFalse);
      expect(notified, isTrue);
    });

    test('sessions list is unmodifiable', () {
      repo.add(_makeSession());
      expect(
        () =>
            (repo.sessions as List<SessionMetadata>).add(_makeSession(id: 'x')),
        throwsUnsupportedError,
      );
    });

    test('delete removes the correct session and notifies listeners', () {
      var notified = false;
      repo.add(_makeSession(id: 'a'));
      repo.add(_makeSession(id: 'b'));
      repo.addListener(() => notified = true);

      repo.delete('a');

      expect(repo.sessions, hasLength(1));
      expect(repo.sessions.first.sessionId, equals('b'));
      expect(notified, isTrue);
    });

    test('delete nonexistent ID is a no-op and does not notify', () {
      var notified = false;
      repo.add(_makeSession(id: 'a'));
      repo.addListener(() => notified = true);

      repo.delete('nonexistent');

      expect(repo.sessions, hasLength(1));
      expect(notified, isFalse);
    });

    test('findById returns the matching session', () {
      final s = _makeSession(id: 'target');
      repo.add(s);
      expect(repo.findById('target'), equals(s));
    });

    test('findById returns null when session is absent', () {
      expect(repo.findById('missing'), isNull);
    });

    test('delete then findById returns null', () {
      repo.add(_makeSession(id: 'x'));
      repo.delete('x');
      expect(repo.findById('x'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // SessionsScreen – empty state
  // ---------------------------------------------------------------------------

  group('SessionsScreen empty state', () {
    testWidgets('shows "No sessions yet" when repository is empty',
        (WidgetTester tester) async {
      final repo = SessionRepository();
      await pumpSessionsScreen(tester, repo);

      expect(find.text('No sessions yet'), findsOneWidget);
    });

    testWidgets('shows import hint subtitle when repository is empty',
        (WidgetTester tester) async {
      final repo = SessionRepository();
      await pumpSessionsScreen(tester, repo);

      expect(find.text('Import data to create a session'), findsOneWidget);
    });

    testWidgets('shows history icon in empty state',
        (WidgetTester tester) async {
      final repo = SessionRepository();
      await pumpSessionsScreen(tester, repo);

      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.history,
        ),
        findsOneWidget,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // SessionsScreen – session list rendering
  // ---------------------------------------------------------------------------

  group('SessionsScreen session list rendering', () {
    testWidgets('renders a card for each session in the repository',
        (WidgetTester tester) async {
      final repo = SessionRepository()
        ..add(_makeSession(id: 'session-001'))
        ..add(_makeSession(id: 'session-002'));

      await pumpSessionsScreen(tester, repo);

      expect(find.byType(Card), findsNWidgets(2));
    });

    testWidgets('displays session ID in each card',
        (WidgetTester tester) async {
      final repo = SessionRepository()
        ..add(_makeSession(id: 'my-unique-session-id'));

      await pumpSessionsScreen(tester, repo);

      expect(find.text('my-unique-session-id'), findsOneWidget);
    });

    testWidgets('displays "Front sensor" label for front-position session',
        (WidgetTester tester) async {
      final repo = SessionRepository()
        ..add(_makeSession(position: SensorPosition.front));

      await pumpSessionsScreen(tester, repo);

      expect(
        find.textContaining('Front sensor'),
        findsOneWidget,
      );
    });

    testWidgets('displays "Rear sensor" label for rear-position session',
        (WidgetTester tester) async {
      final repo = SessionRepository()
        ..add(_makeSession(
          id: 'rear-001',
          position: SensorPosition.rear,
        ));

      await pumpSessionsScreen(tester, repo);

      expect(find.textContaining('Rear sensor'), findsOneWidget);
    });

    testWidgets('displays sampling rate in each card',
        (WidgetTester tester) async {
      final repo = SessionRepository()
        ..add(_makeSession(samplingRateHz: 200.0));

      await pumpSessionsScreen(tester, repo);

      expect(find.textContaining('200 Hz'), findsOneWidget);
    });

    testWidgets('shows "Paired" indicator when session has a paired ID',
        (WidgetTester tester) async {
      final repo = SessionRepository()
        ..add(_makeSession(pairedSessionId: 'other-session'));

      await pumpSessionsScreen(tester, repo);

      expect(find.textContaining('Paired'), findsOneWidget);
    });

    testWidgets('does not show "Paired" indicator for unpaired session',
        (WidgetTester tester) async {
      final repo = SessionRepository()..add(_makeSession());

      await pumpSessionsScreen(tester, repo);

      expect(find.textContaining('Paired'), findsNothing);
    });

    testWidgets('each card shows open and delete icon buttons',
        (WidgetTester tester) async {
      final repo = SessionRepository()..add(_makeSession());
      await pumpSessionsScreen(tester, repo);

      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.open_in_new,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.delete_outline,
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'list disappears and empty state shown after last session deleted',
        (WidgetTester tester) async {
      final repo = SessionRepository()..add(_makeSession(id: 'only'));
      await pumpSessionsScreen(tester, repo);

      // Confirm delete via the dialog
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.delete_outline,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('No sessions yet'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // SessionsScreen – delete confirmation dialog
  // ---------------------------------------------------------------------------

  group('SessionsScreen delete confirmation dialog', () {
    testWidgets('tapping delete icon shows confirmation dialog',
        (WidgetTester tester) async {
      final repo = SessionRepository()..add(_makeSession());
      await pumpSessionsScreen(tester, repo);

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.delete_outline,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delete session?'), findsOneWidget);
      expect(find.text('This action cannot be undone.'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('confirming delete removes session from the list',
        (WidgetTester tester) async {
      final repo = SessionRepository()
        ..add(_makeSession(id: 'to-delete'))
        ..add(_makeSession(id: 'to-keep'));
      await pumpSessionsScreen(tester, repo);

      // Tap delete on the first card
      final deleteButtons = find.byWidgetPredicate(
        (w) => w is Icon && w.icon == Icons.delete_outline,
      );
      await tester.tap(deleteButtons.first);
      await tester.pumpAndSettle();

      // Confirm
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(repo.sessions, hasLength(1));
      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('cancelling delete keeps session in the list',
        (WidgetTester tester) async {
      final repo = SessionRepository()..add(_makeSession(id: 'stay'));
      await pumpSessionsScreen(tester, repo);

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.delete_outline,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repo.sessions, hasLength(1));
      expect(find.text('stay'), findsOneWidget);
    });

    testWidgets('dialog is dismissed after confirming delete',
        (WidgetTester tester) async {
      final repo = SessionRepository()..add(_makeSession());
      await pumpSessionsScreen(tester, repo);

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.delete_outline,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete session?'), findsNothing);
    });

    testWidgets('dialog is dismissed after cancelling delete',
        (WidgetTester tester) async {
      final repo = SessionRepository()..add(_makeSession());
      await pumpSessionsScreen(tester, repo);

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.delete_outline,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Delete session?'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // SessionsScreen – open action
  // ---------------------------------------------------------------------------

  group('SessionsScreen open action', () {
    testWidgets('tapping open shows a snackbar with the session id',
        (WidgetTester tester) async {
      final repo = SessionRepository()..add(_makeSession(id: 'open-me'));
      await pumpSessionsScreen(tester, repo);

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.open_in_new,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('open-me'), findsWidgets);
    });

    testWidgets('tapping open does not remove session from repository',
        (WidgetTester tester) async {
      final repo = SessionRepository()..add(_makeSession(id: 'stay'));
      await pumpSessionsScreen(tester, repo);

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.open_in_new,
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.sessions, hasLength(1));
    });
  });

  // ---------------------------------------------------------------------------
  // SessionsScreen – live repository updates
  // ---------------------------------------------------------------------------

  group('SessionsScreen live repository updates', () {
    testWidgets('adding a session after pump updates the list',
        (WidgetTester tester) async {
      final repo = SessionRepository();
      await pumpSessionsScreen(tester, repo);

      expect(find.text('No sessions yet'), findsOneWidget);

      repo.add(_makeSession(id: 'new-session'));
      await tester.pumpAndSettle();

      expect(find.text('No sessions yet'), findsNothing);
      expect(find.text('new-session'), findsOneWidget);
    });
  });
}
