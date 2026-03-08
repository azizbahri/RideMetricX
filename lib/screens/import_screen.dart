import 'package:flutter/material.dart';

class ImportScreen extends StatelessWidget {
  const ImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Data'),
      ),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.upload_file, size: 64),
            SizedBox(height: 16),
            Text(
              'Import Data',
              style: TextStyle(fontSize: 24),
            ),
          ],
        ),
      ),
    );
  }
}
