// EhrResourceMapper: one EHR list row (EhrResourceListItem, shared by
// /api/ehr/resources and /api/athena/resources) to a HealthRecord.

import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/health/health_data/models/health_record.dart';
import 'package:care_connect_app/features/health/health_data/services/ehr_resource_mapper.dart';

void main() {
  group('sourceFrom', () {
    test('knows every source, ignoring case and spaces', () {
      expect(EhrResourceMapper.sourceFrom('EPIC'), RecordSource.epic);
      expect(EhrResourceMapper.sourceFrom(' cerner '), RecordSource.cerner);
      expect(EhrResourceMapper.sourceFrom('Athena'), RecordSource.athena);
      expect(EhrResourceMapper.sourceFrom('ATHENAHEALTH'), RecordSource.athena);
      expect(EhrResourceMapper.sourceFrom('athenahealth'), RecordSource.athena);
      expect(EhrResourceMapper.sourceFrom('MEDICARE'), RecordSource.medicare);
    });

    test('an unknown or missing source is null, never another source', () {
      for (final s in [null, '', 'ATHENA_HEALTH', 'ALLSCRIPTS', 42]) {
        expect(EhrResourceMapper.sourceFrom(s), isNull, reason: '$s');
      }
    });
  });

  group('recordTypeFrom', () {
    test('the FHIR resource type decides when the app knows it', () {
      const byType = {
        'Condition': RecordType.condition,
        'MedicationRequest': RecordType.medication,
        'MedicationStatement': RecordType.medication,
        'AllergyIntolerance': RecordType.allergy,
        'Encounter': RecordType.appointment,
        'Observation': RecordType.clinicalRecord,
        'DiagnosticReport': RecordType.clinicalRecord,
        'Immunization': RecordType.clinicalRecord,
        'Procedure': RecordType.clinicalRecord,
        'DocumentReference': RecordType.clinicalRecord,
      };
      for (final e in byType.entries) {
        // A category that would say otherwise loses to the resource type.
        expect(
            EhrResourceMapper.recordTypeFrom('Care Context',
                resourceType: e.key),
            e.value,
            reason: e.key);
      }
    });

    test('otherwise the backend category decides', () {
      const byCategory = {
        'Conditions': RecordType.condition,
        'Medications': RecordType.medication,
        'Allergies': RecordType.allergy,
        'Results': RecordType.clinicalRecord,
        'Immunizations': RecordType.clinicalRecord,
        'Procedures': RecordType.clinicalRecord,
        'Documents': RecordType.clinicalRecord,
        'Care Context': RecordType.other,
        'Insurance': RecordType.other,
      };
      for (final e in byCategory.entries) {
        expect(
            EhrResourceMapper.recordTypeFrom(e.key, resourceType: 'CarePlan'),
            e.value,
            reason: e.key);
      }
      expect(EhrResourceMapper.recordTypeFrom(null), RecordType.other);
    });
  });

  group('toHealthRecord', () {
    test('maps every field of the row', () {
      final r = EhrResourceMapper.toHealthRecord({
        'resourceType': 'Condition',
        'resourceId': 'ath-1',
        'category': 'Conditions',
        'title': ' Type 2 diabetes ',
        'status': 'active',
        'occurredAt': '2026-07-01T00:00:00Z',
        'lastSyncedAt': '2026-10-14T12:00:00Z',
        'source': 'ATHENAHEALTH',
      })!;
      expect(r.id, 'ath-1');
      expect(r.sources, [RecordSource.athena]);
      expect(r.type, RecordType.condition);
      expect(r.title, 'Type 2 diabetes');
      expect(r.status, 'active');
      expect(r.date, DateTime.utc(2026, 7, 1));
      expect(r.resourceType, 'Condition');
      // Category (from the row, for every source) first; Retrieved last.
      expect(r.details.map((d) => d.label), ['Category', 'Retrieved']);
      expect(r.details.last.value,
          EhrResourceMapper.shortDate(DateTime.utc(2026, 10, 14, 12)));
    });

    test('a row with an unknown source is dropped', () {
      expect(
          EhrResourceMapper.toHealthRecord(
              {'resourceId': 'x', 'source': 'OTHER', 'title': 'Asthma'}),
          isNull);
    });

    test("a caller's extra details come before Category and Retrieved", () {
      final r = EhrResourceMapper.toHealthRecord(
          {'source': 'EPIC', 'category': 'Results', 'lastSyncedAt': '2026-10-14T12:00:00Z'},
          details: const [RecordDetail('Value', '7.1 %')])!;
      expect(r.details.map((d) => d.label), ['Value', 'Category', 'Retrieved']);
    });

    test('missing fields: a placeholder title, no date, no Retrieved', () {
      final r = EhrResourceMapper.toHealthRecord(
          {'source': 'EPIC', 'title': '   ', 'occurredAt': '', 'status': ''})!;
      expect(r.id, '');
      expect(r.title, 'Health record');
      expect(r.date, isNull);
      expect(r.status, isNull);
      expect(r.resourceType, isNull);
      expect(r.details, isEmpty);
    });

    test('an unparseable lastSyncedAt adds no Retrieved detail', () {
      final r = EhrResourceMapper.toHealthRecord(
          {'source': 'EPIC', 'resourceId': 'e', 'lastSyncedAt': 'yesterday'})!;
      expect(r.details, isEmpty);
    });
  });

  test('shortDate names every month and uses the local date', () {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    for (var m = 1; m <= 12; m++) {
      expect(EhrResourceMapper.shortDate(DateTime(2026, m, 9)),
          '${months[m - 1]} 9, 2026');
    }
    final utc = DateTime.utc(2026, 10, 14, 12);
    final local = utc.toLocal();
    expect(EhrResourceMapper.shortDate(utc),
        '${months[local.month - 1]} ${local.day}, ${local.year}');
  });

  test('stringOrNull and parseDate', () {
    expect(EhrResourceMapper.stringOrNull(null), isNull);
    expect(EhrResourceMapper.stringOrNull('  '), isNull);
    expect(EhrResourceMapper.stringOrNull(' a '), 'a');
    expect(EhrResourceMapper.stringOrNull(7), '7');
    expect(EhrResourceMapper.parseDate(null), isNull);
    expect(EhrResourceMapper.parseDate(20261014), isNull);
    expect(EhrResourceMapper.parseDate('not a date'), isNull);
    expect(EhrResourceMapper.parseDate('2026-10-14'), DateTime(2026, 10, 14));
  });
}
