// MedicalPassport and friends parse what GET /v1/api/passport returns
// (backend PassportDtos.PassportView) and build the PUT /profile body.
//
// Test Plan §3.28: TC-EMG-335…343 are the author's; TC-EMG-376 is the
// Testing Lead's.

import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/medical_passport/models/medical_passport.dart';

Map<String, dynamic> _full() => {
      'name': 'Jordan Miller',
      'age': 41,
      'bloodType': 'O_POSITIVE',
      'chronicConditions': 'Type 2 diabetes',
      'emergencyContact': {
        'name': 'Taylor Miller',
        'relationship': 'Spouse',
        'phone': '(415) 555-0184',
      },
      'allergies': [
        {'allergen': 'Penicillin', 'severity': 'SEVERE', 'reaction': 'Anaphylaxis'},
      ],
      'medications': [
        {'name': 'Lisinopril', 'dosage': '10 mg', 'frequency': 'Once daily'},
      ],
      'sharing': {
        'ALLERGIES': true,
        'MEDICATIONS': false,
        'CHRONIC_CONDITIONS': false,
        'BLOOD_TYPE': true,
        'EMERGENCY_CONTACT': false,
      },
      'token': {
        'active': true,
        'createdAt': '2026-10-01T12:00:00Z',
        'lastScannedAt': null,
      },
      'ready': true,
      'lastUpdated': '2026-07-01T09:00:00Z',
      'lastUpdatedBySection': {
        'ALLERGIES': '2026-05-01T09:00:00Z',
        'MEDICATIONS': '2026-07-01T09:00:00Z',
      },
    };

