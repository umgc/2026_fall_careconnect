// IdentityConflict and IdentityCheck (M3 feedback): one more detail from the
// new record (phone, else email, else ZIP code) that the patient confirms
// before choosing a date of birth. Only a hidden form of it is ever kept.

import 'package:care_connect_app/features/health/health_data/models/identity_conflict.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TC-EHR-REC-077: fromJson reads the check in camelCase and '
      'snake_case, for each type', () {
    final phone = IdentityConflict.fromJson({
      'identityCheck': {'type': 'PHONE', 'value': '4821'}
    }).identityCheck!;
    expect(phone.type, IdentityCheckType.phone);
    expect(phone.value, '4821');

    final email = IdentityConflict.fromJson({
      'identity_check': {'type': 'email', 'value': 'j•••@gmail.com'}
    }).identityCheck!;
    expect(email.type, IdentityCheckType.email);
    expect(email.value, 'j•••@gmail.com');

    final zip = IdentityConflict.fromJson({
      'identityCheck': {'type': 'ZIP', 'value': '21201'}
    }).identityCheck!;
    expect(zip.type, IdentityCheckType.zip);
    expect(zip.value, '21201');
  });

  test('TC-EHR-REC-078: full values from the backend are hidden before '
      'they are kept', () {
    IdentityCheck? read(String type, Object value) => IdentityConflict.fromJson({
          'identityCheck': {'type': type, 'value': value}
        }).identityCheck;
    expect(read('PHONE', '+1 (555) 010-4821')!.value, '4821');
    expect(read('PHONE', 5550104821)!.value, '4821');
    expect(read('EMAIL', 'jane.doe@gmail.com')!.value,
        'j•••@gmail.com');
    expect(read('ZIP', '21201-1234')!.value, '21201');
    expect(read('ZIP', '212011234')!.value, '21201');
  });

  test('TC-EHR-REC-079: a missing, unknown or unusable check means no '
      'check', () {
    expect(IdentityConflict.fromJson({}).identityCheck, isNull);
    expect(IdentityConflict.fromJson({'identityCheck': null}).identityCheck,
        isNull);
    expect(IdentityConflict.fromJson({'identityCheck': 'PHONE'}).identityCheck,
        isNull);
    expect(
        IdentityConflict.fromJson({
          'identityCheck': {'type': 'SSN', 'value': '1234'}
        }).identityCheck,
        isNull);
    expect(IdentityCheck.of(IdentityCheckType.phone, '12-3'), isNull);
    expect(IdentityCheck.of(IdentityCheckType.phone, null), isNull);
    expect(IdentityCheck.of(IdentityCheckType.email, 'not-an-email'), isNull);
    expect(IdentityCheck.of(IdentityCheckType.email, '@gmail.com'), isNull);
    expect(IdentityCheck.of(IdentityCheckType.email, 'jane@'), isNull);
    expect(IdentityCheck.of(IdentityCheckType.zip, '2120'), isNull);
    expect(IdentityCheck.of(IdentityCheckType.zip, 'ABCDE'), isNull);
  });

  test('TC-EHR-REC-084: a phone number with an extension shows the last 4 '
      'digits of the number, not of the extension (DEF-EHR-REC-07)', () {
    // ehr_source_identity.phone is the FHIR ContactPoint value as sent, so it
    // can carry an extension.
    for (final raw in [
      '410-555-0123 ext 45',
      '410-555-0123 ext. 45',
      '410-555-0123 extension 45',
      '(410) 555-0123 x45',
      '410.555.0123 X 4567',
      '410-555-0123 #45',
      'tel:+1-410-555-0123;ext=45',
    ]) {
      expect(IdentityCheck.phoneLast4(raw), '0123', reason: raw);
    }
    expect(IdentityCheck.phoneLast4('+1 410 555 0123'), '0123');
    expect(
        IdentityConflict.fromJson({
          'identityCheck': {'type': 'PHONE', 'value': '410-555-0123 ext 45'}
        }).identityCheck!.value,
        '0123');
  });

  test('TC-EHR-REC-080: a conflict built without a check has none', () {
    const c = IdentityConflict(
        id: 1,
        fieldName: 'date_of_birth',
        canonicalValueBefore: '1980-05-14',
        incomingValue: '1985-05-14');
    expect(c.identityCheck, isNull);
    expect(c.fieldLabel, 'Date of birth');
  });
}
