// EhrDataService: the Epic / Cerner / Athena read surface (/api/ehr/resources,
// /api/ehr/patient) the Health Data screen merges with Medicare.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/health/health_data/models/health_record.dart';
import 'package:care_connect_app/features/health/health_data/services/ehr_data_service.dart';
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
}
