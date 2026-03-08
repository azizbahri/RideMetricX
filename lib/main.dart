import 'package:flutter/material.dart';

import 'app_shell.dart';

void main() {
  runApp(const RideMetricXApp());
}

/// Root application widget.
///
/// Accepts an optional [themeMode] so that tests (and future settings pages)
/// can inject a specific mode without touching the system setting.
class RideMetricXApp extends StatelessWidget {
  const RideMetricXApp({super.key, this.themeMode = ThemeMode.system});

  /// Controls whether the app uses the light theme, dark theme, or follows
  /// the host platform's brightness preference.
  final ThemeMode themeMode;

  static const _seedColor = Colors.deepOrange;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RideMetricX',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: themeMode,
      home: const AppShell(),
    );
  }
}
