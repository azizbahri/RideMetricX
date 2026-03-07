import 'package:flutter_test/flutter_test.dart';

import 'package:ride_metric_x/main.dart';

void main() {
  testWidgets('Hello RideMetricX smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RideMetricXApp());

    expect(find.text('Hello RideMetricX'), findsOneWidget);
    expect(find.text('RideMetricX'), findsOneWidget);
  });
}
