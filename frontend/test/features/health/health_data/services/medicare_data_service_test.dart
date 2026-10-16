// MedicareDataService against the PR's own mock endpoints, fed with the
// backend's fixture bundles (see health_data_test_support.dart).

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/health/health_data/models/health_record.dart';
import 'package:care_connect_app/features/health/health_data/services/medicare_data_service.dart';
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

  RouteAdapter use(RouteAdapter a) {
    ApiClient.instance.debugSetHttpClientAdapter(a);
    return a;
  }

  test('TC-HDATA-003: an EOB becomes a claim record with title, provider, '
      'facility, diagnosis, amounts, service date and Paid', () async {
    use(RouteAdapter({
      '/v1/api/medicare/visits': envelope(fixtureResources('eob-bundle.json')),
      '/v1/api/medicare/coverage': envelope(const []),
    }));
    final result = await MedicareDataService().fetchRecords();
    final inpatient =
        result.records.singleWhere((r) => r.id == 'inpatient--4411138162');
    expect(inpatient.sources, [RecordSource.medicare]);
    expect(inpatient.type, RecordType.claimService);
    expect(inpatient.title, 'Simple pneumonia and pleurisy with CC');
    expect(inpatient.date, DateTime(2026, 4, 18));
    expect(inpatient.status, 'Paid');
    expect(inpatient.details.map((d) => '${d.label}=${d.value}'), [
      'Provider=Saint Agnes Hospital',
      'Facility=Saint Agnes Hospital',
      'Diagnosis=Pneumonia, unspecified organism',
      r'Amount=$14320.55',
      r'Medicare paid=$9861.13',
      'Service date=Apr 18, 2026',
    ]);
  });

  test('TC-HDATA-004: entered-in-error claims and resources of other types '
      'are dropped; a claim with no status is kept', () async {
    final eobs = fixtureResources('eob-bundle.json');
    final noStatus = Map<String, dynamic>.of(eobs.first)
      ..remove('status')
      ..['id'] = 'no-status';
    use(RouteAdapter({
      '/v1/api/medicare/visits': envelope([
        ...eobs,
        noStatus,
        ...fixtureResources('patient-bundle.json'),
      ]),
      '/v1/api/medicare/coverage': envelope(const []),
    }));
    final ids =
        (await MedicareDataService().fetchRecords()).records.map((r) => r.id);
    expect(ids, ['carrier--22639159481', 'inpatient--4411138162', 'no-status']);
  });

  test('TC-HDATA-005: Coverage becomes a record titled by plan, with payer, '
      'effective date, and Active only when active', () async {
    use(RouteAdapter({
      '/v1/api/medicare/visits': envelope(const []),
      '/v1/api/medicare/coverage':
          envelope(fixtureResources('coverage-bundle.json')),
    }));
    final records = (await MedicareDataService().fetchRecords()).records;
    expect(records.map((r) => r.title), [
      'Medicare Part A (Hospital Insurance)',
      'Medicare Part B (Medical Insurance)',
      'Medicare Part D (Prescription Drug Coverage)',
    ]);
    final partA = records.first;
    expect(partA.type, RecordType.other);
    expect(partA.status, 'Active');
    expect(partA.details.map((d) => '${d.label}=${d.value}'),
        ['Payer=Medicare', 'Effective=Jun 1, 2005']);
    expect(records.last.status, isNull);
  });

  test('TC-HDATA-006: the result is synthetic when either envelope says so',
      () async {
    Future<bool> synthetic(bool visits, bool coverage) async {
      use(RouteAdapter({
        '/v1/api/medicare/visits': envelope(const [], synthetic: visits),
        '/v1/api/medicare/coverage': envelope(const [], synthetic: coverage),
      }));
      return (await MedicareDataService().fetchRecords()).synthetic;
    }

    expect(await synthetic(true, false), isTrue);
    expect(await synthetic(false, true), isTrue);
    expect(await synthetic(false, false), isFalse);
  });

  test('TC-HDATA-007: one endpoint failing still returns the other '
      'endpoint\'s records', () async {
    use(RouteAdapter({
      '/v1/api/medicare/coverage':
          envelope(fixtureResources('coverage-bundle.json')),
    }, status: {
      '/v1/api/medicare/visits': 503
    }));
    final result = await MedicareDataService().fetchRecords();
    expect(result.records, hasLength(3));
    expect(result.records.every((r) => r.type == RecordType.other), isTrue);
    expect(result.synthetic, isTrue);
  });

  test('TC-HDATA-008: reads exactly the visits and coverage endpoints, once '
      'each', () async {
    final a = use(RouteAdapter({
      '/v1/api/medicare/visits': envelope(const []),
      '/v1/api/medicare/coverage': envelope(const []),
    }));
    await MedicareDataService().fetchRecords();
    expect(a.paths, ['/v1/api/medicare/visits', '/v1/api/medicare/coverage']);
  });
}
