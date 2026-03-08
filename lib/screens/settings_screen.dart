import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.settings, size: 64),
          SizedBox(height: 16),
          Text(
            'Settings',
            style: TextStyle(fontSize: 24),
          ),
        ],
      ),
    );
  }
}
