import 'dart:convert';
import 'dart:typed_data';

import 'package:care_connect_app/services/colibri_service.dart';
import 'package:dio/dio.dart';
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

  final colibri = ColibriService();

  setUp(() {
    colibri.debugResetResolvedBaseUrl();
  });

  group('ColibriService - Tiered Clinical Safety Triage Tests', () {
    test('shouldEscalateToCloud returns false for routine account and scheduling queries', () {
      expect(ColibriService.shouldEscalateToCloud(''), isFalse);
      expect(ColibriService.shouldEscalateToCloud('   '), isFalse);
      expect(ColibriService.shouldEscalateToCloud('When is my next appointment?'), isFalse);
      expect(ColibriService.shouldEscalateToCloud('Who is my doctor?'), isFalse);
      expect(ColibriService.shouldEscalateToCloud('What medications am I currently taking?'), isFalse);
      expect(ColibriService.shouldEscalateToCloud('Show my daily check-in tasks'), isFalse);
      expect(ColibriService.shouldEscalateToCloud('Good morning, how are you today?'), isFalse);
      expect(ColibriService.shouldEscalateToCloud('How do I update my profile phone number?'), isFalse);
    });

    test('shouldEscalateToCloud returns true for dosage alteration requests', () {
      expect(ColibriService.shouldEscalateToCloud('Can I cut my dosage in half?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Can I cut dosage in half?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Can I cut this pill in half?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Should I split my pill?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Can I double my dose because I forgot yesterday?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Should I stop taking my medication?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Can I skip my morning dose?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Can I halve my tablet dose?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('I want to break the tablet in half'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Are there side effects or drug interactions?'), isTrue);
    });

    test('shouldEscalateToCloud returns true for clinical symptoms and diagnosis', () {
      expect(ColibriService.shouldEscalateToCloud('I have severe chest pain and dizziness'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Please diagnose my symptoms of shortness of breath'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('I have an emergency allergic reaction'), isTrue);
    });

    test('shouldEscalateToCloud returns true for multi-campus external clinic inquiries', () {
      expect(ColibriService.shouldEscalateToCloud('Where is my clinic other office located?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Where is the another office?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('What is the address of the other clinic branch?'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Directions to the downtown location campus'), isTrue);
      expect(ColibriService.shouldEscalateToCloud('Where is the second facility?'), isTrue);
    });

    test('getDefaultColibriUrl returns valid HTTP URL', () {
      final url = colibri.getDefaultColibriUrl();
      expect(url, startsWith('http://'));
      expect(url, contains(':8000/v1'));
    });

    test('queryLocalClinicalAssistant escalates immediate clinical questions', () async {
      final result = await colibri.queryLocalClinicalAssistant(
        question: 'Can I cut my dosage in half?',
      );

      expect(result['success'], isTrue);
      expect(result['escalateToCloud'], isTrue);
      expect(result['content'], contains(ColibriService.escalateToken));
    });

    test('escalateToken constant matches cloud contract', () {
      expect(ColibriService.escalateToken, equals('[ESCALATE_TO_CLINICAL_CLOUD]'));
    });
  });

  group('ColibriService - Health, Gemma Readiness, and Chat Completion', () {
    test('checkHealth parses advertised model IDs and handles connection failures', () async {
      colibri.debugSetHttpClientAdapter(_FakeHttpClientAdapter((options) async {
        expect(options.path, endsWith('/models'));
        return _jsonResponse({
          'object': 'list',
          'data': [
            {'id': 'olmoe-colibri'},
          ],
        });
      }));

      final models = await colibri.checkHealth(customBaseUrl: 'http://127.0.0.1:8000/v1');
      expect(models, equals(['olmoe-colibri']));

      colibri.debugSetHttpClientAdapter(_FakeHttpClientAdapter((options) async {
        throw DioException(requestOptions: options, message: 'offline');
      }));
      expect(await colibri.checkHealth(customBaseUrl: 'http://127.0.0.1:8000/v1'), isEmpty);
    });

    test('checkGemmaReadiness rejects model listing when gemma_ready and litert_model_loaded are false', () async {
      colibri.debugSetHttpClientAdapter(_FakeHttpClientAdapter((options) async {
        return _jsonResponse({
          'object': 'list',
          'litert_model_loaded': false,
          'gemma_ready': false,
          'data': [
            {'id': 'olmoe-colibri'},
            {'id': 'gemma-2b-mediapipe'},
          ],
        });
      }));

      final readiness = await colibri.checkGemmaReadiness();
      expect(readiness['ready'], isFalse);
      expect(readiness['reason'], contains('no Gemma engine is loaded'));
    });

    test('checkGemmaReadiness succeeds only when gemma-2b-mediapipe is listed and engine readiness is confirmed', () async {
      colibri.debugSetHttpClientAdapter(_FakeHttpClientAdapter((options) async {
        return _jsonResponse({
          'object': 'list',
          'litert_model_loaded': true,
          'gemma_ready': true,
          'data': [
            {'id': 'olmoe-colibri'},
            {'id': 'gemma-2b-mediapipe'},
          ],
        });
      }));

      final readiness = await colibri.checkGemmaReadiness();
      expect(readiness['ready'], isTrue);
      expect(readiness['models'], contains(ColibriService.gemmaModelId));
    });

    test('completeChat and queryLocalClinicalAssistant handle HTTP 200 and non-200 responses', () async {
      colibri.debugSetHttpClientAdapter(_FakeHttpClientAdapter((options) async {
        expect(options.path, endsWith('/chat/completions'));
        return _jsonResponse({
          'model': 'olmoe-colibri',
          'choices': [
            {
              'message': {'content': 'Your next appointment is Friday at 10 AM.'},
            },
          ],
          'usage': {'total_tokens': 24},
        });
      }));

      final ok = await colibri.queryLocalClinicalAssistant(
        question: 'When is my next appointment?',
        localPatientData: {'patientName': 'Alex'},
      );
      expect(ok['success'], isTrue);
      expect(ok['model'], equals('olmoe-colibri'));
      expect(ok['content'], contains('Friday at 10 AM'));
      expect(ok['escalateToCloud'], isFalse);

      colibri.debugSetHttpClientAdapter(_FakeHttpClientAdapter((options) async {
        return _jsonResponse({'error': 'unavailable'}, statusCode: 503);
      }));

      final failed = await colibri.completeChat(
        prompt: 'What medications am I taking?',
        model: ColibriService.gemmaModelId,
      );
      expect(failed['success'], isFalse);
    });
  });
}
