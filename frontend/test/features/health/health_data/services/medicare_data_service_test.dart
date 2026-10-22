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

  test(
      'TC-MCR-CG-020: with a patientId both reads ask for that patient; '
      'without one they read the caller\'s own', () async {
    final a = use(RouteAdapter({
      '/v1/api/medicare/visits': envelope(const []),
      '/v1/api/medicare/coverage': envelope(const []),
    }));
    await MedicareDataService().fetchRecords(patientId: 7);
    await MedicareDataService().fetchRecords();
    expect(a.uris.map((u) => u.queryParameters), [
      {'patientId': '7'},
      {'patientId': '7'},
      <String, String>{},
      <String, String>{},
    ]);
  });

  test(
      'TC-MCR-CG-021: a 403 is reported as forbidden, and a 404 or 409 '
      'alongside it still wins', () async {
    Future<MedicareReadProblem?> problem(int visits, int coverage) async {
      use(RouteAdapter({}, status: {
        '/v1/api/medicare/visits': visits,
        '/v1/api/medicare/coverage': coverage,
      }));
      final result = await MedicareDataService().fetchRecords(patientId: 7);
      expect(result.complete, isFalse);
      expect(result.records, isEmpty);
      return result.problem;
    }

    expect(await problem(403, 403), MedicareReadProblem.forbidden);
    expect(await problem(403, 404), MedicareReadProblem.notLinked);
    expect(await problem(409, 403), MedicareReadProblem.linkExpired);
    expect(await problem(503, 503), MedicareReadProblem.unreachable);
  });

  // ───── Testing Lead (PR #364 review): TC-MCR-CG-030, 031 ─────

  test(
      'TC-MCR-CG-030: a 403 beside an unreachable read is still forbidden, '
      'whichever read it was', () async {
    for (final codes in [
      [403, 503],
      [503, 403],
    ]) {
      use(RouteAdapter({}, status: {
        '/v1/api/medicare/visits': codes[0],
        '/v1/api/medicare/coverage': codes[1],
      }));
      final result = await MedicareDataService().fetchRecords(patientId: 7);
      expect(result.problem, MedicareReadProblem.forbidden, reason: '$codes');
      expect(result.records, isEmpty);
    }
  });

  test(
      'TC-MCR-CG-031: a caregiver read that half fails keeps the half that '
      'answered, marked incomplete and unreachable', () async {
    use(RouteAdapter({
      '/v1/api/medicare/coverage':
          envelope(fixtureResources('coverage-bundle.json')),
    }, status: {
      '/v1/api/medicare/visits': 503,
    }));
    final result = await MedicareDataService().fetchRecords(patientId: 7);
    expect(result.complete, isFalse);
    expect(result.problem, MedicareReadProblem.unreachable);
    expect(result.records, hasLength(3));
    expect(result.records.map((r) => r.type).toSet(), {RecordType.other});
  });
}
