// HTTP isolation: calls run inside http.runWithClient with a MockClient, which
// intercepts the service's top-level http.get/http.post. AuthTokenManager's
// secure-storage read fails in the test host and falls back to default headers.
import 'dart:convert';

import 'package:care_connect_app/features/connection_requests/services/connection_request_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _summaryJson({int id = 100}) => {
      'id': id,
      'caregiverName': 'Carey Tester',
      'caregiverEmail': 'carey@example.com',
      'patientName': 'Index Tester',
      'patientEmail': 'index@example.com',
      'relationshipType': 'Caregiver',
      'message': 'Hello',
      'status': 'PENDING',
      'requestedAt': '2026-10-18T12:00:00Z',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('incoming', () {
    test('parses pending requests from /incoming', () async {
      // Arrange
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(jsonEncode([_summaryJson()]), 200);
      });

      // Act
      final result =
          await http.runWithClient(ConnectionRequestService.incoming, () => client);

      // Assert
      expect(seen.method, 'GET');
      expect(seen.url.path, endsWith('/v1/api/connection-requests/incoming'));
      expect(result, hasLength(1));
      expect(result.single.id, 100);
      expect(result.single.caregiverName, 'Carey Tester');
      expect(result.single.requestedAt, DateTime.utc(2026, 10, 18, 12));
    });

    test('throws on a non-200 response', () async {
      final client = MockClient((_) async => http.Response('', 403));

      expect(
        http.runWithClient(ConnectionRequestService.incoming, () => client),
        throwsA(isA<ConnectionRequestException>()),
      );
    });

    test('throws a friendly error when the server is unreachable', () async {
      final client = MockClient((_) async => throw Exception('offline'));

      await expectLater(
        http.runWithClient(ConnectionRequestService.incoming, () => client),
        throwsA(isA<ConnectionRequestException>().having(
            (e) => e.message, 'message', contains('Could not reach the server'))),
      );
    });
  });

  group('accept and decline', () {
    test('accept posts to /{id}/accept', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response('{"message":"ok"}', 200);
      });

      await http.runWithClient(() => ConnectionRequestService.accept(100), () => client);

      expect(seen.method, 'POST');
      expect(seen.url.path, endsWith('/v1/api/connection-requests/100/accept'));
    });

    test('decline posts to /{id}/reject', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response('{"message":"ok"}', 200);
      });

      await http.runWithClient(() => ConnectionRequestService.decline(100), () => client);

      expect(seen.url.path, endsWith('/v1/api/connection-requests/100/reject'));
    });

    test('maps 404 and 409 to specific errors', () async {
      for (final entry in {
        404: 'no longer exists',
        409: 'already been answered',
        500: 'error 500',
      }.entries) {
        final client = MockClient((_) async => http.Response('', entry.key));
        await expectLater(
          http.runWithClient(() => ConnectionRequestService.accept(1), () => client),
          throwsA(isA<ConnectionRequestException>()
              .having((e) => e.toString(), 'message', contains(entry.value))),
        );
      }
    });

    test('throws a friendly error when the server is unreachable', () async {
      final client = MockClient((_) async => throw Exception('offline'));

      await expectLater(
        http.runWithClient(() => ConnectionRequestService.decline(1), () => client),
        throwsA(isA<ConnectionRequestException>()),
      );
    });
  });
}
