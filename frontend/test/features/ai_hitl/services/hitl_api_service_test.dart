import 'dart:convert';

import 'package:care_connect_app/features/ai_hitl/models/hitl_models.dart';
import 'package:care_connect_app/features/ai_hitl/services/hitl_api_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

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

  const heldId = '11111111-1111-1111-1111-111111111111';

  group('HitlQueueItem / HitlDetail parsing', () {
    test('parses queue item', () {
      final item = HitlQueueItem.fromJson({
        'heldItemId': heldId,
        'patientId': 42,
        'triggerCodes': ['UNSUPPORTED_CLAIM'],
        'queryPreview': 'Should I stop metformin?',
        'sourceSurface': 'ASK_AI',
        'createdAt': '2026-07-21T12:00:00Z',
        'expiresAt': '2026-07-24T12:00:00Z',
      });
      expect(item.heldItemId, heldId);
      expect(item.patientId, 42);
      expect(item.triggerCodes, ['UNSUPPORTED_CLAIM']);
      expect(item.queryPreview, 'Should I stop metformin?');
    });

    test('parses detail and flags unsupported claim', () {
      final detail = HitlDetail.fromJson({
        'heldItemId': heldId,
        'patientId': 42,
        'status': 'PENDING_REVIEW',
        'deliveryStatus': 'HELD',
        'triggerCodes': ['UNSUPPORTED_CLAIM'],
        'queryText': 'Q',
        'draftAnswer': 'Draft',
      });
      expect(detail.isPending, isTrue);
      expect(detail.requiresEditedAnswer, isTrue);
    });
  });

  group('HitlApiService', () {
    test('fetchQueue parses list', () async {
      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/v1/api/ai/hitl/queue'));
        return http.Response(
          jsonEncode([
            {
              'heldItemId': heldId,
              'patientId': 7,
              'triggerCodes': ['EMERGENCY'],
              'queryPreview': 'Help',
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final items = await HitlApiService.instance.fetchQueue(client: client);
      expect(items, hasLength(1));
      expect(items.first.patientId, 7);
    });

    test('release posts editedAnswer', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, endsWith('/$heldId/release'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['editedAnswer'], 'Safe answer');
        return http.Response(
          jsonEncode({
            'heldItemId': heldId,
            'patientId': 7,
            'status': 'DELIVERED',
            'deliveryStatus': 'DELIVERED',
            'triggerCodes': <String>[],
            'draftAnswer': 'Draft',
            'finalAnswer': 'Safe answer',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final detail = await HitlApiService.instance.release(
        heldId,
        editedAnswer: 'Safe answer',
        client: client,
      );
      expect(detail.status, 'DELIVERED');
      expect(detail.finalAnswer, 'Safe answer');
    });

    test('reject maps conflict errors', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'CONFLICT',
            'message': 'Held item is not pending review',
          }),
          409,
          headers: {'content-type': 'application/json'},
        );
      });

      expect(
        () => HitlApiService.instance.reject(heldId, client: client),
        throwsA(
          isA<HitlApiException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.message, 'message', contains('not pending')),
        ),
      );
    });
  });
}
