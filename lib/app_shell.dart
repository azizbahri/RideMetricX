import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'models/session_metadata.dart';
import 'repositories/session_repository.dart';
import 'screens/analysis_screen.dart';
import 'screens/comparison_screen.dart';
import 'screens/import_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tuning_screen.dart';
import 'services/data_import/decompressor.dart';
import 'services/data_import/import_service.dart';

/// Width threshold below which [NavigationBar] (bottom) is shown instead of
/// [NavigationRail] (side).
const double _kMobileBreakpoint = 600.0;

/// A single top-level navigation destination.
class _NavDestination {
  const _NavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final Widget icon;
  final Widget selectedIcon;
}

const List<_NavDestination> _destinations = [
  _NavDestination(
    label: 'Import',
    icon: Icon(Icons.upload_file_outlined),
    selectedIcon: Icon(Icons.upload_file),
  ),
  _NavDestination(
    label: 'Sessions',
    icon: Icon(Icons.history_outlined),
    selectedIcon: Icon(Icons.history),
  ),
  _NavDestination(
    label: 'Analysis',
    icon: Icon(Icons.show_chart_outlined),
    selectedIcon: Icon(Icons.show_chart),
  ),
  _NavDestination(
    label: 'Tuning',
    icon: Icon(Icons.tune_outlined),
    selectedIcon: Icon(Icons.tune),
  ),
  _NavDestination(
    label: 'Compare',
    icon: Icon(Icons.compare_arrows_outlined),
    selectedIcon: Icon(Icons.compare_arrows),
  ),
  _NavDestination(
    label: 'Settings',
    icon: Icon(Icons.settings_outlined),
    selectedIcon: Icon(Icons.settings),
  ),
];

/// The root scaffold that hosts the app-wide navigation and swaps the active
/// page in response to user selection.
///
/// On narrow (mobile) viewports a [NavigationBar] is rendered at the bottom.
/// On wide (tablet/desktop) viewports a [NavigationRail] is rendered on the
/// leading edge.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  final SessionRepository _sessionRepository = SessionRepository();

  /// The session currently open in the Analysis workspace, if any.
  SessionMetadata? _activeSession;

  /// Picks a file using the platform file picker and returns a [FileSelection]
  /// containing the file name and decoded text content, or `null` if the user
  /// cancelled.
  ///
  /// Compressed files (`.gz`, `.zip`) are decompressed via [Decompressor]
  /// before wrapping in [FileSelection].
  Future<FileSelection?> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'json', 'bin', 'gz'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return null;

    final ext = file.name.split('.').last.toLowerCase();
    final String content;
    if (ext == 'gz' || ext == 'zip') {
      content = Decompressor.decompress(
        bytes,
        Decompressor.formatFromFileName(file.name),
      );
    } else {
      content = utf8.decode(bytes, allowMalformed: true);
    }

    return FileSelection(
      fileName: file.name,
      content: content,
    );
  }

  List<Widget> get _pages => [
        ImportScreen(
          onPickFrontFile: _pickFile,
          onPickRearFile: _pickFile,
          onNavigateToSessions: () => _onDestinationSelected(1),
          onImportCompleted: _onImportCompleted,
        ),
        SessionsScreen(
          repository: _sessionRepository,
          onOpenSession: _onOpenSession,
        ),
        AnalysisScreen(sessionTitle: _activeSession?.sessionId),
        const TuningScreen(),
        const ComparisonScreen(),
        const SettingsScreen(),
      ];

  void _onImportCompleted(List<SessionMetadata> sessions) {
    for (final session in sessions) {
      _sessionRepository.add(session);
    }
  }

  void _onOpenSession(SessionMetadata session) {
    setState(() {
      _activeSession = session;
      _selectedIndex = 2; // Navigate to Analysis tab
    });
  }

  void _onDestinationSelected(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool useRail = constraints.maxWidth >= _kMobileBreakpoint;

        if (useRail) {
          return _buildRailLayout();
        } else {
          return _buildBarLayout();
        }
      },
    );
  }

  /// Desktop / tablet layout: NavigationRail on the left.
  Widget _buildRailLayout() {
    return Scaffold(
      appBar: AppBar(title: Text(_destinations[_selectedIndex].label)),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onDestinationSelected,
            labelType: NavigationRailLabelType.all,
            destinations: _destinations
                .map(
                  (d) => NavigationRailDestination(
                    icon: d.icon,
                    selectedIcon: d.selectedIcon,
                    label: Text(d.label),
                  ),
                )
                .toList(),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: _pages[_selectedIndex]),
        ],
      ),
    );
  }

  /// Mobile layout: NavigationBar at the bottom.
  Widget _buildBarLayout() {
    return Scaffold(
      appBar: AppBar(title: Text(_destinations[_selectedIndex].label)),
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: _destinations
            .map(
              (d) => NavigationDestination(
                icon: d.icon,
                selectedIcon: d.selectedIcon,
                label: d.label,
              ),
            )
            .toList(),
      ),
    );
  }
}
