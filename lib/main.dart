import 'package:flutter/material.dart';

void main() {
  runApp(const RideMetricXApp());
}

class RideMetricXApp extends StatelessWidget {
  const RideMetricXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RideMetricX',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('RideMetricX'),
      ),
      body: const Center(
        child: Text(
          'Hello RideMetricX',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
