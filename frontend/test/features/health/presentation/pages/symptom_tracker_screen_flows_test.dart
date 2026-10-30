// Happy-path test for SymptomTrackerScreen
// (lib/features/health/presentation/pages/symptom_tracker_screen.dart):
// choose a symptom, set severity and time, and log it.

import 'package:care_connect_app/features/health/presentation/pages/symptom_tracker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('logs a symptom with severity and occurrence time',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SymptomTrackerScreen()));

    await tester.tap(find.text('Choose a symptom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Headache').last);
    await tester.pumpAndSettle();

    tester.widget<Slider>(find.byType(Slider)).onChanged!(8);
    await tester.pump();

    // Pick today's date and the current time.
    await tester.tap(find.byWidgetPredicate(
      (w) => w is ElevatedButton && w.onPressed != null,
    ).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit Symptom Log'));
    await tester.pumpAndSettle();
    expect(find.text('Headache'), findsWidgets);
    expect(find.byType(ListTile), findsOneWidget);
  });

  testWidgets('custom symptom without time is not logged', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SymptomTrackerScreen()));
    await tester.enterText(find.byType(TextField), 'Chest tightness');
    await tester.tap(find.text('Submit Symptom Log'));
    await tester.pump();
    expect(find.byType(ListTile), findsNothing);
  });
}
