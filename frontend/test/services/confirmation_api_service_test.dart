// Tests for ConfirmationApiService.
//
// ConfirmationApiService is a static-method service that calls the
// /v1/api/confirmations backend endpoints.
//
// Strategy:
//   • Mock the flutter_secure_storage MethodChannel so that
//     getAuthHeaders() returns headers with no Authorization token.
//   • Use http.runWithClient() to zone a MockClient over the global
//     HTTP client.  No real network traffic occurs.
//   • Verify request method, URL path, body, and response parsing.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:care_connect_app/services/confirmation_api_service.dart';

// ─── MethodChannel used by flutter_secure_storage ────────────────────────

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

// ─── Factory / helper functions ──────────────────────────────────────────

MockClient _mockJson(int statusCode, Object body) =>
    MockClient((_) async => http.Response(jsonEncode(body), statusCode));

MockClient _mockThrows(Object error) =>
    MockClient((_) async => throw error);

(MockClient, List<http.Request>) _capturingClient(
    int statusCode, Object body) {
  final captured = <http.Request>[];
  final client = MockClient((req) async {
    captured.add(req);
    return http.Response(jsonEncode(body), statusCode);
  });
  return (client, captured);
}

// ─── Sample response bodies ──────────────────────────────────────────────

Map<String, dynamic> _pendingItem({int id = 1}) => {
      'id': id,
      'sourceType': 'SUMMARY',
      'status': 'PENDING',
      'payload': '{"headline":"Took aspirin"}',
      'referenceId': 'call-$id',
      'requestedBy': 10,
      'resolvedBy': null,
      'resolvedAt': null,
      'resolutionNote': null,
      'createdAt': '2026-06-30T10:00:00',
      'updatedAt': '2026-06-30T10:00:00',
    };

Map<String, dynamic> _confirmedItem({int id = 1}) => {
      ..._pendingItem(id: id),
      'status': 'CONFIRMED',
      'resolvedBy': 20,
      'resolvedAt': '2026-06-30T11:00:00',
      'resolutionNote': 'Verified',
    };

Map<String, dynamic> _dismissedItem({int id = 1}) => {
      ..._pendingItem(id: id),
      'status': 'DISMISSED',
      'resolvedBy': 20,
      'resolvedAt': '2026-06-30T11:00:00',
      'resolutionNote': 'Inaccurate',
    };

