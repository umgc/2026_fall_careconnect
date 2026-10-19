// Tests for SymptomTrackerScreen
// (lib/features/health/presentation/pages/symptom_tracker_screen.dart).
//
// Pure widget — no Provider, no API calls in initState.
// Tests cover initial render, static UI elements, and the DropdownButton.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/presentation/pages/symptom_tracker_screen.dart';

Widget _wrap() => const MaterialApp(home: SymptomTrackerScreen());

void main() {
  group('SymptomTrackerScreen – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(SymptomTrackerScreen), findsOneWidget);
    });

    testWidgets('shows "Symptom Tracker" in the AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Symptom Tracker'), findsOneWidget);
    });

    testWidgets('shows "Select a symptom:" label', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Select a symptom:'), findsOneWidget);
    });

    testWidgets('shows a DropdownButton for symptom selection', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });

    testWidgets('dropdown hint text is "Choose a symptom"', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Choose a symptom'), findsOneWidget);
    });

    testWidgets('shows custom symptom TextField', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows severity Slider', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('shows "Select time of occurrence" button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Select time of occurrence'), findsOneWidget);
    });

    testWidgets('shows "Upload Symptom Photo" button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Upload Symptom Photo'), findsOneWidget);
    });

    testWidgets('shows "Submit Symptom Log" button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Submit Symptom Log'), findsOneWidget);
    });

    testWidgets('shows "Symptom History:" section', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Symptom History:'), findsOneWidget);
    });

    testWidgets('shows a Divider', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('does NOT show photo image initially', (tester) async {
      // selectedImage is null initially — no Image.file widget rendered.
      await tester.pumpWidget(_wrap());
      expect(find.byType(Image), findsNothing);
    });
  });
}
