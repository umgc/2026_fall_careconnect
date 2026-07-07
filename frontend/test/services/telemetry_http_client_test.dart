// Tests for TelemetryHttpClient (lib/services/telemetry_http_client.dart).
//
// Uses a fake inner client that throws transport errors and captures telemetry
// POST bodies via http.runWithClient, matching telemetry_test.dart patterns.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/telemetry/telemetry.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/telemetry_http_client.dart';

class _ThrowingClient extends http.BaseClient {
  _ThrowingClient(this._error);

  final Object _error;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw _error;
  }

  @override
  void close() {}
}

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

  group('TelemetryHttpClient', () {
    test('emits error_timeout when inner client throws TimeoutException',
        () async {
      final bodies = await _captureTelemetryBodies(() async {
        final client = TelemetryHttpClient(
          _ThrowingClient(TimeoutException('timeout')),
        );

        try {
          await client.get(Uri.parse('https://example.org/v1/api/patients/1'));
        } catch (_) {}

        client.close();
      });

      expect(bodies, isNotEmpty);
      final decoded = jsonDecode(bodies.single) as Map<String, dynamic>;
      expect(decoded['eventName'], 'error_timeout');
      expect(decoded['details']['endpoint'], 'patients');
      expect(decoded['details']['method'], 'GET');
    });

    test('emits error_network when inner client throws ClientException',
        () async {
      final bodies = await _captureTelemetryBodies(() async {
        final client = TelemetryHttpClient(
          _ThrowingClient(http.ClientException('connection refused')),
        );

        try {
          await client.post(Uri.parse('https://example.org/v1/api/evv/start'));
        } catch (_) {}

        client.close();
      });

      expect(bodies, isNotEmpty);
      final decoded = jsonDecode(bodies.single) as Map<String, dynamic>;
      expect(decoded['eventName'], 'error_network');
      expect(decoded['details']['endpoint'], 'evv');
      expect(decoded['details']['errorType'], 'client');
    });

    test('emits error_network when inner client throws SocketException',
        () async {
      final bodies = await _captureTelemetryBodies(() async {
        final client = TelemetryHttpClient(
          _ThrowingClient(const SocketException('failed host lookup')),
        );

        try {
          await client.get(Uri.parse('https://example.org/v1/api/tasks/1'));
        } catch (_) {}

        client.close();
      });

      expect(bodies, isNotEmpty);
      final decoded = jsonDecode(bodies.single) as Map<String, dynamic>;
      expect(decoded['eventName'], 'error_network');
      expect(decoded['details']['endpoint'], 'tasks');
      expect(decoded['details']['errorType'], 'socket');
    });

    test('does not emit telemetry for telemetry endpoint failures', () async {
      final bodies = await _captureTelemetryBodies(() async {
        final client = TelemetryHttpClient(
          _ThrowingClient(TimeoutException('timeout')),
        );

        try {
          await client.post(
            Uri.parse('https://example.org/v1/api/dev/telemetry'),
          );
        } catch (_) {}

        client.close();
      });

      expect(bodies, isEmpty);
    });
  });
}
