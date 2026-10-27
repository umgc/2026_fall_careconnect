import 'dart:convert';

import 'package:care_connect_app/services/epic_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Unit tests for [EpicService.getResource], the citation-detail fetch that I3c
/// extended to forward a caregiver's `patientUserId`. The service calls the
/// top-level `http.get`, so the mock is injected with `http.runWithClient`;
/// `AuthTokenManager` reads flutter_secure_storage, stubbed to return no token.
const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  group('EpicService.getResource', () {
    test('sends patientUserId query param when given (I3c) and parses the body',
        () async {
      Uri? seen;
      final client = MockClient((request) async {
        seen = request.url;
        return http.Response(
          jsonEncode({'resourceType': 'Observation', 'resourceId': 'obs-1'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final data = await http.runWithClient(
        () => EpicService.getResource('Observation', 'obs-1',
            patientUserId: 'user-7'),
        () => client,
      );

      expect(seen, isNotNull);
      expect(seen!.path, endsWith('/api/epic/resource/Observation/obs-1'));
      expect(seen!.queryParameters['patientUserId'], 'user-7');
      expect(data, isNotNull);
      expect(data!['resourceId'], 'obs-1');
    });

    test('omits patientUserId when absent or empty (caller-scoped)', () async {
      Uri? seen;
      final client = MockClient((request) async {
        seen = request.url;
        return http.Response('{}', 200,
            headers: {'content-type': 'application/json'});
      });

      await http.runWithClient(
        () => EpicService.getResource('Condition', 'cond-9'),
        () => client,
      );
      expect(seen!.queryParameters.containsKey('patientUserId'), isFalse);

      await http.runWithClient(
        () => EpicService.getResource('Condition', 'cond-9', patientUserId: ''),
        () => client,
      );
      expect(seen!.queryParameters.containsKey('patientUserId'), isFalse);
    });

    test('url-encodes the type and id path segments', () async {
      Uri? seen;
      final client = MockClient((request) async {
        seen = request.url;
        return http.Response('{}', 200,
            headers: {'content-type': 'application/json'});
      });

      await http.runWithClient(
        () => EpicService.getResource('Med/Req', 'a b'),
        () => client,
      );

      // pathSegments decodes each segment, proving the reserved chars were
      // percent-encoded on the wire rather than splitting the path.
      expect(seen!.pathSegments, containsAll(<String>['Med/Req', 'a b']));
    });

    test('returns null on a non-200 response', () async {
      final client = MockClient((request) async => http.Response('nope', 404));

      final data = await http.runWithClient(
        () => EpicService.getResource('Observation', 'missing'),
        () => client,
      );

      expect(data, isNull);
    });
  });
}
