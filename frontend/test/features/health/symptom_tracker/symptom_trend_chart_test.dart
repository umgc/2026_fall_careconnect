import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/symptom-tracker/widgets/symptom_trend_chart.dart';

void main() {
  testWidgets('shows empty state when no points in range', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SymptomTrendChart(points: []),
        ),
      ),
    );

    expect(find.textContaining('No symptoms logged'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);
    expect(find.text('Year'), findsOneWidget);
  });

  testWidgets('renders multi-series legend and toggles visibility',
      (tester) async {
    final now = DateTime.now();
    final points = [
      SymptomTrendPoint(
        symptomKey: 'Headache',
        severity: 4,
        takenAt: now.subtract(const Duration(days: 1)),
      ),
      SymptomTrendPoint(
        symptomKey: 'Fatigue',
        severity: 6,
        takenAt: now.subtract(const Duration(days: 2)),
      ),
      SymptomTrendPoint(
        symptomKey: 'Headache',
        severity: 3,
        takenAt: now.subtract(const Duration(hours: 6)),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SymptomTrendChart(points: points),
          ),
        ),
      ),
    );

    expect(find.text('Headache'), findsOneWidget);
    expect(find.text('Fatigue'), findsOneWidget);
    expect(find.textContaining('No symptoms logged'), findsNothing);

    await tester.tap(find.text('Fatigue'));
    await tester.pumpAndSettle();

    // Chip still present; deselected via FilterChip.
    expect(find.text('Fatigue'), findsOneWidget);
  });

  testWidgets('month range can exclude older points into empty state',
      (tester) async {
    final old = DateTime.now().subtract(const Duration(days: 20));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SymptomTrendChart(
            points: [
              SymptomTrendPoint(
                symptomKey: 'Pain',
                severity: 5,
                takenAt: old,
              ),
            ],
            initialRange: SymptomTrendRange.month,
          ),
        ),
      ),
    );

    expect(find.text('Pain'), findsOneWidget);

    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No symptoms logged'), findsOneWidget);
  });
}
