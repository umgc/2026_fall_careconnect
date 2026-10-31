import 'dart:convert';
import 'dart:typed_data';

import 'package:care_connect_app/services/colibri_service.dart';
import 'package:care_connect_app/services/mediapipe_llm_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(Map<String, dynamic> body, {int statusCode = 200}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('care_connect/mediapipe_llm');
  final service = MediaPipeLlmService();
  final colibri = ColibriService();

  setUp(() {
    service.resetForTesting();
    colibri.debugResetResolvedBaseUrl();
  });

  tearDown(() {
    service.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('MediaPipeLlmService Clinical Safety Escalation Tests', () {
    test('queryLocalClinicalAssistant immediately escalates clinical dosage alterations', () async {
      final res = await service.queryLocalClinicalAssistant(
        question: 'Can I cut my dosage in half?',
      );

      expect(res['success'], isTrue);
      expect(res['escalateToCloud'], isTrue);
      expect(res['content'], contains(ColibriService.escalateToken));
    });

    test('queryLocalClinicalAssistant immediately escalates multi-campus directory inquiries', () async {
      final res = await service.queryLocalClinicalAssistant(
        question: 'Where is my clinic other office located?',
      );

      expect(res['success'], isTrue);
      expect(res['escalateToCloud'], isTrue);
      expect(res['content'], contains(ColibriService.escalateToken));
    });

    test('queryLocalClinicalAssistant immediately escalates acute symptom diagnosis', () async {
      final res = await service.queryLocalClinicalAssistant(
        question: 'I have severe chest pain and dizziness',
      );

      expect(res['success'], isTrue);
      expect(res['escalateToCloud'], isTrue);
      expect(res['content'], contains(ColibriService.escalateToken));
    });
  });

  group('MediaPipeLlmService Confirmed Engine Readiness & Rejection Tests', () {
    test('rejects medication inference when Gemma engine has not been initialized', () async {
      var completionCalls = 0;
      colibri.debugSetHttpClientAdapter(_FakeHttpClientAdapter((options) async {
        if (options.path.endsWith('/chat/completions')) {
          completionCalls++;
        }
        return _jsonResponse({'error': 'should not be called'}, statusCode: 503);
      }));

      final res = await service.queryLocalClinicalAssistant(
        question: 'What medications am I currently taking?',
      );

      expect(res['success'], isFalse);
      expect(res['error'], contains('not initialized or ready'));
      expect(completionCalls, equals(0));
      expect(service.isInitialized, isFalse);
    });

    test('rejects empty prompts immediately', () async {
      final res = await service.generateResponse('   ');
      expect(res['success'], isFalse);
      expect(res['error'], contains('cannot be empty'));
    });

    test('does not treat unconfirmed model listings as initialized Gemma engine', () async {
      var chatCalled = false;
      colibri.debugSetHttpClientAdapter(_FakeHttpClientAdapter((options) async {
        if (options.path.endsWith('/models')) {
          return _jsonResponse({
            'object': 'list',
            'litert_model_loaded': false,
            'gemma_ready': false,
            'data': [
              {'id': 'olmoe-colibri'},
              {'id': 'gemma-2b-mediapipe'},
            ],
          });
        }
        chatCalled = true;
        return _jsonResponse({
          'model': 'gemma-2b-mediapipe',
          'choices': [
            {
              'message': {
                'content':
                    'Your active medications on file are Lisinopril and Metformin.',
              },
            },
          ],
        });
      }));

      final availability = await service.checkAvailability();
      expect(availability['available'], isFalse);
      expect(availability['isInitialized'], isFalse);
      expect(service.isInitialized, isFalse);

      final initOk = await service.initialize();
      expect(initOk, isFalse);
      expect(service.isInitialized, isFalse);

      final inference = await service.queryLocalClinicalAssistant(
        question: 'What medications am I currently taking?',
      );
      expect(inference['success'], isFalse);
      expect(chatCalled, isFalse);
    });

    test('initializes and executes inference only when Gemma readiness is explicitly confirmed', () async {
      colibri.debugSetHttpClientAdapter(_FakeHttpClientAdapter((options) async {
        if (options.path.endsWith('/models')) {
          return _jsonResponse({
            'object': 'list',
            'litert_model_loaded': true,
            'gemma_ready': true,
            'data': [
              {'id': 'olmoe-colibri'},
              {'id': 'gemma-2b-mediapipe'},
            ],
          });
        }
        return _jsonResponse({
          'model': 'gemma-2b-mediapipe',
          'choices': [
            {
              'message': {
                'content': 'Per your patient record, take vitamin D3 daily.',
              },
            },
          ],
          'usage': {'total_tokens': 18},
        });
      }));

      final availability = await service.checkAvailability();
      expect(availability['available'], isTrue);
      expect(availability['isInitialized'], isTrue);
      expect(service.isInitialized, isTrue);

      final response = await service.queryLocalClinicalAssistant(
        question: 'What supplements are listed in my context?',
        localPatientData: {'supplements': ['Vitamin D3']},
      );

      expect(response['success'], isTrue);
      expect(response['model'], equals('gemma-2b-mediapipe'));
      expect(response['content'], contains('vitamin D3'));
      expect(response['escalateToCloud'], isFalse);
    });

    test('resets initialization and rejects output if bridge becomes unavailable during inference', () async {
      colibri.debugSetHttpClientAdapter(_FakeHttpClientAdapter((options) async {
        if (options.path.endsWith('/models')) {
          return _jsonResponse({
            'object': 'list',
            'gemma_ready': true,
            'data': [
              {'id': 'gemma-2b-mediapipe'},
            ],
          });
        }
        return _jsonResponse(
          {
            'error': {
              'message': 'Gemma engine is not loaded or ready.',
              'code': 'GEMMA_ENGINE_NOT_READY',
            },
          },
          statusCode: 503,
        );
      }));

      expect(await service.initialize(), isTrue);

      final res = await service.generateResponse('Hello');
      expect(res['success'], isFalse);
      expect(service.isInitialized, isFalse);
    });

    test('Android native MethodChannel requires confirmed initialization and does not fall back to unverified bridge', () async {
      service.debugIsAndroidOverride = true;
      var nativeInitCalled = false;

      colibri.debugSetHttpClientAdapter(_FakeHttpClientAdapter((options) async {
        return _jsonResponse({
          'object': 'list',
          'gemma_ready': false,
          'data': [
            {'id': 'olmoe-colibri'},
          ],
        });
      }));

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        switch (call.method) {
          case 'isAvailable':
            return {
              'available': true,
              'isInitialized': false,
              'modelPath': '/sdcard/Download/gemma-2b.bin',
            };
          case 'initialize':
            nativeInitCalled = true;
            return {
              'success': true,
              'modelPath': '/sdcard/Download/gemma-2b.bin',
            };
          case 'generate':
            return {
              'success': true,
              'content': 'Your appointment with Dr. Carter is Friday at 2:00 PM.',
              'model': 'gemma-2b-mediapipe',
              'latencyMs': 240,
            };
          default:
            return null;
        }
      });

      final availability = await service.checkAvailability();
      expect(nativeInitCalled, isTrue);
      expect(availability['available'], isTrue);
      expect(availability['isInitialized'], isTrue);

      final gen = await service.generateResponse('When is my appointment?');
      expect(gen['success'], isTrue);
      expect(gen['content'], contains('Dr. Carter'));

      // Now simulate native inference error and verify it rejects rather than silently succeeding
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'initialize') {
          return {'success': true};
        }
        if (call.method == 'generate') {
          throw PlatformException(code: 'INFERENCE_ERROR', message: 'engine closed');
        }
        return null;
      });

      expect(await service.initialize(modelPath: '/sdcard/Download/gemma-2b.bin'), isTrue);
      final failedGen = await service.generateResponse('What medications am I taking?');
      expect(failedGen['success'], isFalse);
      expect(service.isInitialized, isFalse);
    });
  });
}
