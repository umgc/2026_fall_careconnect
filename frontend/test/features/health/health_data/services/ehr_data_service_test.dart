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

  test('TC-HDATA-022: a record from a source the app does not know is never '
      'shown as coming from Epic (DEF-MCR-22)', () async {
    ApiClient.instance.debugSetHttpClientAdapter(RouteAdapter({
      '/api/ehr/resources': '[{"resourceId":"x-1","source":"ALLSCRIPTS",'
          '"category":"Conditions","title":"Hypertension"},'
          '{"resourceId":"x-2","category":"Allergies","title":"Penicillin"}]',
    }));
    final records = await EhrDataService().fetchRecords();
    expect(records.where((r) => r.sources.contains(RecordSource.epic)), isEmpty,
        reason: records.map((r) => '${r.id}: ${r.sources}').join('; '));
  });

  test('TC-HDATA-028: resources map to records by id, source, category, '
      'title, date and status, and the patient record to demographics',
      () async {
    ApiClient.instance.debugSetHttpClientAdapter(RouteAdapter({
      '/api/ehr/resources': '['
          '{"resourceId":"c-1","source":"cerner","category":"Medications",'
          '"title":"Metformin 500 mg","occurredAt":"2026-08-01T12:00:00Z",'
          '"status":"active"},'
          '{"resourceId":"a-1","source":"ATHENA","category":"Something else",'
          '"title":"  ","occurredAt":""}'
          ']',
      '/api/ehr/patient':
          '{"name":"Test Patient","birthDate":"1980-05-14","gender":" "}',
    }));
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
  });
}
