import 'package:flutter/material.dart';

import 'screens/import_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/settings_screen.dart';

/// Width threshold below which [NavigationBar] (bottom) is shown instead of
/// [NavigationRail] (side).
const double kMobileBreakpoint = 600.0;

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

  static const List<Widget> _pages = [
    ImportScreen(),
    SessionsScreen(),
    SettingsScreen(),
  ];

  void _onDestinationSelected(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool useRail = constraints.maxWidth >= kMobileBreakpoint;

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
