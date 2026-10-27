// AthenaDataService against GET /api/athena/resources (paged, newest first)
// and GET /api/athena/resources/{type}/{id}.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/health/health_data/models/health_record.dart';
import 'package:care_connect_app/features/health/health_data/services/athena_data_service.dart';
import 'package:care_connect_app/services/api_client.dart';

Map<String, dynamic> athenaItem(String id,
        {String type = 'Condition',
        String category = 'Conditions',
        String title = 'Hypertension',
        String? occurredAt = '2026-03-02T00:00:00Z'}) =>
    {
      'resourceType': type,
      'resourceId': id,
      'category': category,
      'title': title,
      'status': 'active',
      'occurredAt': occurredAt,
      'lastSyncedAt': '2026-10-14T12:00:00Z',
      'source': 'ATHENAHEALTH',
    };

/// Answers /api/athena/resources by page number and records each request.
class AthenaAdapter implements HttpClientAdapter {
  AthenaAdapter({this.pages = const [], this.status, this.detail});

  final List<List<Map<String, dynamic>>> pages;
  final int? status;
  final Map<String, dynamic>? detail;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final headers = {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    };
    if (status != null) {
      return ResponseBody.fromString(
          jsonEncode({'code': 'NOT_CONNECTED'}), status!,
          headers: headers);
    }
    if (options.path.startsWith('/api/athena/resources/')) {
      return detail == null
          ? ResponseBody.fromString(jsonEncode({'code': 'NOT_FOUND'}), 404,
              headers: headers)
          : ResponseBody.fromString(jsonEncode(detail), 200, headers: headers);
    }
    final page = options.queryParameters['page'] as int;
    if (page >= pages.length) {
      throw DioException(
          requestOptions: options, type: DioExceptionType.connectionError);
    }
    return ResponseBody.fromString(
        jsonEncode({
          'items': pages[page],
          'page': page,
          'size': options.queryParameters['size'],
          'hasNext': page < pages.length - 1,
        }),
        200,
        headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpClientAdapter original;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    original = ApiClient.instance.debugHttpClientAdapter;
  });
  tearDown(() => ApiClient.instance.debugSetHttpClientAdapter(original));

  T use<T extends HttpClientAdapter>(T a) {
    ApiClient.instance.debugSetHttpClientAdapter(a);
    return a;
  }

  test('maps each athena item to an athena record with its resource type',
      () async {
    use(AthenaAdapter(pages: [
      [
        athenaItem('c-1'),
        athenaItem('m-1',
            type: 'MedicationRequest',
            category: 'Medications',
            title: 'Lisinopril 10 mg',
            occurredAt: null),
      ],
    ]));
    final result = await AthenaDataService().fetchRecords();
    expect(result.complete, isTrue);
    expect(result.problem, isNull);
    final c = result.records.first;
    expect(c.id, 'c-1');
    expect(c.sources, [RecordSource.athena]);
    expect(c.type, RecordType.condition);
    expect(c.title, 'Hypertension');
    expect(c.status, 'active');
    expect(c.date, DateTime.utc(2026, 3, 2));
    expect(c.resourceType, 'Condition');
    expect(c.details.map((d) => d.label),
        ['Category', 'Retrieved']);
    final m = result.records.last;
    expect(m.type, RecordType.medication);
    expect(m.date, isNull);
  });

  test('pages until hasNext is false, at the largest page size', () async {
    final a = use(AthenaAdapter(pages: [
      [athenaItem('1')],
      [athenaItem('2')],
      [athenaItem('3')],
    ]));
    final result = await AthenaDataService().fetchRecords(
        from: DateTime(2026, 1, 5), to: DateTime(2026, 2, 9));
    expect(result.records.map((r) => r.id), ['1', '2', '3']);
    expect(a.requests.map((r) => r.queryParameters['page']), [0, 1, 2]);
    expect(a.requests.first.queryParameters['size'], 100);
    expect(a.requests.first.queryParameters['from'], '2026-01-05');
    expect(a.requests.first.queryParameters['to'], '2026-02-09');
  });

  test('409 and 404 (athena turned off) are not connected, 403 is hidden, '
      'other failures are unreachable', () async {
    use(AthenaAdapter(status: 409));
    expect((await AthenaDataService().fetchRecords()).problem,
        AthenaReadProblem.notConnected);
    use(AthenaAdapter(status: 404));
    expect((await AthenaDataService().fetchRecords()).problem,
        AthenaReadProblem.notConnected);
    use(AthenaAdapter(status: 403));
    expect((await AthenaDataService().fetchRecords()).problem,
        AthenaReadProblem.hidden);
    use(AthenaAdapter(status: 500));
    final failed = await AthenaDataService().fetchRecords();
    expect(failed.problem, AthenaReadProblem.unreachable);
    expect(failed.complete, isFalse);
  });

  test('a failure part way keeps the pages already read', () async {
    // Page 1 reports hasNext, but page 2 is not answered.
    final a = AthenaAdapter(pages: [
      [athenaItem('1')],
      [athenaItem('2')],
    ]);
    use(_DropAfter(a, 1));
    final result = await AthenaDataService().fetchRecords();
    expect(result.records.map((r) => r.id), ['1']);
    expect(result.complete, isFalse);
    expect(result.problem, AthenaReadProblem.unreachable);
  });

  test('fetchResource reads one record with its FHIR resource', () async {
    final a = use(AthenaAdapter(detail: {
      ...athenaItem('c-1'),
      'resource': {'resourceType': 'Condition', 'id': 'c-1'},
    }));
    final data = await AthenaDataService().fetchResource('Condition', 'c-1');
    expect(a.requests.single.path, '/api/athena/resources/Condition/c-1');
    expect(data!['resource'], {'resourceType': 'Condition', 'id': 'c-1'});

    use(AthenaAdapter());
    expect(await AthenaDataService().fetchResource('Condition', 'gone'),
        isNull);
  });

  // R381-D02: a failed read is not a missing record.
  test('fetchResource: 409 and 403 are no record (null); a server error or no '
      'connection throws AthenaReadException', () async {
    for (final status in [409, 403]) {
      use(AthenaAdapter(status: status));
      expect(await AthenaDataService().fetchResource('Condition', 'c-1'),
          isNull, reason: '$status');
    }
    use(AthenaAdapter(status: 500));
    await expectLater(AthenaDataService().fetchResource('Condition', 'c-1'),
        throwsA(isA<AthenaReadException>()));
    use(_DropAfter(AthenaAdapter(), 0));
    await expectLater(AthenaDataService().fetchResource('Condition', 'c-1'),
        throwsA(isA<AthenaReadException>()));
  });

  // Review follow-up: the page cap that stops a server that always says
  // "there's another page".
  test('stops after maxPages pages and reports the read as incomplete',
      () async {
    final a = use(AthenaAdapter(pages: [
      for (var i = 0; i < AthenaDataService.maxPages + 5; i++)
        [athenaItem('p$i')],
    ]));
    final result = await AthenaDataService().fetchRecords();
    expect(a.requests, hasLength(AthenaDataService.maxPages));
    expect(a.requests.last.queryParameters['page'],
        AthenaDataService.maxPages - 1);
    expect(result.records, hasLength(AthenaDataService.maxPages));
    expect(result.complete, isFalse);
    expect(result.problem, AthenaReadProblem.unreachable);
  });
}

/// Answers the first [n] requests from [inner], then fails.
class _DropAfter implements HttpClientAdapter {
  _DropAfter(this.inner, this.n);
  final HttpClientAdapter inner;
  final int n;
  int _count = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    if (_count++ >= n) {
      throw DioException(
          requestOptions: options, type: DioExceptionType.connectionError);
    }
    return inner.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}
