import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:care_connect_app/services/oracle_health_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OracleHealthConnectionStatus', () {
    test('parses an active connection', () {
      final result = OracleHealthConnectionStatus.fromJson({
        'source': 'ORACLE_HEALTH',
        'connected': true,
        'status': 'ACTIVE',
      });

      expect(result.connected, isTrue);
      expect(result.status, 'ACTIVE');
      expect(result.source, 'ORACLE_HEALTH');
    });

    test('parses a disconnected account without status', () {
      final result = OracleHealthConnectionStatus.fromJson({
        'source': 'ORACLE_HEALTH',
        'connected': false,
      });

      expect(result.connected, isFalse);
      expect(result.status, isNull);
    });

    test('rejects missing connected field', () {
      expect(
        () => OracleHealthConnectionStatus.fromJson({
          'source': 'ORACLE_HEALTH',
        }),
        throwsFormatException,
      );
    });

    test('rejects invalid connected field', () {
      expect(
        () => OracleHealthConnectionStatus.fromJson({
          'connected': 'true',
        }),
        throwsFormatException,
      );
    });
  });

  group('OracleHealthService HTTP contract', () {
    test('rejects an empty launch token before making a request', () {
      expect(
        () => OracleHealthService.authorizeUrl(launch: '   '),
        throwsArgumentError,
      );
    });

    test('requests authorization URL with web return mode', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/oracle-health/authorize');
        expect(request.url.queryParameters['returnMode'], 'web');

        return http.Response(
          jsonEncode({
            'authUrl': 'https://example.org/authorize',
          }),
          200,
        );
      });

      await http.runWithClient(() async {
        final url = await OracleHealthService.authorizeUrl(
          webReturn: true,
        );

        expect(url, 'https://example.org/authorize');
      }, () => client);
    });

    test('rejects missing authorization URL', () async {
      final client = MockClient((request) async {
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        expect(
          OracleHealthService.authorizeUrl(webReturn: false),
          throwsFormatException,
        );
      }, () => client);
    });

    test('rejects insecure authorization URL', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'authUrl': 'http://example.org/authorize',
          }),
          200,
        );
      });

      await http.runWithClient(() async {
        expect(
          OracleHealthService.authorizeUrl(webReturn: false),
          throwsFormatException,
        );
      }, () => client);
    });

    test('reports authorization HTTP failure', () async {
      final client = MockClient((request) async {
        return http.Response('Forbidden', 403);
      });

      await http.runWithClient(() async {
        expect(
          OracleHealthService.authorizeUrl(webReturn: false),
          throwsException,
        );
      }, () => client);
    });

    test('mobile authorization omits web return mode', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/oracle-health/authorize');
        expect(request.url.queryParameters.containsKey('returnMode'), isFalse);

        return http.Response(
          jsonEncode({'authUrl': 'https://example.org/authorize'}),
          200,
        );
      });

      await http.runWithClient(() async {
        final url = await OracleHealthService.authorizeUrl(
          webReturn: false,
        );
        expect(url, 'https://example.org/authorize');
      }, () => client);
    });

    test('reads connected status from backend', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/oracle-health/status');

        return http.Response(
          jsonEncode({
            'source': 'ORACLE_HEALTH',
            'connected': true,
            'status': 'ACTIVE',
          }),
          200,
        );
      });

      await http.runWithClient(() async {
        final result = await OracleHealthService.status();

        expect(result.connected, isTrue);
        expect(result.status, 'ACTIVE');
        expect(result.source, 'ORACLE_HEALTH');
      }, () => client);
    });

    test('reads disconnected status from backend', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'source': 'ORACLE_HEALTH',
            'connected': false,
          }),
          200,
        );
      });

      await http.runWithClient(() async {
        final result = await OracleHealthService.status();

        expect(result.connected, isFalse);
        expect(result.status, isNull);
      }, () => client);
    });

    test('does not treat status HTTP failure as disconnected', () async {
      final client = MockClient((request) async {
        return http.Response('Service unavailable', 503);
      });

      await http.runWithClient(() async {
        await expectLater(
          OracleHealthService.status(),
          throwsException,
        );
      }, () => client);
    });

    test('disconnect sends POST to backend', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/oracle-health/disconnect');

        return http.Response(
          jsonEncode({
            'source': 'ORACLE_HEALTH',
            'connected': false,
          }),
          200,
        );
      });

      await http.runWithClient(() async {
        await OracleHealthService.disconnect();
      }, () => client);
    });

    test('disconnect reports backend failure', () async {
      final client = MockClient((request) async {
        return http.Response('Unauthorized', 401);
      });

      await http.runWithClient(() async {
        await expectLater(
          OracleHealthService.disconnect(),
          throwsException,
        );
      }, () => client);
    });
  });
}
