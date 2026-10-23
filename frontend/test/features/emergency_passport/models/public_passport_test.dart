// CC-12 Increment 3: reading the public scan response (GET
// /v1/api/passport/scan/{token}) into PublicPassport. Test Plan §3.26.

import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/emergency_passport/models/public_passport.dart';

void main() {
  test(
      'TC-EMG-230: lastUpdated reads the backend\'s Instant (6 fraction digits, '
      'as PostgreSQL stores it) and a 9-digit one as the same UTC moment; a '
      'date that is not a string, or does not parse, is no date', () {
    DateTime? read(Object? v) =>
        PublicPassport.fromJson({'name': 'A', 'lastUpdated': v}).lastUpdated;

    final micros = read('2026-10-15T00:08:49.521751Z')!;
    expect(micros.isUtc, isTrue);
    expect(micros, DateTime.utc(2026, 10, 15, 0, 8, 49, 521, 751));
    expect(read('2026-10-15T00:08:49.521751000Z'), micros);
    expect(read('not a date'), isNull);
    expect(read(1760487000), isNull);
    expect(read(null), isNull);
  });

  test(
      'TC-EMG-231: blank or whitespace-only text is treated as absent, so a '
      'passport whose only "shared" text is blank shares nothing', () {
    final p = PublicPassport.fromJson({
      'name': 'Jordan Miller',
      'chronicConditions': '   ',
      'allergies': [
        {'allergen': 'Latex', 'severity': null, 'reaction': '  '},
      ],
      'medications': [
        {'name': 'Lisinopril', 'dosage': '', 'frequency': ' '},
      ],
    });
    expect(p.chronicConditions, isNull);
    expect(p.allergies!.single.reaction, isNull);
    expect(p.medications!.single.dosage, isNull);
    expect(p.medications!.single.frequency, isNull);

    final blankOnly =
        PublicPassport.fromJson({'name': 'Jordan Miller', 'chronicConditions': ' '});
    expect(blankOnly.sharesNothing, isTrue);

    final contact = PassportContact.fromJson(
        {'name': ' ', 'relationship': '', 'phone': '\t'});
    expect([contact.name, contact.relationship, contact.phone], [null, null, null]);
  });

  test(
      'TC-EMG-232: a section of the wrong shape is ignored rather than '
      'crashing: a non-list section is absent, non-object items are skipped, '
      'an empty list shares nothing, and a non-object contact is absent', () {
    final p = PublicPassport.fromJson({
      'name': 'Jordan Miller',
      'allergies': 'Penicillin',
      'medications': [
        'Lisinopril',
        42,
        {'name': 'Metformin', 'dosage': '500 mg'},
      ],
      'emergencyContact': 'Taylor Miller',
    });
    expect(p.allergies, isNull);
    expect(p.medications!.map((m) => m.name), ['Metformin']);
    expect(p.emergencyContact, isNull);

    final empty = PublicPassport.fromJson(
        {'name': 'Jordan Miller', 'allergies': [], 'medications': []});
    expect(empty.allergies, isEmpty);
    expect(empty.sharesNothing, isTrue);
  });

  test(
      'TC-EMG-233: a value the page has no label for is shown as sent: an '
      'unknown blood type stays readable, an unknown severity gets no badge, '
      'a whole-number age sent as 41.0 reads 41, and a missing name is empty',
      () {
    expect(bloodTypeLabel('UNKNOWN'), 'UNKNOWN');
    expect(bloodTypeSpoken('UNKNOWN'), 'UNKNOWN');
    expect(bloodTypeLabel('B_WEIRD'), 'BWEIRD');
    expect(bloodTypeLabel('O_NEGATIVE'), 'O−');
    expect(bloodTypeSpoken('O_NEGATIVE'), 'O negative');
    expect(severityLabel('EXTREME'), isNull);
    expect(severityLabel('SEVERE'), 'Severe');
    expect(severityLabel('MODERATE'), 'Moderate');

    final p = PublicPassport.fromJson({'age': 41.0});
    expect(p.age, 41);
    expect(p.name, '');
    expect(PassportAllergy.fromJson({}).allergen, '');
    expect(PassportMedication.fromJson({}).name, '');
  });
}
