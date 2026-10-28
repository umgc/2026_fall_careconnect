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
const List<MethodChannel> _urlLauncherChannels = [
  MethodChannel('plugins.flutter.io/url_launcher'),
  MethodChannel('plugins.flutter.io/url_launcher_android'),
  MethodChannel('plugins.flutter.io/url_launcher_ios'),
  MethodChannel('plugins.flutter.io/url_launcher_linux'),
  MethodChannel('plugins.flutter.io/url_launcher_macos'),
  MethodChannel('plugins.flutter.io/url_launcher_windows'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (_) async => null);
    for (final channel in _urlLauncherChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launchUrl') {
          return true;
        }
        return true;
      });
    }
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);

    for (final channel in _urlLauncherChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
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
  group('EpicService.authorizeUrl', () {
    test('returns authUrl from a successful response', () async {
      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/api/epic/authorize'));

        return http.Response(
          jsonEncode({'authUrl': 'https://example.com/epic-authorize'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final authUrl = await http.runWithClient(
        EpicService.authorizeUrl,
        () => client,
      );

      expect(authUrl, 'https://example.com/epic-authorize');
    });

    test('throws when authorize endpoint returns non-200', () async {
      final client = MockClient(
        (request) async => http.Response('unauthorized', 401),
      );

      expect(
        () => http.runWithClient(
          EpicService.authorizeUrl,
          () => client,
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Epic authorize failed (401)'),
          ),
        ),
      );
    });
  });

  group('EpicService.status', () {
    test('returns parsed connection status on success', () async {
      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/api/epic/status'));

        return http.Response(
          jsonEncode({
            'connected': true,
            'status': 'CONNECTED',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await http.runWithClient(
        EpicService.status,
        () => client,
      );

      expect(result['connected'], isTrue);
      expect(result['status'], 'CONNECTED');
    });

    test('throws when connection status is unavailable', () async {
      final client = MockClient(
        (request) async => http.Response('server error', 500),
      );

      expect(
        () => http.runWithClient(
          EpicService.status,
          () => client,
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Epic connection status unavailable (500)'),
          ),
        ),
      );
    });
  });

  group('EpicService.disconnect', () {
    test('returns true when disconnect succeeds', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, endsWith('/api/epic/disconnect'));

        return http.Response('', 200);
      });

      final result = await http.runWithClient(
        EpicService.disconnect,
        () => client,
      );

      expect(result, isTrue);
    });

    test('returns false when disconnect fails', () async {
      final client = MockClient(
        (request) async => http.Response('', 500),
      );

      final result = await http.runWithClient(
        EpicService.disconnect,
        () => client,
      );

      expect(result, isFalse);
    });
  });
  group('EpicService.connect', () {
    test('requests authorize URL and launches returned Epic URL', () async {
      Uri? seen;

      final client = MockClient((request) async {
        seen = request.url;

        return http.Response(
          jsonEncode({
            'authUrl': 'https://example.com/epic-authorize',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await http.runWithClient(
        EpicService.connect,
        () => client,
      );

      expect(seen, isNotNull);
      expect(seen!.path, endsWith('/api/epic/authorize'));
    });

    test('throws when authorize request returns non-200', () async {
      final client = MockClient(
        (request) async => http.Response('server error', 500),
      );

      expect(
        () => http.runWithClient(
          EpicService.connect,
          () => client,
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Epic authorize failed (500)'),
          ),
        ),
      );
    });
  });
}
