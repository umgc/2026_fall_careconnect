// EhrDataService: the Epic / Cerner / Athena read surface (/api/ehr/resources,
// /api/ehr/patient) the Health Data screen merges with Medicare.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/health/health_data/models/health_record.dart';
import 'package:care_connect_app/features/health/health_data/models/patient_demographics.dart';
import 'package:care_connect_app/features/health/health_data/services/ehr_data_service.dart';
import 'package:care_connect_app/features/health/health_data/services/ehr_resource_mapper.dart';
import 'package:care_connect_app/services/api_client.dart';

import '../health_data_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpClientAdapter original;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    original = ApiClient.instance.debugHttpClientAdapter;
  });

  tearDown(() => ApiClient.instance.debugSetHttpClientAdapter(original));

  test('unified EHR resources request all available sources', () async {
    final adapter = RouteAdapter({
      '/api/ehr/resources': '[]',
    });
    ApiClient.instance.debugSetHttpClientAdapter(adapter);

    await EhrDataService().fetchRecords();

    final request = adapter.uris.singleWhere(
      (uri) => uri.path.endsWith('/api/ehr/resources'),
    );
    expect(request.queryParameters['source'], 'ALL');
  });

  test(
      'TC-HDATA-022: a record from a source the app does not know is never '
      'shown as coming from Epic (DEF-MCR-22)', () async {
    ApiClient.instance.debugSetHttpClientAdapter(
      RouteAdapter({
        '/api/ehr/resources': '[{"resourceId":"x-1","source":"ALLSCRIPTS",'
            '"category":"Conditions","title":"Hypertension"},'
            '{"resourceId":"x-2","category":"Allergies",'
            '"title":"Penicillin"}]',
      }),
    );

    final records = await EhrDataService().fetchRecords();

    expect(
      records.where((record) => record.sources.contains(RecordSource.epic)),
      isEmpty,
      reason:
          records.map((record) => '${record.id}: ${record.sources}').join('; '),
    );
  });

  test(
    'TC-HDATA-028: resources map to records by id, source, category, '
    'title, date and status, and the patient record to demographics',
    () async {
      ApiClient.instance.debugSetHttpClientAdapter(
        RouteAdapter({
          '/api/ehr/resources': '['
              '{"resourceId":"c-1","source":"cerner",'
              '"category":"Medications","title":"Metformin 500 mg",'
              '"occurredAt":"2026-08-01T12:00:00Z","status":"active"},'
              '{"resourceId":"a-1","source":"ATHENA",'
              '"category":"Something else","title":"  ","occurredAt":""}'
              ']',
          '/api/ehr/patient':
              '{"name":"Test Patient","birthDate":"1980-05-14","gender":" "}',
        }),
      );

      final service = EhrDataService();
      final records = await service.fetchRecords();

      expect(records, hasLength(2));

      final med = records.first;
      expect(med.id, 'c-1');
      expect(med.sources, [RecordSource.cerner]);
      expect(med.type, RecordType.medication);
      expect(med.title, 'Metformin 500 mg');
      expect(med.date, DateTime.utc(2026, 8, 1, 12));
      expect(med.status, 'active');

      final other = records.last;
      expect(other.sources, [RecordSource.athena]);
      expect(other.type, RecordType.other);
      expect(other.title, 'Health record');
      expect(other.date, isNull);
      expect(other.status, isNull);

      final who = await service.fetchPatientDemographics();
      expect(who!.name, 'Test Patient');
      expect(who.birthDate, DateTime(1980, 5, 14));
      expect(who.gender, isNull);
    },
  );

  test(
      'TC-HDATA-042: Cerner allergies, conditions, and encounters map into '
      'the unified health record model', () async {
    final adapter = RouteAdapter({
      '/api/ehr/resources': '[{"resourceId":"epic-med-1","source":"EPIC",'
          '"category":"Medications","title":"Lisinopril",'
          '"status":"active"}]',
      '/v1/api/cerner/patients/7/allergies':
          '{"source":"ORACLE_HEALTH","allergies":['
              '{"source":"ORACLE_HEALTH",'
              '"sourceRecordId":"allergy-1",'
              '"substanceText":"Penicillin",'
              '"clinicalStatus":"active",'
              '"verificationStatus":"confirmed",'
              '"severity":"severe",'
              '"recordedDate":"2026-09-10",'
              '"reactions":["Hives"]}'
              ']}',
      '/v1/api/cerner/patients/7/conditions':
          '{"source":"ORACLE_HEALTH","conditions":['
              '{"source":"ORACLE_HEALTH",'
              '"sourceRecordId":"condition-1",'
              '"conditionText":"Hypertension",'
              '"clinicalStatus":"active",'
              '"recordedDate":"2026-08-12",'
              '"hiddenFromActiveList":false},'
              '{"source":"ORACLE_HEALTH",'
              '"sourceRecordId":"condition-hidden",'
              '"conditionText":"Entered in error",'
              '"hiddenFromActiveList":true}'
              ']}',
      '/v1/api/cerner/patients/7/encounters':
          '{"source":"ORACLE_HEALTH","encounters":['
              '{"source":"ORACLE_HEALTH",'
              '"sourceRecordId":"encounter-1",'
              '"status":"finished",'
              '"classDisplay":"Ambulatory",'
              '"encounterTypes":[{"display":"Office visit"}],'
              '"periodStart":"2026-07-14T14:30:00Z"}'
              ']}',
    });

    ApiClient.instance.debugSetHttpClientAdapter(adapter);

    final records = await EhrDataService().fetchRecords(patientId: 7);

    expect(
      adapter.paths,
      containsAll([
        '/api/ehr/resources',
        '/v1/api/cerner/patients/7/allergies',
        '/v1/api/cerner/patients/7/conditions',
        '/v1/api/cerner/patients/7/encounters',
      ]),
    );

    expect(records, hasLength(4));
    expect(
      records.map((record) => record.id),
      isNot(contains('condition-hidden')),
    );

    final allergy = records.firstWhere((record) => record.id == 'allergy-1');
    expect(allergy.sources, [RecordSource.cerner]);
    expect(allergy.type, RecordType.allergy);
    expect(allergy.title, 'Penicillin');
    expect(allergy.status, 'active');
    expect(allergy.date, DateTime(2026, 9, 10));

    final condition = records.firstWhere(
      (record) => record.id == 'condition-1',
    );
    expect(condition.sources, [RecordSource.cerner]);
    expect(condition.type, RecordType.condition);
    expect(condition.title, 'Hypertension');

    final encounter = records.firstWhere(
      (record) => record.id == 'encounter-1',
    );
    expect(encounter.sources, [RecordSource.cerner]);
    expect(encounter.type, RecordType.appointment);
    expect(encounter.title, 'Office visit');
    expect(encounter.status, 'finished');
    expect(encounter.date, DateTime.utc(2026, 7, 14, 14, 30));
  });

  test(
      'TC-HDATA-043: a failed Cerner endpoint does not hide records from '
      'another EHR source', () async {
    ApiClient.instance.debugSetHttpClientAdapter(
      RouteAdapter(
        {
          '/api/ehr/resources':
              '[{"resourceId":"epic-condition-1","source":"EPIC",'
                  '"category":"Conditions","title":"Asthma"}]',
          '/v1/api/cerner/patients/7/conditions':
              '{"source":"ORACLE_HEALTH","conditions":[]}',
          '/v1/api/cerner/patients/7/encounters':
              '{"source":"ORACLE_HEALTH","encounters":[]}',
        },
        status: {'/v1/api/cerner/patients/7/allergies': 502},
      ),
    );

    final records = await EhrDataService().fetchRecords(patientId: 7);

    expect(records, hasLength(1));
    expect(records.single.id, 'epic-condition-1');
    expect(records.single.sources, [RecordSource.epic]);
  });

  test(
      'rows stored by athenahealth (ATHENAHEALTH) are shown as athena '
      'records, with their resource type', () async {
    ApiClient.instance.debugSetHttpClientAdapter(RouteAdapter({
      '/api/ehr/resources': '[{"resourceType":"Condition","resourceId":"a-2",'
          '"source":"ATHENAHEALTH","category":"Conditions","title":"Asthma"}]',
    }));
    final records = await EhrDataService().fetchRecords();
    expect(records.single.sources, [RecordSource.athena]);
    expect(records.single.resourceType, 'Condition');
  });

  // R381-D05: Epic and athenahealth rows carry the same detail rows.
  test('an Epic row has the same Category detail as an athenahealth row',
      () async {
    final epic = EhrResourceMapper.toHealthRecord(
        {'source': 'EPIC', 'resourceId': 'e', 'category': 'Conditions'})!;
    final athena = EhrResourceMapper.toHealthRecord({
      'source': 'ATHENAHEALTH',
      'resourceId': 'a',
      'category': 'Conditions'
    })!;
    expect(epic.details.map((d) => '${d.label}: ${d.value}'),
        ['Category: Conditions']);
    expect(athena.details.map((d) => '${d.label}: ${d.value}'),
        epic.details.map((d) => '${d.label}: ${d.value}'));
  });

  test(
      'record types come from the FHIR resource type first, then the '
      'category', () async {
    String row(String type, String category) =>
        '{"resourceType":"$type","resourceId":"$type","source":"EPIC",'
        '"category":"$category","title":"$type"}';
    ApiClient.instance.debugSetHttpClientAdapter(RouteAdapter({
      '/api/ehr/resources': '[${[
        row('Condition', 'Conditions'),
        row('MedicationStatement', 'Medications'),
        row('AllergyIntolerance', 'Allergies'),
        row('Encounter', 'Care Context'),
        row('Observation', 'Results'),
        row('DiagnosticReport', 'Results'),
        row('Immunization', 'Immunizations'),
        row('Procedure', 'Procedures'),
        row('DocumentReference', 'Documents'),
        row('CarePlan', 'Care Context'),
        row('Coverage', 'Coverage/Insurance'),
        row('SomethingNew', 'Results'),
      ].join(',')}]',
    }));
    final types = {
      for (final r in await EhrDataService().fetchRecords()) r.id: r.type
    };
    expect(types, {
      'Condition': RecordType.condition,
      'MedicationStatement': RecordType.medication,
      'AllergyIntolerance': RecordType.allergy,
      'Encounter': RecordType.appointment,
      'Observation': RecordType.clinicalRecord,
      'DiagnosticReport': RecordType.clinicalRecord,
      'Immunization': RecordType.clinicalRecord,
      'Procedure': RecordType.clinicalRecord,
      'DocumentReference': RecordType.clinicalRecord,
      'CarePlan': RecordType.other,
      'Coverage': RecordType.other,
      'SomethingNew': RecordType.clinicalRecord,
    });
  });

  group('Patient Information', () {
    Future<PatientDemographics?> demographics(
        Map<String, String?> bySource) async {
      ApiClient.instance.debugSetHttpClientAdapter(_BySource(bySource));
      return EhrDataService().fetchPatientDemographics();
    }

    test('Epic wins every field it has; athenahealth fills the rest', () async {
      final d = await demographics({
        'EPIC': '{"name":"Epic Name","birthDate":"1980-05-14","gender":" "}',
        'ATHENAHEALTH':
            '{"name":"Athena Name","birthDate":"1981-01-01","gender":"female"}',
      });
      expect(d!.name, 'Epic Name');
      expect(d.birthDate, DateTime(1980, 5, 14));
      expect(d.gender, 'female');
    });

    test('athenahealth alone fills the whole card', () async {
      final d = await demographics({
        'EPIC': null,
        'ATHENAHEALTH':
            '{"name":"Athena Name","birthDate":"1981-01-01","gender":"male"}',
      });
      expect(d!.name, 'Athena Name');
      expect(d.birthDate, DateTime(1981, 1, 1));
      expect(d.gender, 'male');
    });

    // Review follow-up: each source's demographics come back by name, so a
    // caller looks a source up by name and a missing one is just null (it
    // used to be a list read by index, where a missing name was index -1).
    test('fetchDemographicsBySource returns each source by name', () async {
      ApiClient.instance.debugSetHttpClientAdapter(_BySource({
        'EPIC': '{"name":"Epic Name","birthDate":"1980-05-14"}',
        'ATHENAHEALTH': null,
      }));
      final bySource = await EhrDataService().fetchDemographicsBySource();
      expect(bySource.keys, EhrDataService.demographicsSources);
      expect(bySource['EPIC']!.birthDate, DateTime(1980, 5, 14));
      expect(bySource['ATHENAHEALTH'], isNull);
      expect(bySource['CERNER'], isNull);
    });

    test('merging follows the preferred order and tolerates a missing source',
        () {
      const epic = PatientDemographics(name: 'Epic Name');
      const athena = PatientDemographics(
          name: 'Athena Name', gender: 'female', birthDate: null);
      // Insertion order doesn't matter: Epic is still preferred.
      final merged = EhrDataService.mergeDemographics(
          {'ATHENAHEALTH': athena, 'EPIC': epic})!;
      expect(merged.name, 'Epic Name');
      expect(merged.gender, 'female');
      // A source left out entirely doesn't throw.
      expect(EhrDataService.mergeDemographics({'ATHENAHEALTH': athena})!.name,
          'Athena Name');
      expect(EhrDataService.mergeDemographics(const {}), isNull);
    });

    test('no source with demographics means no card', () async {
      expect(await demographics({'EPIC': null, 'ATHENAHEALTH': null}), isNull);
    });
  });
}

/// Answers /api/ehr/patient by its ?source=; a null body is a 404.
class _BySource implements HttpClientAdapter {
  _BySource(this.bodies);
  final Map<String, String?> bodies;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = bodies[options.queryParameters['source']];
    return ResponseBody.fromString(body ?? '{}', body == null ? 404 : 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}