void main() {
  group('MedicalPassport.fromJson', () {
    test('TC-EMG-335: reads every field of a full passport', () {
      final p = MedicalPassport.fromJson(_full());

      expect(p.name, 'Jordan Miller');
      expect(p.age, 41);
      expect(p.bloodType, BloodType.oPositive);
      expect(p.bloodType!.label, 'O+');
      expect(p.chronicConditions, 'Type 2 diabetes');
      expect(p.emergencyContact!.name, 'Taylor Miller');
      expect(p.emergencyContact!.relationship, 'Spouse');
      expect(p.emergencyContact!.phone, '(415) 555-0184');
      expect(p.allergies.single.allergen, 'Penicillin');
      expect(p.allergies.single.severity, 'SEVERE');
      expect(p.allergies.single.reaction, 'Anaphylaxis');
      expect(p.medications.single.name, 'Lisinopril');
      expect(p.medications.single.dosage, '10 mg');
      expect(p.medications.single.frequency, 'Once daily');
      expect(p.isShared(PassportField.allergies), isTrue);
      expect(p.isShared(PassportField.medications), isFalse);
      expect(p.hasCode, isTrue);
      expect(p.code!.createdAt, DateTime.utc(2026, 10, 1, 12).toLocal());
      expect(p.code!.lastScannedAt, isNull);
      expect(p.ready, isTrue);
      expect(p.lastUpdated, DateTime.utc(2026, 7, 1, 9).toLocal());
      expect(p.lastUpdatedBySection, {
        PassportField.allergies: DateTime.utc(2026, 5, 1, 9).toLocal(),
        PassportField.medications: DateTime.utc(2026, 7, 1, 9).toLocal(),
      });
      expect(p.initials, 'JM');
    });

    test('TC-EMG-336: a new passport with nothing set reads as empty, not shared and not ready', () {
      final p = MedicalPassport.fromJson({
        'name': 'Sam',
        'age': null,
        'bloodType': null,
        'chronicConditions': null,
        'emergencyContact': null,
        'allergies': [],
        'medications': [],
        'sharing': {},
        'token': null,
        'ready': false,
        'lastUpdated': null,
        'lastUpdatedBySection': {},
      });

      expect(p.age, isNull);
      expect(p.bloodType, isNull);
      expect(p.emergencyContact, isNull);
      expect(p.allergies, isEmpty);
      expect(p.medications, isEmpty);
      for (final field in PassportField.values) {
        expect(p.isShared(field), isFalse, reason: field.name);
      }
      expect(p.hasCode, isFalse);
      expect(p.ready, isFalse);
      expect(p.lastUpdated, isNull);
      expect(p.initials, 'S');
    });

    test('TC-EMG-337: unknown sharing keys, unknown blood types and bad dates are ignored', () {
      final json = _full()
        ..['bloodType'] = 'Z_POS'
        ..['sharing'] = {'SHOE_SIZE': true, 'ALLERGIES': true}
        ..['lastUpdatedBySection'] = {'ALLERGIES': 'not a date', 'SHOE_SIZE': '2026-01-01T00:00:00Z'};

      final p = MedicalPassport.fromJson(json);

      expect(p.bloodType, isNull);
      expect(p.sharing, {PassportField.allergies: true});
      expect(p.lastUpdatedBySection, isEmpty);
    });

    test('TC-EMG-338: an inactive token is treated as no code', () {
      final json = _full()..['token'] = {'active': false, 'createdAt': '2026-10-01T12:00:00Z'};
      expect(MedicalPassport.fromJson(json).hasCode, isFalse);
    });
  });

  group('enums', () {
    test('TC-EMG-339: every PassportField and BloodType round-trips through its API name', () {
      for (final field in PassportField.values) {
        expect(PassportField.fromApi(field.apiName), field);
      }
      for (final type in BloodType.values) {
        expect(BloodType.fromApi(type.apiName), type);
      }
      expect(PassportField.fromApi('nope'), isNull);
      expect(BloodType.fromApi(null), isNull);
      expect(BloodType.values.map((t) => t.label),
          ['A+', 'A−', 'B+', 'B−', 'AB+', 'AB−', 'O+', 'O−']);
    });
  });

  group('NewPassportCode', () {
    test('TC-EMG-340: reads the one-time token and link', () {
      final code = NewPassportCode.fromJson({
        'token': 'abc',
        'url': 'https://app.example/passport/abc',
        'createdAt': '2026-10-14T23:03:25Z',
      });
      expect(code.token, 'abc');
      expect(code.url, 'https://app.example/passport/abc');
      expect(code.createdAt, DateTime.utc(2026, 10, 14, 23, 3, 25).toLocal());
    });
  });

  group('PassportProfileUpdate', () {
    test('TC-EMG-341: from() carries the current values, so a PUT does not clear what was not edited', () {
      final update = PassportProfileUpdate.from(MedicalPassport.fromJson(_full()));
      expect(update.toJson(), {
        'bloodType': 'O_POSITIVE',
        'chronicConditions': 'Type 2 diabetes',
        'emergencyContactName': 'Taylor Miller',
        'emergencyContactRelationship': 'Spouse',
        'emergencyContactPhone': '(415) 555-0184',
      });
    });

    test('TC-EMG-342: empty fields are sent as null, which clears them', () {
      expect(const PassportProfileUpdate().toJson().values, everyElement(isNull));
    });
  });

  test('TC-EMG-343: initialsOf handles blanks and extra spaces', () {
    expect(initialsOf('  jordan   lee  miller '), 'JM');
    expect(initialsOf(''), '?');
    expect(initialsOf(null), '?');
  });

  test(
      'TC-EMG-376: what the real backend sends parses: an Instant with '
      'microseconds, an age as 41.0, a contact with only a phone, and rows '
      'with nothing but their name', () {
    final p = MedicalPassport.fromJson({
      ..._full(),
      'age': 41.0,
      'emergencyContact': {'name': null, 'relationship': null, 'phone': '555-0100'},
      'allergies': [
        {'allergen': 'Latex', 'severity': null, 'reaction': null},
      ],
      'medications': [
        {'name': 'Aspirin', 'dosage': null, 'frequency': null},
      ],
      'token': {
        'active': true,
        'createdAt': '2026-10-16T09:00:00.123456Z',
        'lastScannedAt': '2026-10-16T21:30:00.5Z',
      },
    });
    expect(p.age, 41);
    expect(p.emergencyContact!.name, isNull);
    expect(p.emergencyContact!.phone, '555-0100');
    expect(p.allergies.single.severity, isNull);
    expect(p.medications.single.dosage, isNull);
    expect(p.code!.createdAt!.toUtc(), DateTime.utc(2026, 10, 16, 9, 0, 0, 123, 456));
    expect(p.code!.createdAt!.isUtc, isFalse, reason: 'shown in local time');
    expect(p.code!.lastScannedAt!.toUtc(), DateTime.utc(2026, 10, 16, 21, 30, 0, 500));
  });
}
