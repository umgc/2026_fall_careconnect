// Tests for ConsentApiService.
//
// Coverage strategy:
//   ConsentApiService has three public static methods that each issue a
//   single HTTP request via top-level http.post/get/delete. No auth headers
//   or storage plugins are required (AuthTokenManager swallows the missing
//   secure-storage plugin and returns a plain Content-Type header in tests),
//   so http.runWithClient + MockClient is sufficient, matching the pattern
//   used in checkin_service_test.dart.
//
//   Branches tested:
//     grantAiRetrieval — 200 success (decodes response), optional fields
//       omitted/included in the request body, non-2xx throws.
//     revokeAiRetrieval — 200 success, query parameter present, non-2xx throws.
//     isAiRetrievalGranted — true/false from `granted`, non-2xx throws.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:care_connect_app/services/consent_api_service.dart';

void main() {
  group('ConsentApiService.grantAiRetrieval()', () {
    test('returns decoded map on 200 and sends granteeUserId', () async {
      late http.Request captured;
      final result = await http.runWithClient(
        () => ConsentApiService.grantAiRetrieval(granteeUserId: 42),
        () => MockClient((req) async {
          captured = req;
          return http.Response(
            jsonEncode({
              'granteeUserId': 42,
              'patientUserId': 7,
              'status': 'ACTIVE',
            }),
            200,
          );
        }),
      );

      expect(captured.method, 'POST');
      expect(captured.url.path, contains('/api/v3/consent/ai-retrieval'));
      final sentBody = jsonDecode(captured.body) as Map;
      expect(sentBody['granteeUserId'], 42);
      expect(sentBody.containsKey('granteeRole'), isFalse);
      expect(sentBody.containsKey('expiresAt'), isFalse);

      expect(result['status'], 'ACTIVE');
      expect(result['granteeUserId'], 42);
    });

    test('includes granteeRole and expiresAt when provided', () async {
      late http.Request captured;
      await http.runWithClient(
        () => ConsentApiService.grantAiRetrieval(
          granteeUserId: 42,
          granteeRole: 'CAREGIVER',
          expiresAt: '2026-12-31T00:00:00Z',
        ),
        () => MockClient((req) async {
          captured = req;
          return http.Response(jsonEncode({'status': 'ACTIVE'}), 200);
        }),
      );

      final sentBody = jsonDecode(captured.body) as Map;
      expect(sentBody['granteeRole'], 'CAREGIVER');
      expect(sentBody['expiresAt'], '2026-12-31T00:00:00Z');
    });

    test('throws on non-2xx status', () async {
      await expectLater(
        http.runWithClient(
          () => ConsentApiService.grantAiRetrieval(granteeUserId: 42),
          () => MockClient((req) async => http.Response('{}', 403)),
        ),
        throwsException,
      );
    });

    test('throws FormatException when response body is not an object',
        () async {
      await expectLater(
        http.runWithClient(
          () => ConsentApiService.grantAiRetrieval(granteeUserId: 42),
          () => MockClient((req) async => http.Response('[1,2,3]', 200)),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ConsentApiService.revokeAiRetrieval()', () {
    test('returns decoded map on 200 with granteeUserId query param',
        () async {
      late http.Request captured;
      final result = await http.runWithClient(
        () => ConsentApiService.revokeAiRetrieval(granteeUserId: 99),
        () => MockClient((req) async {
          captured = req;
          return http.Response(jsonEncode({'status': 'REVOKED'}), 200);
        }),
      );

      expect(captured.method, 'DELETE');
      expect(captured.url.queryParameters['granteeUserId'], '99');
      expect(result['status'], 'REVOKED');
    });

    test('throws on non-2xx status', () async {
      await expectLater(
        http.runWithClient(
          () => ConsentApiService.revokeAiRetrieval(granteeUserId: 99),
          () => MockClient((req) async => http.Response('{}', 500)),
        ),
        throwsException,
      );
    });
  });

  group('ConsentApiService.isAiRetrievalGranted()', () {
    test('returns true when granted is true', () async {
      late http.Request captured;
      final result = await http.runWithClient(
        () => ConsentApiService.isAiRetrievalGranted(
          patientUserId: 7,
          granteeUserId: 42,
        ),
        () => MockClient((req) async {
          captured = req;
          return http.Response(jsonEncode({'granted': true}), 200);
        }),
      );

      expect(captured.method, 'GET');
      expect(captured.url.queryParameters['patientUserId'], '7');
      expect(captured.url.queryParameters['granteeUserId'], '42');
      expect(result, isTrue);
    });

    test('returns false when granted is false', () async {
      final result = await http.runWithClient(
        () => ConsentApiService.isAiRetrievalGranted(
          patientUserId: 7,
          granteeUserId: 42,
        ),
        () => MockClient((req) async {
          return http.Response(jsonEncode({'granted': false}), 200);
        }),
      );

      expect(result, isFalse);
    });

    test('throws on non-2xx status', () async {
      await expectLater(
        http.runWithClient(
          () => ConsentApiService.isAiRetrievalGranted(
            patientUserId: 7,
            granteeUserId: 42,
          ),
          () => MockClient((req) async => http.Response('{}', 404)),
        ),
        throwsException,
      );
    });
  });
}
