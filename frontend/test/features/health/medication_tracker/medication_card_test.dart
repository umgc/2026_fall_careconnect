// Tests for MedicationCard widget
// (lib/features/health/medication-tracker/widgets/medication-card.dart).
// Provider is only used in the remove action (not build), so we can test
// rendering without providing UserProvider.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/medication-tracker/widgets/medication-card.dart';
import 'package:care_connect_app/features/health/medication-tracker/models/medication-model.dart';

Medication _med({
  bool isActive = true,
  MedicationType? medicationType = MedicationType.OVER_THE_COUNTER,
  String? prescribedBy,
  String? notes,
  String? nextDose,
}) =>
    Medication(
      id: 1,
      medicationName: 'Ibuprofen',
      dosage: '200mg',
      frequency: 'Twice daily',
      route: 'Oral',
      isActive: isActive,
      medicationType: medicationType,
      prescribedBy: prescribedBy,
      notes: notes,
      nextDose: nextDose,
    );

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  group('MedicationCard', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(),
        onStatusChanged: (_) {},
      )));
      expect(find.byType(MedicationCard), findsOneWidget);
    });

    testWidgets('shows medication name', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(),
        onStatusChanged: (_) {},
      )));
      expect(find.text('Ibuprofen'), findsOneWidget);
    });

    testWidgets('shows dosage and frequency', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(),
        onStatusChanged: (_) {},
      )));
      expect(find.text('200mg • Twice daily'), findsOneWidget);
    });

    testWidgets('shows route', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(),
        onStatusChanged: (_) {},
      )));
      expect(find.textContaining('Route: Oral'), findsOneWidget);
    });

    testWidgets('shows next dose when provided', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(nextDose: '8:00 AM'),
        onStatusChanged: (_) {},
      )));
      expect(find.textContaining('Next dose: 8:00 AM'), findsOneWidget);
    });

    testWidgets('shows Not specified when nextDose is null', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(nextDose: null),
        onStatusChanged: (_) {},
      )));
      expect(find.textContaining('Not specified'), findsOneWidget);
    });

    testWidgets('hides delete icon for PRESCRIPTION type', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(
          isActive: true,
          medicationType: MedicationType.PRESCRIPTION,
        ),
        onStatusChanged: (_) {},
      )));
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('shows delete icon for active OVER_THE_COUNTER medication',
        (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(
          isActive: true,
          medicationType: MedicationType.OVER_THE_COUNTER,
        ),
        onStatusChanged: (_) {},
      )));
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('shows pending notice when inactive', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(isActive: false),
        onStatusChanged: (_) {},
      )));
      expect(find.byIcon(Icons.pending_outlined), findsOneWidget);
      expect(find.textContaining('pending caregiver approval'), findsOneWidget);
    });

    testWidgets('does not show pending notice when active', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(isActive: true),
        onStatusChanged: (_) {},
      )));
      expect(find.byIcon(Icons.pending_outlined), findsNothing);
    });

    testWidgets('shows prescribedBy when provided', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(prescribedBy: 'Dr. Smith'),
        onStatusChanged: (_) {},
      )));
      expect(find.textContaining('Prescribed by: Dr. Smith'), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    });

    testWidgets('hides prescribedBy row when null', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(prescribedBy: null),
        onStatusChanged: (_) {},
      )));
      expect(find.textContaining('Prescribed by:'), findsNothing);
    });

    testWidgets('shows notes when provided', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(notes: 'Take with food'),
        onStatusChanged: (_) {},
      )));
      expect(find.text('Take with food'), findsOneWidget);
      expect(find.byIcon(Icons.note_outlined), findsOneWidget);
    });

    testWidgets('hides notes row when null', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(notes: null),
        onStatusChanged: (_) {},
      )));
      expect(find.byIcon(Icons.note_outlined), findsNothing);
    });

    testWidgets('hides notes row when empty string', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(notes: ''),
        onStatusChanged: (_) {},
      )));
      expect(find.byIcon(Icons.note_outlined), findsNothing);
    });
  });
}