// ─── Test entry point ────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _secureStorageChannel,
      (_) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  // ── fetchPendingItems ──────────────────────────────────────────────────

  group('fetchPendingItems()', () {
    test('returns list on HTTP 200', () async {
      final result = await http.runWithClient(
        () => ConfirmationApiService.fetchPendingItems(),
        () => _mockJson(200, [_pendingItem(id: 1), _pendingItem(id: 2)]),
      );
      expect(result['success'], isTrue);
      expect((result['items'] as List), hasLength(2));
    });

    test('sends GET to /v1/api/confirmations/pending', () async {
      final (client, captured) =
          _capturingClient(200, [_pendingItem()]);
      await http.runWithClient(
        () => ConfirmationApiService.fetchPendingItems(),
        () => client,
      );
      expect(captured, hasLength(1));
      expect(captured.first.method, 'GET');
      expect(captured.first.url.path, contains('/confirmations/pending'));
    });

    test('passes sourceType query param when provided', () async {
      final (client, captured) = _capturingClient(200, []);
      await http.runWithClient(
        () => ConfirmationApiService.fetchPendingItems(
            sourceType: 'ASK_AI'),
        () => client,
      );
      expect(
        captured.first.url.queryParameters['sourceType'],
        'ASK_AI',
      );
    });

    test('returns error on non-200 status', () async {
      final result = await http.runWithClient(
        () => ConfirmationApiService.fetchPendingItems(),
        () => _mockJson(403, {'error': 'Access denied'}),
      );
      expect(result['success'], isFalse);
    });

    test('returns error on network exception', () async {
      final result = await http.runWithClient(
        () => ConfirmationApiService.fetchPendingItems(),
        () => _mockThrows(Exception('No connectivity')),
      );
      expect(result['success'], isFalse);
      expect(result['error'], contains('No connectivity'));
    });
  });

  // ── fetchItem ──────────────────────────────────────────────────────────

  group('fetchItem()', () {
    test('returns item on HTTP 200', () async {
      final result = await http.runWithClient(
        () => ConfirmationApiService.fetchItem(1),
        () => _mockJson(200, _pendingItem(id: 1)),
      );
      expect(result['success'], isTrue);
      expect(result['item']['id'], 1);
    });

    test('sends GET to /v1/api/confirmations/{id}', () async {
      final (client, captured) = _capturingClient(200, _pendingItem());
      await http.runWithClient(
        () => ConfirmationApiService.fetchItem(42),
        () => client,
      );
      expect(captured.first.url.path, contains('/confirmations/42'));
    });

    test('returns error on 404', () async {
      final result = await http.runWithClient(
        () => ConfirmationApiService.fetchItem(99),
        () => _mockJson(404, {'error': 'Not found'}),
      );
      expect(result['success'], isFalse);
    });
  });

  // ── confirmItem ────────────────────────────────────────────────────────

  group('confirmItem()', () {
    test('returns confirmed item on HTTP 200', () async {
      final result = await http.runWithClient(
        () => ConfirmationApiService.confirmItem(1, note: 'Verified'),
        () => _mockJson(200, _confirmedItem(id: 1)),
      );
      expect(result['success'], isTrue);
      expect(result['item']['status'], 'CONFIRMED');
    });

    test('sends POST to /v1/api/confirmations/{id}/confirm', () async {
      final (client, captured) =
          _capturingClient(200, _confirmedItem());
      await http.runWithClient(
        () => ConfirmationApiService.confirmItem(7, note: 'ok'),
        () => client,
      );
      expect(captured.first.method, 'POST');
      expect(captured.first.url.path, contains('/confirmations/7/confirm'));
    });

    test('includes note in request body when provided', () async {
      final (client, captured) =
          _capturingClient(200, _confirmedItem());
      await http.runWithClient(
        () => ConfirmationApiService.confirmItem(1, note: 'Looks good'),
        () => client,
      );
      final body = jsonDecode(captured.first.body);
      expect(body['note'], 'Looks good');
    });

    test('sends empty body when note is null', () async {
      final (client, captured) =
          _capturingClient(200, _confirmedItem());
      await http.runWithClient(
        () => ConfirmationApiService.confirmItem(1),
        () => client,
      );
      // Body should be empty or have null note
      final bodyStr = captured.first.body;
      if (bodyStr.isNotEmpty) {
        final body = jsonDecode(bodyStr);
        expect(body['note'], isNull);
      }
    });

    test('returns error on 400 (not PENDING)', () async {
      final result = await http.runWithClient(
        () => ConfirmationApiService.confirmItem(1),
        () => _mockJson(400, {'error': 'Item is not PENDING'}),
      );
      expect(result['success'], isFalse);
    });
  });

  // ── dismissItem ────────────────────────────────────────────────────────

  group('dismissItem()', () {
    test('returns dismissed item on HTTP 200', () async {
      final result = await http.runWithClient(
        () => ConfirmationApiService.dismissItem(1, note: 'Inaccurate'),
        () => _mockJson(200, _dismissedItem(id: 1)),
      );
      expect(result['success'], isTrue);
      expect(result['item']['status'], 'DISMISSED');
    });

    test('sends POST to /v1/api/confirmations/{id}/dismiss', () async {
      final (client, captured) =
          _capturingClient(200, _dismissedItem());
      await http.runWithClient(
        () => ConfirmationApiService.dismissItem(5),
        () => client,
      );
      expect(captured.first.method, 'POST');
      expect(captured.first.url.path, contains('/confirmations/5/dismiss'));
    });

    test('returns error on network exception', () async {
      final result = await http.runWithClient(
        () => ConfirmationApiService.dismissItem(1),
        () => _mockThrows(Exception('Timeout')),
      );
      expect(result['success'], isFalse);
    });
  });

  // ── fetchItemsByUser ───────────────────────────────────────────────────

  group('fetchItemsByUser()', () {
    test('returns items on HTTP 200', () async {
      final result = await http.runWithClient(
        () => ConfirmationApiService.fetchItemsByUser(10),
        () => _mockJson(200, [_pendingItem(), _confirmedItem(id: 2)]),
      );
      expect(result['success'], isTrue);
      expect((result['items'] as List), hasLength(2));
    });

    test('sends GET to /v1/api/confirmations/user/{userId}', () async {
      final (client, captured) = _capturingClient(200, []);
      await http.runWithClient(
        () => ConfirmationApiService.fetchItemsByUser(42),
        () => client,
      );
      expect(captured.first.url.path, contains('/confirmations/user/42'));
    });
  });
}
