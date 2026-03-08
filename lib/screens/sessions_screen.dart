import 'package:flutter/material.dart';

class SessionsScreen extends StatelessWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 64),
          SizedBox(height: 16),
          Text(
            'Sessions',
            style: TextStyle(fontSize: 24),
          ),
        ],
      ),
    );
  }
}
