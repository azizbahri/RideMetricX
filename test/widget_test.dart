import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/main.dart';

void main() {
  testWidgets('App renders without crashing (smoke test)',
      (WidgetTester tester) async {
    await tester.pumpWidget(const RideMetricXApp());
    // The shell should be visible with at least the Import destination.
    expect(find.text('Import'), findsWidgets);
    expect(find.text('RideMetricX'),
        findsNothing); // title is in MaterialApp, not in the UI
  });
}
