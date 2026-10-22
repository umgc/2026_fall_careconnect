// CC-12 Increment 2: the public scan call and the data it returns.
// Test Plan §3.26: TC-EMG-223…229 (the pull request's), 234…236 (Testing Lead).

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:care_connect_app/config/env_constant.dart';
import 'package:care_connect_app/features/emergency_passport/models/public_passport.dart';
import 'package:care_connect_app/features/emergency_passport/services/passport_scan_service.dart';

import '../passport_test_support.dart';


PassportScanService _service(
        Future<http.Response> Function(http.Request) handler) =>
    PassportScanService(client: MockClient(handler));

void main() {
  test('TC-EMG-223: an active code returns every shared section, read without sign-in',
      () async {
    late http.Request sent;
    final result = await _service((req) async {
      sent = req;
      return http.Response(jsonEncode(fullPassport), 200);
    }).scan('abc123');

    expect(sent.method, 'GET');
    expect(sent.url.path, '/v1/api/passport/scan/abc123');
    expect(sent.headers.containsKey('Authorization'), isFalse);

    final p = (result as ScanShown).passport;
    expect(p.name, 'Jordan Miller');
    expect(p.age, 41);
    expect(p.bloodType, 'O_POSITIVE');
    expect(p.allergies!.map((a) => a.allergen), ['Penicillin', 'Peanuts', 'Latex']);
    expect(p.allergies!.first.severity, 'LIFE_THREATENING');
    expect(p.allergies!.last.severity, isNull);
    expect(p.medications!.single.dosage, '10 mg');
    expect(p.chronicConditions, 'Type 2 diabetes');
    expect(p.emergencyContact!.phone, '(415) 555-0184');
    expect(p.lastUpdated, DateTime.utc(2026, 10, 13, 15));
    expect(p.sharesNothing, isFalse);
  });

  test('TC-EMG-224: name and age only means nothing else was shared, and there is no date',
      () async {
    final result = await _service((_) async =>
            http.Response(jsonEncode({'name': 'Jordan Miller', 'age': 41}), 200))
        .scan('abc123');
    final p = (result as ScanShown).passport;
    expect(p.sharesNothing, isTrue);
    expect(p.allergies, isNull);
    expect(p.lastUpdated, isNull);
  });

  for (final c in [
    (404, '{"status":"NOT_ACTIVE"}', ScanNotActive),
    (429, '{"status":"RATE_LIMITED"}', ScanRateLimited),
    (500, '{"error":"x"}', ScanFailed),
    (200, 'not json', ScanFailed),
    (200, '[]', ScanFailed),
  ]) {
    test('TC-EMG-225: HTTP ${c.$1} with body ${c.$2} -> ${c.$3}', () async {
      final result = await _service((_) async => http.Response(c.$2, c.$1))
          .scan('abc123');
      expect(result.runtimeType, c.$3);
    });
  }

  test('TC-EMG-226: no answer from the server -> ScanFailed', () async {
    final result = await _service((_) async => throw http.ClientException('offline'))
        .scan('abc123');
    expect(result, isA<ScanFailed>());
  });

  test('TC-EMG-227: an empty code is not active and makes no call', () async {
    var calls = 0;
    final result = await _service((_) async {
      calls++;
      return http.Response('', 200);
    }).scan('  ');
    expect(result, isA<ScanNotActive>());
    expect(calls, 0);
  });

  test('TC-EMG-228: the code is sent as one path segment', () async {
    late Uri url;
    await _service((req) async {
      url = req.url;
      return http.Response('{"status":"NOT_ACTIVE"}', 404);
    }).scan('a/b?c');
    expect(url.pathSegments.last, 'a/b?c');
    expect(url.query, isEmpty);
  });

  test('TC-EMG-229: labels', () {
    expect(bloodTypeLabel('O_POSITIVE'), 'O+');
    expect(bloodTypeLabel('AB_NEGATIVE'), 'AB−');
    expect(bloodTypeSpoken('AB_NEGATIVE'), 'AB negative');
    expect(severityLabel('LIFE_THREATENING'), 'Life-threatening');
    expect(severityLabel('MILD'), 'Mild');
    expect(severityLabel(null), isNull);
  });

  testWidgets(
      'TC-EMG-234: a server that never answers gives ScanFailed after 15 '
      'seconds, not before, so the page leaves its loading state', (t) async {
    ScanResult? result;
    _service((_) => Completer<http.Response>().future)
        .scan('abc123')
        .then((r) => result = r);
    await t.pump(const Duration(seconds: 14));
    expect(result, isNull);
    await t.pump(const Duration(seconds: 2));
    expect(result, isA<ScanFailed>());
  });

  for (final status in [400, 401, 403, 502, 503]) {
    test(
        'TC-EMG-235: HTTP $status is "couldn\'t load" (ScanFailed), never '
        'shown as a code that is not active', () async {
      final result = await _service(
              (_) async => http.Response('{"error":"x"}', status))
          .scan('abc123');
      expect(result, isA<ScanFailed>());
    });
  }

  test(
      'TC-EMG-236: the scan goes to the configured backend with the code '
      'trimmed, asks for JSON, and carries no credentials (no Authorization, '
      'no Cookie)', () async {
    late http.Request sent;
    await _service((req) async {
      sent = req;
      return http.Response('{"status":"NOT_ACTIVE"}', 404);
    }).scan('  abc123 \n');
    expect(sent.url.toString(),
        '${getBackendBaseUrl()}/v1/api/passport/scan/abc123');
    expect(sent.headers['Accept'], 'application/json');
    expect(
        sent.headers.keys.map((k) => k.toLowerCase()),
        isNot(anyOf(contains('authorization'), contains('cookie'))));
  });
}
