import 'package:care_connect_app/features/dashboard/utils/patient_parser.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _patient({Object? id = 7, Object? linkId}) => {
      if (id != null) 'id': id,
      'firstName': 'Jane',
      'lastName': 'Doe',
      'email': 'j@d.com',
      'phone': '555',
      'dob': '1990-01-01',
      'relationship': 'Mother',
      if (linkId != null) 'linkId': linkId,
    };

void main() {
  test('string linkId at top level is parsed', () {
    final p = PatientParser.parsePatientItem({
      'patient': _patient(),
      'linkId': '42',
    });
    expect(p.linkId, 42);
  });

  test('suspended link falls back to linkId in patient data', () {
    final p = PatientParser.parsePatientItem({
      'patient': _patient(linkId: '55'),
      'link': {'status': 'disabled'},
    });
    expect(p.linkId, 55);
    expect(p.linkStatus, 'SUSPENDED');
  });

  test('suspended link with int linkId in patient data', () {
    final p = PatientParser.parsePatientItem({
      'patient': _patient(linkId: 56),
      'link': {'active': false},
    });
    expect(p.linkId, 56);
  });

  test('top-level string id used as linkId when different from patient id',
      () {
    final p = PatientParser.parsePatientItem({
      'id': '900',
      'patient': _patient(),
      'link': {'status': 'inactive'},
    });
    expect(p.linkId, 900);
  });

  test('nested link status and unknown status value', () {
    final nested = PatientParser.parsePatientItem({
      'patient': _patient(),
      'link': {
        'link': {'status': 'pending'},
      },
    });
    expect(nested.linkStatus, 'PENDING');

    final nestedNull = PatientParser.parsePatientItem({
      'patient': _patient(),
      'link': {
        'link': {'status': null, 'id': 'abc'},
      },
    });
    expect(nestedNull.linkStatus, 'ACTIVE');
  });
}
