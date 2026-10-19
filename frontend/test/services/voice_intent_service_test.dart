import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:care_connect_app/services/voice_intent_service.dart';

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Future<T> _withClient<T>(http.Client client, Future<T> Function() action) {
  return http.runWithClient(action, () => client);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    VoiceIntentService.testOverride = null;
    VoiceIntentService.requestTimeout = const Duration(seconds: 3);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (_) async => null);
  });

  tearDown(() {
    VoiceIntentService.testOverride = null;
    VoiceIntentService.requestTimeout = const Duration(seconds: 3);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  test('returns the successful backend intent response', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode({
          'intent': 'navigate',
          'entities': {'destination': 'calendar'},
          'confidence': 0.95,
          'destination': '/calendar',
          'displayLabel': 'Navigate to calendar',
          'requiresConfirmation': true,
          'success': true,
        }),
        200,
      );
    });

    final result = await _withClient(
      client,
      () => VoiceIntentService.extractIntent(
        utterance: 'open calendar',
        locale: 'en',
        screenId: '/voice',
      ),
    );

    expect(result, isNotNull);
    expect(result!.intent, 'navigate');
    expect(result.entities['destination'], 'calendar');
    expect(result.destination, '/calendar');
    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/voice/intent');
  });

  test('returns null for an unavailable intent result', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({'intent': 'unknown', 'success': false}),
        200,
      ),
    );

    final result = await _withClient(
      client,
      () => VoiceIntentService.extractIntent(utterance: 'open calendar'),
    );

    expect(result, isNull);
  });

  test('returns null for a non-success HTTP response', () async {
    final client = MockClient((_) async => http.Response('', 503));

    final result = await _withClient(
      client,
      () => VoiceIntentService.extractIntent(utterance: 'open calendar'),
    );

    expect(result, isNull);
  });

  test('returns null after the request timeout so keyword fallback can run',
      () async {
    VoiceIntentService.requestTimeout = const Duration(milliseconds: 1);
    final neverCompletes = Completer<http.Response>();
    final client = MockClient((_) => neverCompletes.future);

    final result = await _withClient(
      client,
      () => VoiceIntentService.extractIntent(utterance: 'open calendar'),
    );

    expect(result, isNull);
  });
}
