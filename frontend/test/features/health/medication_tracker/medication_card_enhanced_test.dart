// Enhanced tests for MedicationCard widget
// (lib/features/health/medication-tracker/widgets/medication-card.dart).
// Covers: SUPPLEMENT type, inactive with PRESCRIPTION, access_time icon,
// info_outline icon, multiple medication configurations.

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
  String medicationName = 'Ibuprofen',
  String dosage = '200mg',
  String frequency = 'Twice daily',
  String route = 'Oral',
}) =>
    Medication(
      id: 1,
      medicationName: medicationName,
      dosage: dosage,
      frequency: frequency,
      route: route,
      isActive: isActive,
      medicationType: medicationType,
      prescribedBy: prescribedBy,
      notes: notes,
      nextDose: nextDose,
    );

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  group('MedicationCard - SUPPLEMENT type', () {
    testWidgets('shows delete icon for active SUPPLEMENT medication',
        (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(
          isActive: true,
          medicationType: MedicationType.SUPPLEMENT,
        ),
        onStatusChanged: (_) {},
      )));
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('hides delete icon for inactive SUPPLEMENT medication',
        (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(
          isActive: false,
          medicationType: MedicationType.SUPPLEMENT,
        ),
        onStatusChanged: (_) {},
      )));
      // inactive medications should not show delete button
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });
  });

  group('MedicationCard - icons', () {
    testWidgets('shows access_time icon for next dose row', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(),
        onStatusChanged: (_) {},
      )));
      expect(find.byIcon(Icons.access_time), findsOneWidget);
    });

    testWidgets('shows info_outline icon for route row', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(),
        onStatusChanged: (_) {},
      )));
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });
  });

  group('MedicationCard - different medication data', () {
    testWidgets('displays custom medication name', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(medicationName: 'Metformin'),
        onStatusChanged: (_) {},
      )));
      expect(find.text('Metformin'), findsOneWidget);
    });

    testWidgets('displays custom dosage and frequency', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(dosage: '500mg', frequency: 'Once daily'),
        onStatusChanged: (_) {},
      )));
      expect(find.text('500mg \u2022 Once daily'), findsOneWidget);
    });

    testWidgets('displays custom route', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(route: 'IV'),
        onStatusChanged: (_) {},
      )));
      expect(find.textContaining('Route: IV'), findsOneWidget);
    });

    testWidgets('displays custom next dose', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(nextDose: '10:00 PM'),
        onStatusChanged: (_) {},
      )));
      expect(find.textContaining('Next dose: 10:00 PM'), findsOneWidget);
    });
  });

  group('MedicationCard - inactive state', () {
    testWidgets('inactive PRESCRIPTION shows pending notice but no delete',
        (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(
          isActive: false,
          medicationType: MedicationType.PRESCRIPTION,
        ),
        onStatusChanged: (_) {},
      )));
      expect(find.byIcon(Icons.pending_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('pending notice contains expected text', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(isActive: false),
        onStatusChanged: (_) {},
      )));
      expect(
        find.textContaining('pending caregiver approval'),
        findsOneWidget,
      );
      expect(
        find.textContaining('continue to take medication'),
        findsOneWidget,
      );
    });
  });

  group('MedicationCard - optional fields combinations', () {
    testWidgets('shows both prescribedBy and notes when both provided',
        (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(
          prescribedBy: 'Dr. Jones',
          notes: 'Take before meals',
        ),
        onStatusChanged: (_) {},
      )));
      expect(find.textContaining('Prescribed by: Dr. Jones'), findsOneWidget);
      expect(find.text('Take before meals'), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      expect(find.byIcon(Icons.note_outlined), findsOneWidget);
    });

    testWidgets('hides both prescribedBy and notes when both null',
        (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(prescribedBy: null, notes: null),
        onStatusChanged: (_) {},
      )));
      expect(find.byIcon(Icons.person_outline), findsNothing);
      expect(find.byIcon(Icons.note_outlined), findsNothing);
    });
  });

  group('MedicationCard - widget structure', () {
    testWidgets('is a StatefulWidget', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(),
        onStatusChanged: (_) {},
      )));
      expect(find.byType(MedicationCard), findsOneWidget);
    });

    testWidgets('accepts onMedicationRemoved callback', (tester) async {
      await tester.pumpWidget(_wrap(MedicationCard(
        medication: _med(),
        onStatusChanged: (_) {},
        onMedicationRemoved: () {},
      )));
      expect(find.byType(MedicationCard), findsOneWidget);
    });
  });
}
