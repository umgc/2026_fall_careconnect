// Tests for CurrentMedicationsSection widget
// (lib/features/health/caregiver-patient-list/widgets/current_medications_card.dart)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/current_medications_card.dart';
import 'package:care_connect_app/features/health/medication-tracker/models/medication-model.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

Medication _med({
  String name = 'Aspirin',
  String dosage = '100mg',
  String frequency = 'Once daily',
  String route = 'Oral',
  bool isActive = true,
  MedicationType? type = MedicationType.OVER_THE_COUNTER,
  String? prescribedBy,
  String? notes,
}) =>
    Medication(
      medicationName: name,
      dosage: dosage,
      frequency: frequency,
      route: route,
      isActive: isActive,
      medicationType: type,
      prescribedBy: prescribedBy,
      notes: notes,
    );

void main() {
  group('CurrentMedicationsSection', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(const CurrentMedicationsSection(entries: [])));
      expect(find.byType(CurrentMedicationsSection), findsOneWidget);
    });

    testWidgets('shows default Current Medications title', (tester) async {
      await tester.pumpWidget(_wrap(const CurrentMedicationsSection(entries: [])));
      expect(find.text('Current Medications'), findsOneWidget);
    });

    testWidgets('shows custom title', (tester) async {
      await tester.pumpWidget(_wrap(const CurrentMedicationsSection(
        entries: [],
        title: 'Patient Meds',
      )));
      expect(find.text('Patient Meds'), findsOneWidget);
    });

    testWidgets('shows empty state when no entries', (tester) async {
      await tester.pumpWidget(_wrap(const CurrentMedicationsSection(entries: [])));
      expect(find.text('No current medications'), findsOneWidget);
    });

    testWidgets('shows medication name', (tester) async {
      await tester.pumpWidget(_wrap(CurrentMedicationsSection(
        entries: [_med(name: 'Lisinopril')],
      )));
      expect(find.text('Lisinopril'), findsOneWidget);
    });

    testWidgets('shows dosage', (tester) async {
      await tester.pumpWidget(_wrap(CurrentMedicationsSection(
        entries: [_med(dosage: '10mg')],
      )));
      expect(find.text('10mg'), findsOneWidget);
    });

    testWidgets('shows frequency', (tester) async {
      await tester.pumpWidget(_wrap(CurrentMedicationsSection(
        entries: [_med(frequency: 'Twice daily')],
      )));
      expect(find.text('Twice daily'), findsOneWidget);
    });

    testWidgets('shows active badge for active medication', (tester) async {
      await tester.pumpWidget(_wrap(CurrentMedicationsSection(
        entries: [_med(isActive: true)],
      )));
      expect(find.text('active'), findsOneWidget);
    });

    testWidgets('shows inactive badge for inactive medication', (tester) async {
      await tester.pumpWidget(_wrap(CurrentMedicationsSection(
        entries: [_med(isActive: false)],
      )));
      expect(find.text('inactive'), findsOneWidget);
    });

    testWidgets('shows Approve button for inactive medication', (tester) async {
      await tester.pumpWidget(_wrap(CurrentMedicationsSection(
        entries: [_med(isActive: false)],
      )));
      expect(find.text('Approve'), findsOneWidget);
    });

    testWidgets('does not show Approve button for active medication', (tester) async {
      await tester.pumpWidget(_wrap(CurrentMedicationsSection(
        entries: [_med(isActive: true)],
      )));
      expect(find.text('Approve'), findsNothing);
    });

    testWidgets('shows Delete button', (tester) async {
      await tester.pumpWidget(_wrap(CurrentMedicationsSection(
        entries: [_med()],
      )));
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('shows prescribedBy when provided', (tester) async {
      await tester.pumpWidget(_wrap(CurrentMedicationsSection(
        entries: [_med(prescribedBy: 'Dr. Johnson')],
      )));
      expect(find.text('Dr. Johnson'), findsOneWidget);
    });

    testWidgets('shows notes when provided', (tester) async {
      await tester.pumpWidget(_wrap(CurrentMedicationsSection(
        entries: [_med(notes: 'Take with food')],
      )));
      expect(find.text('Take with food'), findsOneWidget);
    });

    testWidgets('shows vaccines_outlined icon', (tester) async {
      await tester.pumpWidget(_wrap(const CurrentMedicationsSection(entries: [])));
      expect(find.byIcon(Icons.vaccines_outlined), findsOneWidget);
    });
  });
}
