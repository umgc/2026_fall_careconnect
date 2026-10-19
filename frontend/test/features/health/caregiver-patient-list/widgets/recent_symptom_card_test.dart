// Tests for RecentSymptomsSection widget
// (lib/features/health/caregiver-patient-list/widgets/recent_symptom_card.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/recent_symptom_card.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

SymptomEntry _entry({
  String severity = 'Mild',
  String name = 'Headache',
  String note = 'Some note',
}) =>
    SymptomEntry(
      id: '1',
      date: DateTime(2024, 3, 10),
      name: name,
      severity: severity,
      note: note,
    );

void main() {
  group('RecentSymptomsSection', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(
        RecentSymptomsSection(entries: [_entry()]),
      ));
      expect(find.byType(RecentSymptomsSection), findsOneWidget);
    });

    testWidgets('shows Recent Symptoms header', (tester) async {
      await tester.pumpWidget(_wrap(
        RecentSymptomsSection(entries: [_entry()]),
      ));
      expect(find.text('Recent Symptoms'), findsOneWidget);
    });

    testWidgets('shows medical_services icon', (tester) async {
      await tester.pumpWidget(_wrap(
        RecentSymptomsSection(entries: [_entry()]),
      ));
      expect(find.byIcon(Icons.medical_services_outlined), findsOneWidget);
    });

    testWidgets('shows symptom name', (tester) async {
      await tester.pumpWidget(_wrap(
        RecentSymptomsSection(entries: [_entry(name: 'Nausea')]),
      ));
      expect(find.text('Nausea'), findsOneWidget);
    });

    testWidgets('shows severity chip', (tester) async {
      await tester.pumpWidget(_wrap(
        RecentSymptomsSection(entries: [_entry(severity: 'Moderate')]),
      ));
      expect(find.text('moderate'), findsOneWidget);
    });

    testWidgets('shows note text', (tester) async {
      await tester.pumpWidget(_wrap(
        RecentSymptomsSection(entries: [_entry(note: 'Pain after meals')]),
      ));
      expect(find.text('Pain after meals'), findsOneWidget);
    });

    testWidgets('shows formatted date (Mar 10)', (tester) async {
      await tester.pumpWidget(_wrap(
        RecentSymptomsSection(entries: [_entry()]),
      ));
      expect(find.text('Mar 10'), findsOneWidget);
    });

    testWidgets('renders multiple entries', (tester) async {
      await tester.pumpWidget(_wrap(
        RecentSymptomsSection(entries: [
          _entry(name: 'Fever'),
          _entry(name: 'Cough'),
        ]),
      ));
      expect(find.text('Fever'), findsOneWidget);
      expect(find.text('Cough'), findsOneWidget);
    });

    testWidgets('renders empty entries list without crashing', (tester) async {
      await tester.pumpWidget(_wrap(
        RecentSymptomsSection(entries: []),
      ));
      expect(find.text('Recent Symptoms'), findsOneWidget);
    });

    testWidgets('shows extraTop widget when provided', (tester) async {
      await tester.pumpWidget(_wrap(
        RecentSymptomsSection(
          entries: [],
          extraTop: const Text('Extra Widget'),
        ),
      ));
      expect(find.text('Extra Widget'), findsOneWidget);
    });

    testWidgets('does not show extraTop when not provided', (tester) async {
      await tester.pumpWidget(_wrap(
        RecentSymptomsSection(entries: [_entry()]),
      ));
      expect(find.text('Extra Widget'), findsNothing);
    });

    testWidgets('hides note row when note is empty', (tester) async {
      await tester.pumpWidget(_wrap(
        RecentSymptomsSection(entries: [_entry(note: '')]),
      ));
      // The note widget should not render — only 'headache' and 'mild' should appear
      expect(find.text(''), findsNothing);
    });

    testWidgets('severe severity chip appears for severe entry', (tester) async {
      await tester.pumpWidget(_wrap(
        RecentSymptomsSection(entries: [_entry(severity: 'Severe')]),
      ));
      expect(find.text('severe'), findsOneWidget);
    });
  });
}
