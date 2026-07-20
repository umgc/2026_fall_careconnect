// Tests for telemetry_error_handler.dart.
//
// Coverage strategy mirrors telemetry_test.dart:
//   - TestWidgetsFlutterBinding.ensureInitialized()
//   - SharedPreferences mock for telemetry opt-out gate
//   - http.runWithClient + MockClient to capture telemetry POST bodies

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/telemetry/telemetry.dart';
import 'package:care_connect_app/features/telemetry/telemetry_error_handler.dart';
import 'package:care_connect_app/services/api_service.dart';

Future<List<String>> _captureTelemetryBodies(
  Future<void> Function() action,
) async {
  final bodies = <String>[];
  final mock = MockClient((req) async {
    if (req.method == 'POST' &&
        req.url.path.contains('telemetry') &&
        !req.url.path.contains('enabled')) {
      bodies.add(req.body);
    }
    return http.Response(jsonEncode({'enabled': true}), 200);
  });

  ApiService.debugSetHttpClient(mock);
  try {
    await http.runWithClient(() async {
      await Telemetry.setBackendEnabled(true);
      await action();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, () => mock);
  } finally {
    ApiService.debugResetHttpClient();
  }

  return bodies;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'telemetry_opted_out': false});
  });

  group('bucketEndpoint', () {
    test('maps telemetry paths', () {
      expect(bucketEndpoint('/v1/api/dev/telemetry'), 'telemetry');
      expect(bucketEndpoint('/v1/api/dev/telemetry/enabled'), 'telemetry');
    });

    test('maps coarse API buckets', () {
      expect(bucketEndpoint('/v1/api/evv/visits'), 'evv');
      expect(bucketEndpoint('/api/v3/calls/abc/join'), 'calls');
      expect(bucketEndpoint('/v1/api/patients/1'), 'patients');
      expect(bucketEndpoint('/v1/api/caregivers/2'), 'caregivers');
      expect(bucketEndpoint('/v1/api/auth/login'), 'auth');
      expect(bucketEndpoint('/v1/api/messages/1'), 'chat');
      expect(bucketEndpoint('/v3/api/tasks/1'), 'tasks');
      expect(bucketEndpoint('/v1/api/analytics/summary'), 'analytics');
      expect(bucketEndpoint('/v1/api/custom'), 'api');
    });
  });

  group('isNetworkError', () {
    test('returns false for TimeoutException', () {
      expect(isNetworkError(TimeoutException('timeout')), isFalse);
    });

    test('returns true for SocketException and ClientException', () {
      expect(isNetworkError(const SocketException('failed')), isTrue);
      expect(
        isNetworkError(http.ClientException('connection refused')),
        isTrue,
      );
    });

    test('returns true for message heuristics', () {
      expect(
        isNetworkError(Exception('SocketException: failed host lookup')),
        isTrue,
      );
    });
  });

  group('networkErrorType', () {
    test('returns coarse error type labels', () {
      expect(networkErrorType(const SocketException('x')), 'socket');
      expect(networkErrorType(http.ClientException('x')), 'client');
      expect(networkErrorType(Exception('other')), 'connection');
    });
  });

  group('recordHttpTimeout', () {
    test('emits error_timeout telemetry for non-telemetry endpoints', () async {
      final bodies = await _captureTelemetryBodies(() async {
        recordHttpTimeout(
          source: 'http',
          method: 'GET',
          endpoint: 'patients',
          timeoutMs: 15000,
        );
      });

      expect(bodies, isNotEmpty);
      final decoded = jsonDecode(bodies.single) as Map<String, dynamic>;
      expect(decoded['eventName'], 'error_timeout');
      expect(decoded['details']['endpoint'], 'patients');
      expect(decoded['details']['timeoutMs'], 15000);
    });

    test('skips telemetry when endpoint bucket is telemetry', () async {
      final bodies = await _captureTelemetryBodies(() async {
        recordHttpTimeout(
          source: 'http',
          method: 'POST',
          endpoint: 'telemetry',
        );
      });

      expect(bodies, isEmpty);
    });
  });

  group('recordHttpNetworkError', () {
    test('emits error_network telemetry for non-telemetry endpoints', () async {
      final bodies = await _captureTelemetryBodies(() async {
        recordHttpNetworkError(
          source: 'http',
          method: 'POST',
          endpoint: 'evv',
          statusCode: 0,
          errorType: 'client',
        );
      });

      expect(bodies, isNotEmpty);
      final decoded = jsonDecode(bodies.single) as Map<String, dynamic>;
      expect(decoded['eventName'], 'error_network');
      expect(decoded['details']['endpoint'], 'evv');
      expect(decoded['details']['errorType'], 'client');
    });
  });

  group('tryRecordUncaughtError', () {
    test('emits error_timeout for TimeoutException', () async {
      final bodies = await _captureTelemetryBodies(() async {
        tryRecordUncaughtError(TimeoutException('timeout'));
      });

      expect(bodies, isNotEmpty);
      final decoded = jsonDecode(bodies.single) as Map<String, dynamic>;
      expect(decoded['eventName'], 'error_timeout');
      expect(decoded['details']['source'], 'dart');
    });

    test('emits error_network for ClientException', () async {
      final bodies = await _captureTelemetryBodies(() async {
        tryRecordUncaughtError(http.ClientException('connection refused'));
      });

      expect(bodies, isNotEmpty);
      final decoded = jsonDecode(bodies.single) as Map<String, dynamic>;
      expect(decoded['eventName'], 'error_network');
      expect(decoded['details']['errorType'], 'client');
    });

    test('ignores non-network errors', () async {
      final bodies = await _captureTelemetryBodies(() async {
        tryRecordUncaughtError(Exception('validation failed'));
      });

      expect(bodies, isEmpty);
    });
  });
}
