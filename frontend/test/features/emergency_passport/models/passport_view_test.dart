// CC-12 Increment 2: the patient's own passport model and the QR link fix.
// Test Plan §3.27: TC-EMG-264…266 (the pull request's), 292…294 (Testing
// Lead: the backend's real shapes, wrong shapes, scanLink edges, NewQrCode).

import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/emergency_passport/models/passport_view.dart';

import '../passport_test_support.dart';

void main() {
  test('TC-EMG-264: reads sharing, counts and the active code', () {
    final v = PassportView.fromJson(passportJson);
    expect(v.name, 'Mary Johnson');
    expect(v.isShared(PassportField.allergies), isTrue);
    expect(v.isShared(PassportField.bloodType), isTrue);
    expect(v.isShared(PassportField.medications), isFalse);
    expect(v.allergyCount, 1);
    expect(v.code!.createdAt, DateTime.parse('2026-10-15T17:11:34.932728Z'));
    expect(v.code!.lastScannedAt, isNull);
    expect(v.ready, isTrue);
  });

  test('TC-EMG-265: no token means no code', () {
    final v = PassportView.fromJson({...passportJson, 'token': null});
    expect(v.code, isNull);
  });

  test('TC-EMG-266: scanLink adds the # the web app needs, once', () {
    expect(scanLink('http://localhost:3000/passport/abc'),
        'http://localhost:3000/#/passport/abc');
    expect(scanLink('https://app.example.org/passport/abc'),
        'https://app.example.org/#/passport/abc');
    expect(scanLink('https://app.example.org/#/passport/abc'),
        'https://app.example.org/#/passport/abc');
  });

  // ---------- Testing Lead ----------

  test(
      'TC-EMG-292: the backend\'s own shapes: a scanned code\'s Instant is read '
      'to the microsecond, an inactive or undated token is no code, and wrong '
      'or missing fields read as nothing shared, nothing counted, not ready',
      () {
    final scanned = PassportView.fromJson({
      ...passportJson,
      'medications': [
        {'name': 'Lisinopril', 'dosage': '10 mg', 'frequency': 'Once daily'},
        {'name': 'Metformin', 'dosage': '500 mg', 'frequency': 'Twice daily'},
      ],
      'token': {
        'active': true,
        'createdAt': '2026-10-15T17:11:34.932728Z',
        'lastScannedAt': '2026-10-16T08:01:02.123456Z',
      },
    });
    expect(scanned.medicationCount, 2);
    expect(scanned.code!.lastScannedAt,
        DateTime.utc(2026, 10, 16, 8, 1, 2, 123, 456));

    for (final token in [
      {'active': false, 'createdAt': '2026-10-15T17:11:34Z'},
      {'active': 'true', 'createdAt': '2026-10-15T17:11:34Z'},
      {'active': true, 'createdAt': 'yesterday'},
      {'active': true},
      'abc',
    ]) {
      expect(PassportView.fromJson({...passportJson, 'token': token}).code,
          isNull,
          reason: '$token');
    }
    final notAString = PassportView.fromJson({
      ...passportJson,
      'token': {
        'active': true,
        'createdAt': '2026-10-15T17:11:34Z',
        'lastScannedAt': 5,
      },
    });
    expect(notAString.code, isNotNull);
    expect(notAString.code!.lastScannedAt, isNull);

    final wrong = PassportView.fromJson({
      'name': null,
      'sharing': ['ALLERGIES'],
      'allergies': 'Penicillin',
      'medications': {'name': 'x'},
      'ready': 'true',
    });
    expect(wrong.name, '');
    expect(PassportField.values.where(wrong.isShared), isEmpty);
    expect(wrong.allergyCount, 0);
    expect(wrong.medicationCount, 0);
    expect(wrong.code, isNull);
    expect(wrong.ready, isFalse);

    final partial = PassportView.fromJson({
      'name': 'Mary Johnson',
      'sharing': {'ALLERGIES': true, 'BLOOD_TYPE': 'yes'},
    });
    expect(PassportField.values.where(partial.isShared),
        [PassportField.allergies]);
    expect(
        const PassportView(name: 'x', sharing: {})
            .isShared(PassportField.bloodType),
        isFalse);
  });

  test(
      'TC-EMG-293: scanLink keeps a site\'s own path, changes only the last '
      '/passport/, and leaves anything that is not a scan link alone', () {
    expect(scanLink('https://example.org/careconnect/passport/abc'),
        'https://example.org/careconnect/#/passport/abc');
    expect(scanLink('https://example.org/passport/x/passport/abc'),
        'https://example.org/passport/x/#/passport/abc');
    expect(scanLink('https://example.org/emergency/abc'),
        'https://example.org/emergency/abc');
    expect(scanLink(''), '');
    // The backend's fixed default (DEF-EMG-07) is already a # link.
    expect(scanLink('http://localhost:3000/#/passport/abc'),
        'http://localhost:3000/#/passport/abc');
  });

  test(
      'TC-EMG-294: a new code\'s answer keeps the server\'s createdAt exactly '
      '(the screen matches it against GET /passport later), fixes the link, '
      'and reads missing fields as empty', () {
    final code = NewQrCode.fromJson({
      'token': 'abc',
      'url': 'http://localhost:3000/passport/abc',
      'createdAt': '2026-10-15T17:11:34.932728Z',
    });
    expect(code.token, 'abc');
    expect(code.url, 'http://localhost:3000/#/passport/abc');
    expect(code.createdAt, DateTime.parse('2026-10-15T17:11:34.932728Z'));

    final before = DateTime.now().toUtc();
    final empty = NewQrCode.fromJson({});
    expect(empty.token, '');
    expect(empty.url, '');
    expect(empty.createdAt.isUtc, isTrue);
    expect(
        empty.createdAt.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse);
  });
}
