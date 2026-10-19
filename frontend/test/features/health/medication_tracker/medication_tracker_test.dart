// Tests for:
//   Medication model   (lib/features/health/medication-tracker/models/medication-model.dart)
//   AllergyCard widget (lib/features/health/symptom-tracker/widgets/allergies_card.dart)
//   MedicationCard widget (lib/features/health/medication-tracker/widgets/medication-card.dart)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/medication-tracker/models/medication-model.dart';
import 'package:care_connect_app/features/health/symptom-tracker/widgets/allergies_card.dart';
import 'package:care_connect_app/features/health/medication-tracker/widgets/medication-card.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

Medication _makeMed({
  String name = 'Aspirin',
  String dosage = '100mg',
  String frequency = 'Once daily',
  String route = 'Oral',
  MedicationType? medicationType = MedicationType.OVER_THE_COUNTER,
  bool isActive = true,
  String? prescribedBy,
  String? notes,
  String? nextDose = 'Today',
}) =>
    Medication(
      medicationName: name,
      dosage: dosage,
      frequency: frequency,
      route: route,
      medicationType: medicationType,
      isActive: isActive,
      prescribedBy: prescribedBy,
      notes: notes,
      nextDose: nextDose,
    );

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // Medication model
  // ───────────────────────────────────────────────────────────────────────────
  group('Medication model', () {
    test('stores all required fields', () {
      final med = _makeMed();
      expect(med.medicationName, 'Aspirin');
      expect(med.dosage, '100mg');
      expect(med.frequency, 'Once daily');
      expect(med.route, 'Oral');
      expect(med.isActive, isTrue);
    });

    test('fromJson parses required fields', () {
      final med = Medication.fromJson({
        'medicationName': 'Ibuprofen',
        'dosage': '200mg',
        'frequency': 'Twice daily',
        'route': 'Oral',
        'isActive': true,
      });
      expect(med.medicationName, 'Ibuprofen');
      expect(med.dosage, '200mg');
      expect(med.frequency, 'Twice daily');
      expect(med.route, 'Oral');
      expect(med.isActive, isTrue);
    });

    test('fromJson isActive defaults to true when null', () {
      final med = Medication.fromJson({
        'medicationName': 'X',
        'dosage': '1mg',
        'frequency': 'daily',
        'route': 'Oral',
        'isActive': null,
      });
      expect(med.isActive, isTrue);
    });

    test('fromJson parses PRESCRIPTION medicationType', () {
      final med = Medication.fromJson({
        'medicationName': 'X',
        'dosage': '1mg',
        'frequency': 'daily',
        'route': 'Oral',
        'medicationType': 'PRESCRIPTION',
      });
      expect(med.medicationType, MedicationType.PRESCRIPTION);
    });

    test('fromJson parses SUPPLEMENT medicationType', () {
      final med = Medication.fromJson({
        'medicationName': 'X',
        'dosage': '1mg',
        'frequency': 'daily',
        'route': 'Oral',
        'medicationType': 'SUPPLEMENT',
      });
      expect(med.medicationType, MedicationType.SUPPLEMENT);
    });

    test('fromJson null medicationType stays null', () {
      final med = Medication.fromJson({
        'medicationName': 'X',
        'dosage': '1mg',
        'frequency': 'daily',
        'route': 'Oral',
        'medicationType': null,
      });
      expect(med.medicationType, isNull);
    });

    test('fromJson unknown medicationType falls back to PRESCRIPTION', () {
      final med = Medication.fromJson({
        'medicationName': 'X',
        'dosage': '1mg',
        'frequency': 'daily',
        'route': 'Oral',
        'medicationType': 'UNKNOWN_TYPE',
      });
      expect(med.medicationType, MedicationType.PRESCRIPTION);
    });

    test('fromJson calculates nextDose "Today" for daily frequency', () {
      final med = Medication.fromJson({
        'medicationName': 'X',
        'dosage': '1mg',
        'frequency': 'Once daily',
        'route': 'Oral',
      });
      expect(med.nextDose, 'Today');
    });

    test('fromJson calculates nextDose "This week" for weekly frequency', () {
      final med = Medication.fromJson({
        'medicationName': 'X',
        'dosage': '1mg',
        'frequency': 'Once weekly',
        'route': 'Oral',
      });
      expect(med.nextDose, 'This week');
    });

    test('fromJson calculates nextDose "This month" for monthly frequency', () {
      final med = Medication.fromJson({
        'medicationName': 'X',
        'dosage': '1mg',
        'frequency': 'Once monthly',
        'route': 'Oral',
      });
      expect(med.nextDose, 'This month');
    });

    test('fromJson calculates nextDose "As needed" for other frequency', () {
      final med = Medication.fromJson({
        'medicationName': 'X',
        'dosage': '1mg',
        'frequency': 'As required',
        'route': 'Oral',
      });
      expect(med.nextDose, 'As needed');
    });

    test('toJson includes required fields', () {
      final med = _makeMed(name: 'Aspirin', dosage: '100mg');
      final json = med.toJson();
      expect(json['medicationName'], 'Aspirin');
      expect(json['dosage'], '100mg');
      expect(json['isActive'], isTrue);
    });

    test('toJson omits null optional fields', () {
      final med = _makeMed();
      final json = med.toJson();
      expect(json.containsKey('id'), isFalse);
      expect(json.containsKey('prescribedBy'), isFalse);
      expect(json.containsKey('notes'), isFalse);
    });

    test('copyWith changes specified fields', () {
      final med = _makeMed(name: 'Aspirin', isActive: true);
      final updated = med.copyWith(medicationName: 'Ibuprofen', isActive: false);
      expect(updated.medicationName, 'Ibuprofen');
      expect(updated.isActive, isFalse);
      expect(updated.dosage, med.dosage); // unchanged
    });

    test('copyWith preserves original when nothing changed', () {
      final med = _makeMed();
      final copy = med.copyWith();
      expect(copy.medicationName, med.medicationName);
      expect(copy.dosage, med.dosage);
      expect(copy.isActive, med.isActive);
    });

    test('MedicationStatus has upcoming, taken, missed values', () {
      expect(MedicationStatus.values, contains(MedicationStatus.upcoming));
      expect(MedicationStatus.values, contains(MedicationStatus.taken));
      expect(MedicationStatus.values, contains(MedicationStatus.missed));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // AllergyCard
  // ───────────────────────────────────────────────────────────────────────────
  group('AllergyCard', () {
    Widget makeCard({VoidCallback? onDelete}) => _wrap(
          AllergyCard(
            drug: 'Penicillin',
            reaction: 'Rash',
            severity: 'Moderate',
            note: 'Avoid all penicillin-based antibiotics',
            onDelete: onDelete ?? () {},
          ),
        );

    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(makeCard());
      expect(find.byType(AllergyCard), findsOneWidget);
    });

    testWidgets('shows drug name', (tester) async {
      await tester.pumpWidget(makeCard());
      expect(find.text('Penicillin'), findsOneWidget);
    });

    testWidgets('shows reaction text', (tester) async {
      await tester.pumpWidget(makeCard());
      expect(find.text('Reaction: Rash'), findsOneWidget);
    });

    testWidgets('shows severity text', (tester) async {
      await tester.pumpWidget(makeCard());
      expect(find.text('Severity: Moderate'), findsOneWidget);
    });

    testWidgets('shows note text', (tester) async {
      await tester.pumpWidget(makeCard());
      expect(find.text('Avoid all penicillin-based antibiotics'), findsOneWidget);
    });

    testWidgets('shows close icon', (tester) async {
      await tester.pumpWidget(makeCard());
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('calls onDelete when close button tapped', (tester) async {
      bool deleted = false;
      await tester.pumpWidget(makeCard(onDelete: () => deleted = true));
      await tester.tap(find.byIcon(Icons.close));
      expect(deleted, isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // MedicationCard
  // ───────────────────────────────────────────────────────────────────────────
  group('MedicationCard', () {
    Widget makeCard(Medication med) => _wrap(
          MedicationCard(
            medication: med,
            onStatusChanged: (_) {},
          ),
        );

    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(makeCard(_makeMed()));
      expect(find.byType(MedicationCard), findsOneWidget);
    });

    testWidgets('shows medication name', (tester) async {
      await tester.pumpWidget(makeCard(_makeMed(name: 'Metformin')));
      expect(find.text('Metformin'), findsOneWidget);
    });

    testWidgets('shows dosage and frequency', (tester) async {
      await tester.pumpWidget(
          makeCard(_makeMed(dosage: '500mg', frequency: 'Twice daily')));
      expect(find.textContaining('500mg'), findsOneWidget);
      expect(find.textContaining('Twice daily'), findsOneWidget);
    });

    testWidgets('shows next dose when set', (tester) async {
      await tester.pumpWidget(makeCard(_makeMed(nextDose: 'Today')));
      expect(find.textContaining('Next dose: Today'), findsOneWidget);
    });

    testWidgets('shows "Not specified" when nextDose is null', (tester) async {
      await tester.pumpWidget(makeCard(_makeMed(nextDose: null)));
      expect(find.textContaining('Not specified'), findsOneWidget);
    });

    testWidgets('shows route', (tester) async {
      await tester.pumpWidget(makeCard(_makeMed(route: 'Topical')));
      expect(find.textContaining('Route: Topical'), findsOneWidget);
    });

    testWidgets('shows prescribedBy when provided', (tester) async {
      await tester.pumpWidget(
          makeCard(_makeMed(prescribedBy: 'Dr. Smith')));
      expect(find.textContaining('Prescribed by: Dr. Smith'), findsOneWidget);
    });

    testWidgets('does not show prescribedBy row when null', (tester) async {
      await tester.pumpWidget(makeCard(_makeMed(prescribedBy: null)));
      expect(find.textContaining('Prescribed by:'), findsNothing);
    });

    testWidgets('shows notes when provided', (tester) async {
      await tester.pumpWidget(
          makeCard(_makeMed(notes: 'Take with food')));
      expect(find.text('Take with food'), findsOneWidget);
    });

    testWidgets('does not show notes row when null', (tester) async {
      await tester.pumpWidget(makeCard(_makeMed(notes: null)));
      expect(find.byIcon(Icons.note_outlined), findsNothing);
    });

    testWidgets('does not show delete button for prescription med',
        (tester) async {
      await tester.pumpWidget(makeCard(_makeMed(
          isActive: true, medicationType: MedicationType.PRESCRIPTION)));
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('TC-MED-TYPE-022: does not show delete button for inactive med', (tester) async {
      await tester.pumpWidget(
          makeCard(_makeMed(isActive: false, medicationType: MedicationType.OVER_THE_COUNTER)));
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('shows pending message for inactive medication', (tester) async {
      await tester.pumpWidget(
          makeCard(_makeMed(isActive: false)));
      expect(find.textContaining('pending caregiver approval'), findsOneWidget);
    });

    testWidgets('shows pending_outlined icon for inactive medication',
        (tester) async {
      await tester.pumpWidget(makeCard(_makeMed(isActive: false)));
      expect(find.byIcon(Icons.pending_outlined), findsOneWidget);
    });

    testWidgets('does not show pending message for active medication',
        (tester) async {
      await tester.pumpWidget(makeCard(_makeMed(isActive: true)));
      expect(find.byIcon(Icons.pending_outlined), findsNothing);
    });
  });
}
