// Tests for Medication model, MedicationType, and MedicationStatus enums.
// (lib/features/health/medication-tracker/models/medication-model.dart)
//
// Covers: constructor, fromJson, toJson, copyWith, _calculateNextDose,
// enum values, toString.

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/medication-tracker/models/medication-model.dart';

void main() {
  // =========================================================================
  // Enums
  // =========================================================================

  group('MedicationType enum', () {
    test('has 3 values', () {
      expect(MedicationType.values.length, 3);
    });

    test('contains PRESCRIPTION, OTC, SUPPLEMENT', () {
      expect(MedicationType.values, contains(MedicationType.PRESCRIPTION));
      expect(MedicationType.values, contains(MedicationType.OTC));
      expect(MedicationType.values, contains(MedicationType.SUPPLEMENT));
    });
  });

  group('MedicationStatus enum', () {
    test('has 3 values', () {
      expect(MedicationStatus.values.length, 3);
    });

    test('contains upcoming, taken, missed', () {
      expect(MedicationStatus.values, contains(MedicationStatus.upcoming));
      expect(MedicationStatus.values, contains(MedicationStatus.taken));
      expect(MedicationStatus.values, contains(MedicationStatus.missed));
    });
  });

  // =========================================================================
  // Constructor
  // =========================================================================

  group('Medication constructor', () {
    test('sets required fields', () {
      const med = Medication(
        medicationName: 'Lisinopril',
        dosage: '10mg',
        frequency: 'Once daily',
        route: 'Oral',
        isActive: true,
      );

      expect(med.medicationName, 'Lisinopril');
      expect(med.dosage, '10mg');
      expect(med.frequency, 'Once daily');
      expect(med.route, 'Oral');
      expect(med.isActive, true);
    });

    test('optional fields default to null', () {
      const med = Medication(
        medicationName: 'Test',
        dosage: '5mg',
        frequency: 'daily',
        route: 'Oral',
        isActive: true,
      );

      expect(med.id, isNull);
      expect(med.patientId, isNull);
      expect(med.medicationType, isNull);
      expect(med.prescribedBy, isNull);
      expect(med.endDate, isNull);
      expect(med.notes, isNull);
      expect(med.status, isNull);
    });

    test('with all optional fields', () {
      const med = Medication(
        id: 42,
        patientId: 10,
        medicationName: 'Metformin',
        dosage: '500mg',
        frequency: 'Twice daily',
        route: 'Oral',
        medicationType: MedicationType.PRESCRIPTION,
        prescribedBy: 'Dr. Smith',
        prescribedDate: '2026-01-15',
        startDate: '2026-01-20',
        endDate: '2026-07-20',
        notes: 'Take with food',
        isActive: true,
        status: MedicationStatus.upcoming,
        nextDose: 'Today',
      );

      expect(med.id, 42);
      expect(med.prescribedBy, 'Dr. Smith');
      expect(med.endDate, '2026-07-20');
      expect(med.notes, 'Take with food');
      expect(med.status, MedicationStatus.upcoming);
    });
  });

  // =========================================================================
  // fromJson
  // =========================================================================

  group('Medication.fromJson', () {
    test('parses all fields from complete JSON', () {
      final json = {
        'id': 1,
        'patientId': 10,
        'medicationName': 'Aspirin',
        'dosage': '81mg',
        'frequency': 'Once daily',
        'route': 'Oral',
        'medicationType': 'OTC',
        'prescribedBy': 'Dr. Jones',
        'prescribedDate': '2026-01-01',
        'startDate': '2026-01-05',
        'endDate': null,
        'notes': 'Low dose',
        'isActive': true,
      };

      final med = Medication.fromJson(json);

      expect(med.id, 1);
      expect(med.patientId, 10);
      expect(med.medicationName, 'Aspirin');
      expect(med.dosage, '81mg');
      expect(med.medicationType, MedicationType.OTC);
      expect(med.prescribedBy, 'Dr. Jones');
      expect(med.isActive, true);
    });

    test('isActive defaults to true when null', () {
      final json = {
        'medicationName': 'Test',
        'dosage': '5mg',
        'frequency': 'daily',
        'route': 'Oral',
      };
      expect(Medication.fromJson(json).isActive, true);
    });

    test('medicationType null when not in JSON', () {
      final json = {
        'medicationName': 'Test',
        'dosage': '5mg',
        'frequency': 'daily',
        'route': 'Oral',
      };
      expect(Medication.fromJson(json).medicationType, isNull);
    });

    test('medicationType falls back to PRESCRIPTION for unknown value', () {
      final json = {
        'medicationName': 'Test',
        'dosage': '5mg',
        'frequency': 'daily',
        'route': 'Oral',
        'medicationType': 'UNKNOWN_TYPE',
      };
      expect(Medication.fromJson(json).medicationType, MedicationType.PRESCRIPTION);
    });

    test('nextDose calculated as Today for daily frequency', () {
      final json = {
        'medicationName': 'Test',
        'dosage': '5mg',
        'frequency': 'Once daily',
        'route': 'Oral',
      };
      expect(Medication.fromJson(json).nextDose, 'Today');
    });

    test('nextDose calculated as This week for weekly frequency', () {
      final json = {
        'medicationName': 'Test',
        'dosage': '5mg',
        'frequency': 'Weekly',
        'route': 'Oral',
      };
      expect(Medication.fromJson(json).nextDose, 'This week');
    });

    test('nextDose calculated as This month for monthly frequency', () {
      final json = {
        'medicationName': 'Test',
        'dosage': '5mg',
        'frequency': 'Monthly',
        'route': 'Oral',
      };
      expect(Medication.fromJson(json).nextDose, 'This month');
    });

    test('nextDose calculated as As needed for other frequency', () {
      final json = {
        'medicationName': 'Test',
        'dosage': '5mg',
        'frequency': 'As needed',
        'route': 'Oral',
      };
      expect(Medication.fromJson(json).nextDose, 'As needed');
    });
  });

  // =========================================================================
  // toJson
  // =========================================================================

  group('Medication.toJson', () {
    test('includes required fields', () {
      const med = Medication(
        medicationName: 'Lisinopril',
        dosage: '10mg',
        frequency: 'Once daily',
        route: 'Oral',
        isActive: true,
      );

      final json = med.toJson();

      expect(json['medicationName'], 'Lisinopril');
      expect(json['dosage'], '10mg');
      expect(json['frequency'], 'Once daily');
      expect(json['route'], 'Oral');
      expect(json['isActive'], true);
    });

    test('omits null optional fields', () {
      const med = Medication(
        medicationName: 'Test',
        dosage: '5mg',
        frequency: 'daily',
        route: 'Oral',
        isActive: true,
      );

      final json = med.toJson();

      expect(json.containsKey('id'), false);
      expect(json.containsKey('patientId'), false);
      expect(json.containsKey('prescribedBy'), false);
      expect(json.containsKey('endDate'), false);
      expect(json.containsKey('notes'), false);
      expect(json.containsKey('medicationType'), false);
    });

    test('includes optional fields when set', () {
      const med = Medication(
        id: 5,
        patientId: 10,
        medicationName: 'Metformin',
        dosage: '500mg',
        frequency: 'Twice daily',
        route: 'Oral',
        medicationType: MedicationType.PRESCRIPTION,
        prescribedBy: 'Dr. Smith',
        notes: 'Take with meals',
        isActive: true,
      );

      final json = med.toJson();

      expect(json['id'], 5);
      expect(json['patientId'], 10);
      expect(json['medicationType'], 'PRESCRIPTION');
      expect(json['prescribedBy'], 'Dr. Smith');
      expect(json['notes'], 'Take with meals');
    });

    test('does not include UI-only fields (status, nextDose)', () {
      const med = Medication(
        medicationName: 'Test',
        dosage: '5mg',
        frequency: 'daily',
        route: 'Oral',
        isActive: true,
        status: MedicationStatus.taken,
        nextDose: 'Today',
      );

      final json = med.toJson();
      expect(json.containsKey('status'), false);
      expect(json.containsKey('nextDose'), false);
    });
  });

  // =========================================================================
  // copyWith
  // =========================================================================

  group('Medication.copyWith', () {
    test('creates copy with updated name', () {
      const original = Medication(
        medicationName: 'Aspirin',
        dosage: '81mg',
        frequency: 'daily',
        route: 'Oral',
        isActive: true,
      );

      final copy = original.copyWith(medicationName: 'Ibuprofen');
      expect(copy.medicationName, 'Ibuprofen');
      expect(copy.dosage, '81mg'); // unchanged
    });

    test('creates copy with changed isActive', () {
      const original = Medication(
        medicationName: 'Test',
        dosage: '5mg',
        frequency: 'daily',
        route: 'Oral',
        isActive: true,
      );

      final inactive = original.copyWith(isActive: false);
      expect(inactive.isActive, false);
      expect(inactive.medicationName, 'Test');
    });

    test('preserves all fields when no changes', () {
      const original = Medication(
        id: 1,
        medicationName: 'Test',
        dosage: '5mg',
        frequency: 'daily',
        route: 'Oral',
        isActive: true,
        notes: 'Keep refrigerated',
      );

      final copy = original.copyWith();
      expect(copy.id, 1);
      expect(copy.notes, 'Keep refrigerated');
    });
  });

  // =========================================================================
  // toString
  // =========================================================================

  group('Medication.toString', () {
    test('includes key fields', () {
      const med = Medication(
        id: 42,
        medicationName: 'Lisinopril',
        dosage: '10mg',
        frequency: 'daily',
        route: 'Oral',
        isActive: true,
      );

      final str = med.toString();
      expect(str, contains('Lisinopril'));
      expect(str, contains('10mg'));
      expect(str, contains('42'));
      expect(str, contains('true'));
    });
  });
}
