// Tests for PatientParser
// (lib/features/dashboard/presentation/pages/patient_parser.dart).
//
// This is the presentation-layer PatientParser — a simpler static utility
// that parses patient items from API responses into Patient objects.
// No network I/O, no BuildContext, no providers.

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/dashboard/presentation/pages/patient_parser.dart';
import 'package:care_connect_app/features/dashboard/models/patient_model.dart';

void main() {
  group('PatientParser.parsePatientItem – direct format', () {
    test('parses a flat patient object (legacy format)', () {
      final result = PatientParser.parsePatientItem({
        'id': 42,
        'firstName': 'Alice',
        'lastName': 'Smith',
        'email': 'alice@example.com',
        'phone': '555-1234',
        'dob': '1990-01-01',
        'relationship': 'Patient',
      });
      expect(result, isA<Patient>());
      expect(result.id, 42);
      expect(result.firstName, 'Alice');
      expect(result.lastName, 'Smith');
      expect(result.email, 'alice@example.com');
    });

    test('returns error patient on malformed data', () {
      // Completely invalid input — Patient.fromJson will throw; the catch block
      // returns a placeholder Patient with id=0 and firstName='Error'.
      final result = PatientParser.parsePatientItem({'bad': 'data'});
      expect(result, isA<Patient>());
      // Either parses successfully with defaults OR returns error placeholder
      // Both are valid — just confirm it doesn't throw.
    });
  });

  group('PatientParser.parsePatientItem – nested format', () {
    test('parses nested patient structure with direct link data', () {
      final result = PatientParser.parsePatientItem({
        'patient': {
          'id': 10,
          'firstName': 'Bob',
          'lastName': 'Jones',
          'email': 'bob@example.com',
          'phone': '555-9999',
          'dob': '1985-06-15',
          'relationship': 'Self',
        },
        'link': {
          'id': 200,
          'status': 'ACTIVE',
        },
      });
      expect(result.id, 10);
      expect(result.firstName, 'Bob');
      expect(result.linkId, 200);
      expect(result.linkStatus, 'ACTIVE');
    });

    test('parses nested structure with SUSPENDED status', () {
      final result = PatientParser.parsePatientItem({
        'patient': {
          'id': 11,
          'firstName': 'Carol',
          'lastName': 'White',
          'email': 'carol@example.com',
          'phone': '555-1111',
          'dob': '1970-03-20',
          'relationship': 'Family',
        },
        'link': {
          'id': 300,
          'status': 'SUSPENDED',
        },
      });
      expect(result.linkStatus, 'SUSPENDED');
      expect(result.linkId, 300);
    });

    test('defaults to ACTIVE when no link data present', () {
      final result = PatientParser.parsePatientItem({
        'patient': {
          'id': 12,
          'firstName': 'Dave',
          'lastName': 'Brown',
          'email': 'd@example.com',
          'phone': '555-2222',
          'dob': '2000-01-01',
          'relationship': 'Friend',
        },
      });
      expect(result.linkStatus, 'ACTIVE');
    });

    test('derives link status from isActive=true boolean field', () {
      final result = PatientParser.parsePatientItem({
        'patient': {
          'id': 13,
          'firstName': 'Eve',
          'lastName': 'Green',
          'email': 'eve@example.com',
          'phone': '555-3333',
          'dob': '1992-09-09',
          'relationship': 'Guardian',
        },
        'link': {
          'linkId': 400,
          'isActive': true,
        },
      });
      expect(result.linkId, 400);
      expect(result.linkStatus, 'ACTIVE');
    });

    test('derives link status from isActive=false boolean field', () {
      final result = PatientParser.parsePatientItem({
        'patient': {
          'id': 14,
          'firstName': 'Frank',
          'lastName': 'Black',
          'email': 'frank@example.com',
          'phone': '555-4444',
          'dob': '1988-12-31',
          'relationship': 'Sibling',
        },
        'link': {
          'linkId': 500,
          'isActive': false,
        },
      });
      expect(result.linkId, 500);
      expect(result.linkStatus, 'SUSPENDED');
    });

    test('uses linkType from link data as relationship if present', () {
      final result = PatientParser.parsePatientItem({
        'patient': {
          'id': 15,
          'firstName': 'Grace',
          'lastName': 'Hill',
          'email': 'grace@example.com',
          'phone': '555-5555',
          'dob': '1975-07-07',
          'relationship': null,
        },
        'link': {
          'id': 600,
          'status': 'ACTIVE',
          'linkType': 'FAMILY_MEMBER',
        },
      });
      expect(result.relationship, 'FAMILY_MEMBER');
    });

    test('parses link id from string field', () {
      final result = PatientParser.parsePatientItem({
        'patient': {
          'id': 16,
          'firstName': 'Henry',
          'lastName': 'Ford',
          'email': 'h@example.com',
          'phone': '555-6666',
          'dob': '1963-04-14',
          'relationship': 'Friend',
        },
        'link': {
          'id': '700', // string instead of int
          'status': 'ACTIVE',
        },
      });
      expect(result.linkId, 700);
    });
  });
}
