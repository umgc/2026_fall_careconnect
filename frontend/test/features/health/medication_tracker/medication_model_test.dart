// Tests for Medication model (lib/features/health/medication-tracker/models/medication-model.dart).
// Pure Dart class with constructor, fromJson, toJson, copyWith, toString, and enums.

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/medication-tracker/models/medication-model.dart';

Medication _basic() => const Medication(
      medicationName: 'Aspirin',
      dosage: '100mg',
      frequency: 'Daily',
      route: 'Oral',
      isActive: true,
    );

void main() {
  group('MedicationType enum', () {
  });

  group('MedicationStatus enum', () {
    test('has upcoming, taken, missed', () {
      expect(MedicationStatus.values, containsAll([
        MedicationStatus.upcoming,
        MedicationStatus.taken,
        MedicationStatus.missed,
      ]));
    });
  });

  group('Medication constructor', () {
    test('stores required fields', () {
      final med = _basic();
      expect(med.medicationName, 'Aspirin');
      expect(med.dosage, '100mg');
      expect(med.frequency, 'Daily');
      expect(med.route, 'Oral');
      expect(med.isActive, isTrue);
    });

    test('optional fields default to null', () {
      final med = _basic();
      expect(med.id, isNull);
      expect(med.patientId, isNull);
      expect(med.medicationType, isNull);
      expect(med.prescribedBy, isNull);
      expect(med.notes, isNull);
      expect(med.status, isNull);
    });
  });

  group('Medication.fromJson', () {
    test('parses required fields', () {
      final med = Medication.fromJson({
        'medicationName': 'Lisinopril',
        'dosage': '10mg',
        'frequency': 'Daily',
        'route': 'Oral',
        'isActive': true,
      });
      expect(med.medicationName, 'Lisinopril');
      expect(med.dosage, '10mg');
      expect(med.isActive, isTrue);
    });

    test('parses optional id and patientId', () {
      final med = Medication.fromJson({
        'id': 42,
        'patientId': 7,
        'medicationName': 'X',
        'dosage': '5mg',
        'frequency': 'Weekly',
        'route': 'IV',
        'isActive': false,
      });
      expect(med.id, 42);
      expect(med.patientId, 7);
      expect(med.isActive, isFalse);
    });

    test('parses medicationType PRESCRIPTION', () {
      final med = Medication.fromJson({
        'medicationName': 'X',
        'dosage': '1mg',
        'frequency': 'Daily',
        'route': 'Oral',
        'medicationType': 'PRESCRIPTION',
        'isActive': true,
      });
      expect(med.medicationType, MedicationType.PRESCRIPTION);
    });

    test('isActive defaults to true when missing', () {
      final med = Medication.fromJson({
        'medicationName': 'Y',
        'dosage': '2mg',
        'frequency': 'Monthly',
        'route': 'Topical',
      });
      expect(med.isActive, isTrue);
    });

    test('calculates nextDose as Today for daily frequency', () {
      final med = Medication.fromJson({
        'medicationName': 'Z',
        'dosage': '5mg',
        'frequency': 'Once daily',
        'route': 'Oral',
        'isActive': true,
      });
      expect(med.nextDose, 'Today');
    });

    test('calculates nextDose as This week for weekly frequency', () {
      final med = Medication.fromJson({
        'medicationName': 'W',
        'dosage': '10mg',
        'frequency': 'Weekly dose',
        'route': 'Oral',
        'isActive': true,
      });
      expect(med.nextDose, 'This week');
    });

    test('calculates nextDose as This month for monthly frequency', () {
      final med = Medication.fromJson({
        'medicationName': 'V',
        'dosage': '100mg',
        'frequency': 'Monthly injection',
        'route': 'IV',
        'isActive': true,
      });
      expect(med.nextDose, 'This month');
    });

    test('calculates nextDose as As needed for other frequencies', () {
      final med = Medication.fromJson({
        'medicationName': 'U',
        'dosage': '50mg',
        'frequency': 'As required',
        'route': 'Oral',
        'isActive': true,
      });
      expect(med.nextDose, 'As needed');
    });
  });

  group('Medication.toJson', () {
    test('includes required fields', () {
      final json = _basic().toJson();
      expect(json['medicationName'], 'Aspirin');
      expect(json['dosage'], '100mg');
      expect(json['frequency'], 'Daily');
      expect(json['route'], 'Oral');
      expect(json['isActive'], isTrue);
    });

    test('omits null optional fields', () {
      final json = _basic().toJson();
      expect(json.containsKey('id'), isFalse);
      expect(json.containsKey('patientId'), isFalse);
      expect(json.containsKey('medicationType'), isFalse);
      expect(json.containsKey('notes'), isFalse);
    });

    test('includes medicationType when set', () {
      final med = const Medication(
        medicationName: 'A',
        dosage: '1mg',
        frequency: 'Daily',
        route: 'Oral',
        isActive: true,
        medicationType: MedicationType.SUPPLEMENT,
      );
      expect(med.toJson()['medicationType'], 'SUPPLEMENT');
    });
  });

  group('Medication.copyWith', () {
    test('copies unchanged fields', () {
      final med = _basic();
      final copy = med.copyWith();
      expect(copy.medicationName, med.medicationName);
      expect(copy.isActive, med.isActive);
    });

    test('overrides specified fields', () {
      final med = _basic();
      final copy = med.copyWith(dosage: '200mg', isActive: false);
      expect(copy.dosage, '200mg');
      expect(copy.isActive, isFalse);
      expect(copy.medicationName, med.medicationName);
    });
  });

  group('Medication.toString', () {
    test('contains medication name', () {
      expect(_basic().toString(), contains('Aspirin'));
    });
  });
}
