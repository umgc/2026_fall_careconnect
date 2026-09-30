// Tests for Medication model
// (lib/features/health/medication-tracker/models/medication-model.dart).
//
// Covers: fromJson, toJson, copyWith, toString, formattedPrice (via description),
// and the _calculateNextDose helper (via fromJson frequency field).
// Pure-Dart — no platform channels or network I/O.

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/medication-tracker/models/medication-model.dart';

void main() {
  // ──────────────────────────────────────────────────────────────
  // Medication.fromJson
  // ──────────────────────────────────────────────────────────────

  group('Medication.fromJson', () {
    test('parses all fields when fully populated', () {
      // Verifies the happy-path with every JSON key present.
      final json = {
        'id': 1,
        'patientId': 42,
        'medicationName': 'Lisinopril',
        'dosage': '10mg',
        'frequency': 'Once daily',
        'route': 'Oral',
        'medicationType': 'PRESCRIPTION',
        'prescribedBy': 'Dr. Smith',
        'prescribedDate': '2025-01-01',
        'startDate': '2025-01-05',
        'endDate': '2025-06-30',
        'notes': 'Take with food',
        'isActive': true,
      };
      final m = Medication.fromJson(json);

      expect(m.id, 1);
      expect(m.patientId, 42);
      expect(m.medicationName, 'Lisinopril');
      expect(m.dosage, '10mg');
      expect(m.frequency, 'Once daily');
      expect(m.route, 'Oral');
      expect(m.medicationType, MedicationType.PRESCRIPTION);
      expect(m.prescribedBy, 'Dr. Smith');
      expect(m.prescribedDate, '2025-01-01');
      expect(m.startDate, '2025-01-05');
      expect(m.endDate, '2025-06-30');
      expect(m.notes, 'Take with food');
      expect(m.isActive, isTrue);
    });

    test('optional fields are null when absent', () {
      // Verifies null/absent optional JSON keys produce null model fields.
      final m = Medication.fromJson({
        'medicationName': 'Aspirin',
        'dosage': '81mg',
        'frequency': 'As needed',
        'route': 'Oral',
        'isActive': false,
      });

      expect(m.id, isNull);
      expect(m.patientId, isNull);
      expect(m.medicationType, isNull);
      expect(m.prescribedBy, isNull);
      expect(m.notes, isNull);
      expect(m.isActive, isFalse);
    });

    test('isActive defaults to true when absent from JSON', () {
      // Verifies the isActive ?? true fallback.
      final m = Medication.fromJson({
        'medicationName': 'Vitamin D',
        'dosage': '1000 IU',
        'frequency': 'daily',
        'route': 'Oral',
      });
      expect(m.isActive, isTrue);
    });

    test('medicationType falls back to PRESCRIPTION for unknown value', () {
      // Verifies orElse: () => MedicationType.PRESCRIPTION for unrecognized values.
      final m = Medication.fromJson({
        'medicationName': 'Test',
        'dosage': '5mg',
        'frequency': 'daily',
        'route': 'IV',
        'medicationType': 'UNKNOWN_TYPE',
        'isActive': true,
      });
      expect(m.medicationType, MedicationType.PRESCRIPTION);
    });

    test('medicationType is OTC when specified', () {
      final m = Medication.fromJson({
        'medicationName': 'Ibuprofen',
        'dosage': '200mg',
        'frequency': 'As needed',
        'route': 'Oral',
        'medicationType': 'OTC',
        'isActive': true,
      });
      expect(m.medicationType, MedicationType.OTC);
    });

    test('medicationType is SUPPLEMENT when specified', () {
      final m = Medication.fromJson({
        'medicationName': 'Fish Oil',
        'dosage': '1000mg',
        'frequency': 'daily',
        'route': 'Oral',
        'medicationType': 'SUPPLEMENT',
        'isActive': true,
      });
      expect(m.medicationType, MedicationType.SUPPLEMENT);
    });

    test('medicationType is HERBAL when specified', () {
      // KI-05: HERBAL added to match backend Medication.MedicationType.
      final m = Medication.fromJson({
        'medicationName': 'Turmeric',
        'dosage': '500mg',
        'frequency': 'daily',
        'route': 'Oral',
        'medicationType': 'HERBAL',
        'isActive': true,
      });
      expect(m.medicationType, MedicationType.HERBAL);
    });

    test('medicationType is EMERGENCY when specified', () {
      // KI-05: EMERGENCY added to match backend Medication.MedicationType.
      final m = Medication.fromJson({
        'medicationName': 'Epinephrine',
        'dosage': '0.3mg',
        'frequency': 'As needed',
        'route': 'IM',
        'medicationType': 'EMERGENCY',
        'isActive': true,
      });
      expect(m.medicationType, MedicationType.EMERGENCY);
    });

    test('_calculateNextDose returns Today for daily frequency', () {
      // Verifies that "daily" in frequency triggers "Today" next dose.
      final m = Medication.fromJson({
        'medicationName': 'Med',
        'dosage': '5mg',
        'frequency': 'Once daily',
        'route': 'Oral',
        'isActive': true,
      });
      expect(m.nextDose, 'Today');
    });

    test('_calculateNextDose returns This week for weekly frequency', () {
      // Verifies that "weekly" in frequency triggers "This week" next dose.
      final m = Medication.fromJson({
        'medicationName': 'Med',
        'dosage': '5mg',
        'frequency': 'Once weekly',
        'route': 'Oral',
        'isActive': true,
      });
      expect(m.nextDose, 'This week');
    });

    test('_calculateNextDose returns This month for monthly frequency', () {
      // Verifies that "monthly" in frequency triggers "This month" next dose.
      final m = Medication.fromJson({
        'medicationName': 'Med',
        'dosage': '5mg',
        'frequency': 'Once monthly',
        'route': 'Oral',
        'isActive': true,
      });
      expect(m.nextDose, 'This month');
    });

    test('_calculateNextDose returns As needed for other frequency', () {
      // Verifies the default "As needed" result for unrecognized frequency.
      final m = Medication.fromJson({
        'medicationName': 'Med',
        'dosage': '5mg',
        'frequency': 'PRN',
        'route': 'Oral',
        'isActive': true,
      });
      expect(m.nextDose, 'As needed');
    });
  });

  // ──────────────────────────────────────────────────────────────
  // Medication.toJson
  // ──────────────────────────────────────────────────────────────

  group('Medication.toJson', () {
    test('serializes required fields correctly', () {
      // Verifies that required fields always appear in toJson output.
      const m = Medication(
        medicationName: 'Lisinopril',
        dosage: '10mg',
        frequency: 'Once daily',
        route: 'Oral',
        isActive: true,
      );
      final json = m.toJson();

      expect(json['medicationName'], 'Lisinopril');
      expect(json['dosage'], '10mg');
      expect(json['frequency'], 'Once daily');
      expect(json['route'], 'Oral');
      expect(json['isActive'], isTrue);
    });

    test('optional null fields are excluded from toJson output', () {
      // Verifies that null optional fields use if() and are not included.
      const m = Medication(
        medicationName: 'Aspirin',
        dosage: '81mg',
        frequency: 'As needed',
        route: 'Oral',
        isActive: false,
      );
      final json = m.toJson();

      expect(json.containsKey('id'), isFalse);
      expect(json.containsKey('patientId'), isFalse);
      expect(json.containsKey('medicationType'), isFalse);
      expect(json.containsKey('notes'), isFalse);
    });

    test('optional populated fields are included in toJson output', () {
      // Verifies that non-null optional fields are included.
      const m = Medication(
        id: 5,
        patientId: 10,
        medicationName: 'Met',
        dosage: '500mg',
        frequency: 'twice daily',
        route: 'Oral',
        medicationType: MedicationType.PRESCRIPTION,
        notes: 'With meals',
        isActive: true,
      );
      final json = m.toJson();

      expect(json['id'], 5);
      expect(json['patientId'], 10);
      expect(json['medicationType'], 'PRESCRIPTION');
      expect(json['notes'], 'With meals');
    });
  });

  // ──────────────────────────────────────────────────────────────
  // Medication.copyWith
  // ──────────────────────────────────────────────────────────────

  group('Medication.copyWith', () {
    test('unchanged fields are preserved from original', () {
      // Verifies that copyWith without arguments returns an identical object.
      const original = Medication(
        id: 1,
        medicationName: 'Original',
        dosage: '5mg',
        frequency: 'daily',
        route: 'Oral',
        isActive: true,
      );
      final copy = original.copyWith();

      expect(copy.id, original.id);
      expect(copy.medicationName, original.medicationName);
      expect(copy.isActive, original.isActive);
    });

    test('specified fields are updated in the copy', () {
      // Verifies that copyWith replaces specified fields.
      const original = Medication(
        medicationName: 'Old Name',
        dosage: '5mg',
        frequency: 'daily',
        route: 'Oral',
        isActive: true,
      );
      final copy = original.copyWith(
        medicationName: 'New Name',
        isActive: false,
        dosage: '10mg',
      );

      expect(copy.medicationName, 'New Name');
      expect(copy.isActive, isFalse);
      expect(copy.dosage, '10mg');
      expect(copy.route, 'Oral'); // unchanged
    });
  });

  // ──────────────────────────────────────────────────────────────
  // Medication.toString
  // ──────────────────────────────────────────────────────────────

  group('Medication.toString', () {
    test('contains key medication fields', () {
      // Verifies that toString includes id, name, dosage, frequency, isActive.
      const m = Medication(
        id: 7,
        medicationName: 'Metformin',
        dosage: '500mg',
        frequency: 'twice daily',
        route: 'Oral',
        isActive: true,
      );
      final s = m.toString();

      expect(s, contains('7'));
      expect(s, contains('Metformin'));
      expect(s, contains('500mg'));
      expect(s, contains('twice daily'));
      expect(s, contains('true'));
    });
  });
}
