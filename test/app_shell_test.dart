import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/app_shell.dart';
import 'package:ride_metric_x/main.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Responsive layout tests
  // ---------------------------------------------------------------------------
  group('AppShell responsive layout', () {
    testWidgets('shows NavigationBar on mobile width (<600)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const RideMetricXApp());

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('shows NavigationRail on tablet/desktop width (>=600)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const RideMetricXApp());

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('shows NavigationRail at exact breakpoint (600)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const RideMetricXApp());

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Tab switching / route navigation tests
  // ---------------------------------------------------------------------------
  group('AppShell tab switching', () {
    testWidgets('starts on Import screen', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const RideMetricXApp());

      expect(find.text('Import Data'), findsWidgets);
    });

    testWidgets('tapping Sessions in NavigationBar shows Sessions screen',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const RideMetricXApp());

      await tester.tap(find.widgetWithText(NavigationDestination, 'Sessions'));
      await tester.pumpAndSettle();

      expect(find.text('Sessions'), findsWidgets);
    });

    testWidgets('tapping Settings in NavigationBar shows Settings screen',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const RideMetricXApp());

      await tester.tap(find.widgetWithText(NavigationDestination, 'Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsWidgets);
    });

    testWidgets('tapping Import in NavigationRail shows Import screen',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const RideMetricXApp());

      // Navigate away first, then come back to Import.
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Sessions'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Import'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Import Data'), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------
  // Theme mode smoke tests
  // ---------------------------------------------------------------------------
  group('RideMetricXApp theme modes', () {
    testWidgets('renders in light mode without error',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const RideMetricXApp(themeMode: ThemeMode.light),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode without error',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const RideMetricXApp(themeMode: ThemeMode.dark),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in system mode without error',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const RideMetricXApp(themeMode: ThemeMode.system),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark mode applies dark brightness',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const RideMetricXApp(themeMode: ThemeMode.dark),
      );
      final ThemeData theme = Theme.of(
        tester.element(find.byType(AppShell)),
      );
      expect(theme.brightness, Brightness.dark);
    });

    testWidgets('light mode applies light brightness',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const RideMetricXApp(themeMode: ThemeMode.light),
      );
      final ThemeData theme = Theme.of(
        tester.element(find.byType(AppShell)),
      );
      expect(theme.brightness, Brightness.light);
    });
  });
}
