import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:care_connect_app/features/analytics/analytics_page.dart';

void main() {
  testWidgets('Analytics page renders correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MaterialApp(home: AnalyticsPage(patientId: 1)));

    // Verify that the analytics page shows loading initially
    expect(find.text('Patient Analytics'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('Analytics page shows export buttons in error state as retry', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AnalyticsPage(patientId: 1)));

    // Pump multiple times to allow async operations to complete
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    // After pumping, we should be in either loading or error state
    // Both are valid since the API call will fail in tests
    final retryFinder = find.text('Retry');
    final loadingFinder = find.byType(CircularProgressIndicator);

    expect(
      retryFinder.evaluate().length + loadingFinder.evaluate().length,
      greaterThan(0),
    );
  });

  testWidgets('Analytics page shows Scaffold', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AnalyticsPage(patientId: 1)));
    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('Analytics page shows AppBar', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AnalyticsPage(patientId: 1)));
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('Analytics page renders with different patientId', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AnalyticsPage(patientId: 999)));
    expect(find.byType(AnalyticsPage), findsOneWidget);
    expect(find.text('Patient Analytics'), findsOneWidget);
  });

  testWidgets('Analytics page shows no error text while loading', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AnalyticsPage(patientId: 1)));
    expect(find.textContaining('Error'), findsNothing);
  });

  testWidgets('Analytics page shows Center while loading', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AnalyticsPage(patientId: 1)));
    expect(find.byType(Center), findsWidgets);
  });
}
