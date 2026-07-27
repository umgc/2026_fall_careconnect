// Tests for AIChatService.
//
// AIChatService is a static-method service that:
//   1. Calls ApiService.getAuthHeaders() which reads a JWT from
//      flutter_secure_storage (platform channel).
//   2. Issues HTTP requests via the top-level http.post / http.get /
//      http.delete functions.
//
// Strategy:
//   • Mock the flutter_secure_storage MethodChannel so that all reads return
//     null.  This causes getAuthHeaders() to return headers with no
//     Authorization token (equivalent to an unauthenticated test context).
//   • Use http.runWithClient() to zone a MockClient over the global HTTP client
//     for the duration of each tested call.  No real network traffic occurs.
//
// NOTE: analyzeFile() uses http.MultipartFile.fromPath which requires access
// to the real filesystem.  Its error-path (non-existent file) is covered by
// a dedicated test group; the happy path requires an integration test.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:care_connect_app/services/ai_chat_service.dart';

// ─── MethodChannel used by flutter_secure_storage ────────────────────────────

// The flutter_secure_storage plugin registers under this channel name on
// Android and iOS.  All method calls are intercepted and return null so that
// getJwtToken() returns null → getAuthHeaders() omits the Authorization header.
const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

// ─── Factory / helper functions ───────────────────────────────────────────────

/// Returns a [MockClient] that replies to every request with [statusCode] and
/// a JSON-encoded [body].
MockClient _mockJson(int statusCode, Object body) =>
    MockClient((_) async => http.Response(jsonEncode(body), statusCode));

/// Returns a [MockClient] that replies with [statusCode] and a plain [rawBody].
/// Use for empty bodies or error payloads that are not JSON.
MockClient _mockRaw(int statusCode, String rawBody) =>
    MockClient((_) async => http.Response(rawBody, statusCode));

/// Returns a [MockClient] that throws [error] on every request.
/// Use for simulating network and other transport-layer exceptions.
MockClient _mockThrows(Object error) => MockClient((_) async => throw error);

/// Returns a ([MockClient], capturedRequests) pair.
/// Every outgoing request is captured in the returned list so that individual
/// tests can assert on method, URL, headers, and body.
(MockClient, List<http.Request>) _capturingClient(int statusCode, Object body) {
  final captured = <http.Request>[];
  final client = MockClient((req) async {
    captured.add(req);
    return http.Response(jsonEncode(body), statusCode);
  });
  return (client, captured);
}

// ─── Test entry point ─────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Intercept all flutter_secure_storage channel calls and return null.
    // This prevents MissingPluginException in tests and simulates empty storage
    // so getAuthHeaders() returns {"Content-Type":"application/json"} only.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _secureStorageChannel,
      (_) async => null,
    );
  });

  tearDown(() {
    // Remove the mock handler after each test so tests remain independent.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 1 — sendMessage(): success responses
  //
  // When the backend returns HTTP 200 with success:true, sendMessage() must
  // extract and return aiResponse, conversationId, modelUsed, and
  // processingTimeMs from the response envelope.
  // ──────────────────────────────────────────────────────────────────────────
  group('sendMessage() — success', () {
    // Minimal success response body from the backend.
    Map<String, dynamic> successBody({
      String aiResponse = 'Hello!',
      String conversationId = 'conv-123',
      String modelUsed = 'deepseek-chat',
      int processingTimeMs = 42,
    }) =>
        {
          'success': true,
          'aiResponse': aiResponse,
          'conversationId': conversationId,
          'modelUsed': modelUsed,
          'processingTimeMs': processingTimeMs,
        };

    test('returns success:true on HTTP 200 with success flag', () async {
      // The top-level success key must be propagated to callers so they can
      // distinguish a successful AI reply from a backend-reported error.
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockJson(200, successBody()),
      );
      expect(result['success'], isTrue);
    });

    test('returns the aiResponse field from the response', () async {
      // The AI-generated reply is what gets displayed to the user.
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockJson(200, successBody(aiResponse: 'Greetings!')),
      );
      expect(result['aiResponse'], 'Greetings!');
    });

    test('returns the conversationId field from the response', () async {
      // The conversation ID is needed for follow-up messages in the same
      // session.
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockJson(200, successBody(conversationId: 'conv-999')),
      );
      expect(result['conversationId'], 'conv-999');
    });

    test('returns the modelUsed field from the response', () async {
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockJson(200, successBody(modelUsed: 'gpt-4')),
      );
      expect(result['modelUsed'], 'gpt-4');
    });

    test('returns the processingTimeMs field from the response', () async {
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockJson(200, successBody(processingTimeMs: 150)),
      );
      expect(result['processingTimeMs'], 150);
    });

    test('returns success:false when response has success:false', () async {
      // Backend can report a logical error even on HTTP 200 (e.g. AI timeout).
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockJson(200, {
          'success': false,
          'errorMessage': 'AI unavailable',
        }),
      );
      expect(result['success'], isFalse);
    });

    test('maps logical backend failure to a stable safe message', () async {
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockJson(200, {
          'success': false,
          'errorMessage': 'AI unavailable',
        }),
      );
      expect(
        result['errorMessage'],
        'The AI service could not complete your request. Please try again.',
      );
    });

    test('does not surface a raw backend error field', () async {
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockJson(200, {
          'success': false,
          'error': 'Backend error',
        }),
      );
      expect(result['errorMessage'], isNot(contains('Backend error')));
    });

    test('uses the same stable message when backend error fields are absent',
        () async {
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockJson(200, {'success': false}),
      );
      expect(
        result['errorMessage'],
        'The AI service could not complete your request. Please try again.',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 2 — sendMessage(): HTTP error codes
  //
  // Each non-200 HTTP status that the service handles explicitly must produce
  // success:false plus a caller-visible error string.
  // ──────────────────────────────────────────────────────────────────────────
  group('sendMessage() — HTTP error codes', () {
    test('returns success:false on 401 Unauthorized', () async {
      // A 401 means the token has expired; the caller needs to re-authenticate.
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockRaw(401, 'Unauthorized'),
      );
      expect(result['success'], isFalse);
    });

    test('returns auth-expired message on 401', () async {
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockRaw(401, 'Unauthorized'),
      );
      expect(result['error'], contains('Authentication failed'));
    });

    test('returns success:false on 403 Forbidden', () async {
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockRaw(403, 'Forbidden'),
      );
      expect(result['success'], isFalse);
    });

    test('returns access-denied message on 403', () async {
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockRaw(403, 'Forbidden'),
      );
      expect(result['error'], contains('Access denied'));
    });

    test('returns success:false on 429 Too Many Requests', () async {
      // Rate-limit responses must surface as a specific user-facing message.
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockRaw(429, 'Rate limited'),
      );
      expect(result['success'], isFalse);
    });

    test('returns rate-limit message on 429', () async {
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockRaw(429, 'Rate limited'),
      );
      expect(result['error'], contains('Rate limit exceeded'));
    });

    test('returns success:false on 500 Server Error', () async {
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockRaw(500, 'Internal Server Error'),
      );
      expect(result['success'], isFalse);
    });

    test('returns server-error message that includes the status code on 500',
        () async {
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockRaw(500, 'Internal Server Error'),
      );
      expect(result['error'], contains('500'));
    });

    test('returns success:false on 503 Service Unavailable', () async {
      // Any 5xx code must be handled as a server-error.
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockRaw(503, 'Service Unavailable'),
      );
      expect(result['success'], isFalse);
    });

    test('never exposes a raw backend failure body', () async {
      const sensitiveBody =
          '{"message":"SQL failed for patient@example.com","stack":"secret"}';
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockRaw(500, sensitiveBody),
      );

      expect(result.values.join(' '), isNot(contains('patient@example.com')));
      expect(result.values.join(' '), isNot(contains('secret')));
    });

    test('returns success:false on an unexpected 4xx code (e.g. 422)',
        () async {
      // Non-enumerated status codes fall through to the generic error branch.
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockRaw(422, 'Unprocessable Entity'),
      );
      expect(result['success'], isFalse);
    });

    test('includes the unexpected status code in the error string', () async {
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockRaw(422, 'Unprocessable Entity'),
      );
      expect(result['error'], contains('422'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 3 — sendMessage(): exception handling
  //
  // Transport-layer exceptions must be caught and converted to success:false
  // maps rather than propagating as unhandled exceptions to callers.
  // ──────────────────────────────────────────────────────────────────────────
  group('sendMessage() — exception handling', () {
    test('returns success:false on http.ClientException (network error)',
        () async {
      // A ClientException means the TCP connection failed — no response exists.
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockThrows(
          http.ClientException('Connection refused'),
        ),
      );
      expect(result['success'], isFalse);
    });

    test('includes "Network error" in the error field on ClientException',
        () async {
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockThrows(
          http.ClientException('Connection refused'),
        ),
      );
      expect(result['error'], contains('Network error'));
    });

    test('returns success:false on FormatException (malformed JSON)', () async {
      // A 200 response with an invalid JSON body must not crash the service.
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockRaw(200, '{invalid json{{'),
      );
      expect(result['success'], isFalse);
    });

    test('includes "Invalid response format" in error on FormatException',
        () async {
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockRaw(200, '{invalid json{{'),
      );
      expect(result['error'], contains('Invalid response format'));
    });

    test('returns success:false on generic exception', () async {
      // Any unexpected exception type must be caught as a generic failure.
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockThrows(Exception('Something went wrong')),
      );
      expect(result['success'], isFalse);
    });

    test('includes "Failed to send message" in error on generic exception',
        () async {
      final result = await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => _mockThrows(Exception('Something went wrong')),
      );
      expect(result['error'], contains('Failed to send message'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 4 — sendMessage(): request construction
  //
  // The outgoing POST body must faithfully encode all provided parameters.
  // Optional parameters must be present when supplied and absent when null.
  // ──────────────────────────────────────────────────────────────────────────
  group('sendMessage() — request body', () {
    // Helper that captures a single request and returns its decoded JSON body.
    Future<Map<String, dynamic>> captureBody({
      String message = 'Hello',
      int userId = 42,
      int? patientId,
      String? conversationId,
      String chatType = 'GENERAL_SUPPORT',
      String? title,
      String preferredModel = 'deepseek-chat',
      double temperature = 0.7,
      int maxTokens = 1000,
      bool includeVitals = true,
      bool includeMedications = true,
      bool includeNotes = true,
      bool includeMoodPainLogs = true,
      bool includeAllergies = true,
      List<Map<String, dynamic>>? uploadedFiles,
    }) async {
      final (client, requests) = _capturingClient(200, {
        'success': true,
        'aiResponse': '',
        'conversationId': '',
        'modelUsed': '',
        'processingTimeMs': 0,
      });
      await http.runWithClient(
        () => AIChatService.sendMessage(
          message: message,
          userId: userId,
          patientId: patientId,
          conversationId: conversationId,
          chatType: chatType,
          title: title,
          preferredModel: preferredModel,
          temperature: temperature,
          maxTokens: maxTokens,
          includeVitals: includeVitals,
          includeMedications: includeMedications,
          includeNotes: includeNotes,
          includeMoodPainLogs: includeMoodPainLogs,
          includeAllergies: includeAllergies,
          uploadedFiles: uploadedFiles,
        ),
        () => client,
      );
      return jsonDecode(requests.single.body) as Map<String, dynamic>;
    }

    test('uses POST method', () async {
      final (client, requests) = _capturingClient(200, {
        'success': true,
        'aiResponse': '',
        'conversationId': '',
        'modelUsed': '',
        'processingTimeMs': 0,
      });
      await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => client,
      );
      expect(requests.single.method, 'POST');
    });

    test('hits the /v1/api/ai-chat/chat endpoint', () async {
      final (client, requests) = _capturingClient(200, {
        'success': true,
        'aiResponse': '',
        'conversationId': '',
        'modelUsed': '',
        'processingTimeMs': 0,
      });
      await http.runWithClient(
        () => AIChatService.sendMessage(message: 'Hi', userId: 1),
        () => client,
      );
      expect(requests.single.url.path, '/v1/api/ai-chat/chat');
    });

    test('request body includes the message field', () async {
      final body = await captureBody(message: 'How are you?');
      expect(body['message'], 'How are you?');
    });

    test('request body includes the userId field', () async {
      final body = await captureBody(userId: 99);
      expect(body['userId'], 99);
    });

    test('request body includes patientId when provided', () async {
      final body = await captureBody(patientId: 7);
      expect(body['patientId'], 7);
    });

    test('request body omits patientId when not provided', () async {
      // Sending null patientId may break backend validation.
      final body = await captureBody(patientId: null);
      expect(body.containsKey('patientId'), isFalse);
    });

    test('request body includes conversationId when provided', () async {
      final body = await captureBody(conversationId: 'conv-abc');
      expect(body['conversationId'], 'conv-abc');
    });

    test('request body omits conversationId when not provided', () async {
      final body = await captureBody(conversationId: null);
      expect(body.containsKey('conversationId'), isFalse);
    });

    test('request body includes the chatType field', () async {
      final body = await captureBody(chatType: 'MEDICAL_QUERY');
      expect(body['chatType'], 'MEDICAL_QUERY');
    });

    test('request body includes title when provided', () async {
      final body = await captureBody(title: 'My Chat');
      expect(body['title'], 'My Chat');
    });

    test('request body omits title when not provided', () async {
      final body = await captureBody(title: null);
      expect(body.containsKey('title'), isFalse);
    });

    test('request body includes preferredModel', () async {
      final body = await captureBody(preferredModel: 'gpt-4');
      expect(body['preferredModel'], 'gpt-4');
    });

    test('request body includes temperature', () async {
      final body = await captureBody(temperature: 0.5);
      expect(body['temperature'], 0.5);
    });

    test('request body includes maxTokens', () async {
      final body = await captureBody(maxTokens: 500);
      expect(body['maxTokens'], 500);
    });

    test('request body includes includeVitals flag', () async {
      final body = await captureBody(includeVitals: false);
      expect(body['includeVitals'], false);
    });

    test('request body includes includeMedications flag', () async {
      final body = await captureBody(includeMedications: false);
      expect(body['includeMedications'], false);
    });

    test('request body includes includeNotes flag', () async {
      final body = await captureBody(includeNotes: false);
      expect(body['includeNotes'], false);
    });

    test('request body includes includeMoodPainLogs flag', () async {
      final body = await captureBody(includeMoodPainLogs: false);
      expect(body['includeMoodPainLogs'], false);
    });

    test('request body includes includeAllergies flag', () async {
      final body = await captureBody(includeAllergies: false);
      expect(body['includeAllergies'], false);
    });

    test('request body includes uploadedFiles when non-empty list provided',
        () async {
      final files = [
        {'name': 'report.pdf', 'content': 'base64data'}
      ];
      final body = await captureBody(uploadedFiles: files);
      expect(body.containsKey('uploadedFiles'), isTrue);
      expect((body['uploadedFiles'] as List), hasLength(1));
    });

    test('request body omits uploadedFiles when null', () async {
      final body = await captureBody(uploadedFiles: null);
      expect(body.containsKey('uploadedFiles'), isFalse);
    });

    test('request body omits uploadedFiles when empty list provided', () async {
      // An empty list is treated the same as null to keep the payload lean.
      final body = await captureBody(uploadedFiles: []);
      expect(body.containsKey('uploadedFiles'), isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 5 — clearConversation()
  //
  // Sends a POST to the deactivate endpoint.  Succeeds silently on 200;
  // rethrows any exception (non-200 or transport error) so callers can decide
  // how to handle failures.
  // ──────────────────────────────────────────────────────────────────────────
  group('clearConversation()', () {
    test('completes normally on HTTP 200', () async {
      await expectLater(
        http.runWithClient(
          () => AIChatService.clearConversation('conv-abc'),
          () => _mockRaw(200, ''),
        ),
        completes,
      );
    });

    test('uses POST method', () async {
      final (client, requests) = _capturingClient(200, {});
      await http.runWithClient(
        () => AIChatService.clearConversation('conv-abc'),
        () => client,
      );
      expect(requests.single.method, 'POST');
    });

    test('embeds the conversationId in the URL path', () async {
      // The URL must contain the exact conversation ID passed to the method.
      final (client, requests) = _capturingClient(200, {});
      await http.runWithClient(
        () => AIChatService.clearConversation('conv-xyz'),
        () => client,
      );
      expect(requests.single.url.path, contains('conv-xyz'));
    });

    test('hits the /deactivate endpoint', () async {
      final (client, requests) = _capturingClient(200, {});
      await http.runWithClient(
        () => AIChatService.clearConversation('conv-abc'),
        () => client,
      );
      expect(requests.single.url.path, endsWith('/deactivate'));
    });

    test('throws Exception on non-200 status code', () async {
      // The method rethrows so callers can display an error to the user.
      await expectLater(
        http.runWithClient(
          () => AIChatService.clearConversation('conv-abc'),
          () => _mockRaw(404, 'Not Found'),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('rethrows transport errors', () async {
      await expectLater(
        http.runWithClient(
          () => AIChatService.clearConversation('conv-abc'),
          () => _mockThrows(http.ClientException('Network error')),
        ),
        throwsA(isA<http.ClientException>()),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 6 — getConversationHistory()
  //
  // GET with query parameters.  On success returns the parsed response map.
  // On any error returns a safe default {"messages": []}.
  // ──────────────────────────────────────────────────────────────────────────
  group('getConversationHistory()', () {
    test('uses GET method', () async {
      final (client, requests) = _capturingClient(200, {'messages': []});
      await http.runWithClient(
        () => AIChatService.getConversationHistory(userId: '1'),
        () => client,
      );
      expect(requests.single.method, 'GET');
    });

    test('hits the /v1/api/ai-chat/history endpoint', () async {
      final (client, requests) = _capturingClient(200, {'messages': []});
      await http.runWithClient(
        () => AIChatService.getConversationHistory(userId: '1'),
        () => client,
      );
      expect(requests.single.url.path, '/v1/api/ai-chat/history');
    });

    test('returns the parsed response map on HTTP 200', () async {
      final result = await http.runWithClient(
        () => AIChatService.getConversationHistory(userId: '1'),
        () => _mockJson(200, {
          'messages': [
            {'id': 1, 'text': 'Hello'}
          ]
        }),
      );
      expect(result['messages'], hasLength(1));
    });

    test('query parameters include userId', () async {
      final (client, requests) = _capturingClient(200, {'messages': []});
      await http.runWithClient(
        () => AIChatService.getConversationHistory(userId: '42'),
        () => client,
      );
      expect(requests.single.url.queryParameters['userId'], '42');
    });

    test('query parameters include limit', () async {
      final (client, requests) = _capturingClient(200, {'messages': []});
      await http.runWithClient(
        () => AIChatService.getConversationHistory(userId: '1', limit: 25),
        () => client,
      );
      expect(requests.single.url.queryParameters['limit'], '25');
    });

    test('query parameters include conversationId when provided', () async {
      final (client, requests) = _capturingClient(200, {'messages': []});
      await http.runWithClient(
        () => AIChatService.getConversationHistory(
          userId: '1',
          conversationId: 'conv-abc',
        ),
        () => client,
      );
      expect(
        requests.single.url.queryParameters['conversationId'],
        'conv-abc',
      );
    });

    test('query parameters omit conversationId when not provided', () async {
      final (client, requests) = _capturingClient(200, {'messages': []});
      await http.runWithClient(
        () => AIChatService.getConversationHistory(userId: '1'),
        () => client,
      );
      expect(
        requests.single.url.queryParameters.containsKey('conversationId'),
        isFalse,
      );
    });

    test('returns {"messages":[]} on non-200 status', () async {
      // A failure must not surface as an exception; an empty list is safer.
      final result = await http.runWithClient(
        () => AIChatService.getConversationHistory(userId: '1'),
        () => _mockRaw(500, 'Server Error'),
      );
      expect(result, {'messages': []});
    });

    test('returns {"messages":[]} on transport exception', () async {
      final result = await http.runWithClient(
        () => AIChatService.getConversationHistory(userId: '1'),
        () => _mockThrows(http.ClientException('Timeout')),
      );
      expect(result, {'messages': []});
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 7 — startNewConversation()
  //
  // POST that creates a new conversation.  Returns the server-assigned
  // conversationId on success (200 or 201), or null on any failure.
  // ──────────────────────────────────────────────────────────────────────────
  group('startNewConversation()', () {
    test('uses POST method', () async {
      final (client, requests) =
          _capturingClient(200, {'conversationId': 'id'});
      await http.runWithClient(
        () => AIChatService.startNewConversation(userId: '1'),
        () => client,
      );
      expect(requests.single.method, 'POST');
    });

    test('hits the /v1/api/ai-chat/conversation/new endpoint', () async {
      final (client, requests) =
          _capturingClient(200, {'conversationId': 'id'});
      await http.runWithClient(
        () => AIChatService.startNewConversation(userId: '1'),
        () => client,
      );
      expect(requests.single.url.path, '/v1/api/ai-chat/conversation/new');
    });

    test('returns the conversationId on HTTP 200', () async {
      // The returned ID is used to link subsequent messages to this session.
      final id = await http.runWithClient(
        () => AIChatService.startNewConversation(userId: '1'),
        () => _mockJson(200, {'conversationId': 'new-conv-456'}),
      );
      expect(id, 'new-conv-456');
    });

    test('returns the conversationId on HTTP 201', () async {
      // Some backends return 201 Created for new resources.
      final id = await http.runWithClient(
        () => AIChatService.startNewConversation(userId: '1'),
        () => _mockJson(201, {'conversationId': 'new-conv-789'}),
      );
      expect(id, 'new-conv-789');
    });

    test('returns null on non-200/201 status', () async {
      final id = await http.runWithClient(
        () => AIChatService.startNewConversation(userId: '1'),
        () => _mockRaw(500, 'Server Error'),
      );
      expect(id, isNull);
    });

    test('returns null on transport exception', () async {
      final id = await http.runWithClient(
        () => AIChatService.startNewConversation(userId: '1'),
        () => _mockThrows(http.ClientException('Connection refused')),
      );
      expect(id, isNull);
    });

    test('request body includes userId', () async {
      final (client, requests) = _capturingClient(200, {'conversationId': 'x'});
      await http.runWithClient(
        () => AIChatService.startNewConversation(userId: '55'),
        () => client,
      );
      final body = jsonDecode(requests.single.body) as Map;
      expect(body['userId'], '55');
    });

    test('request body includes title when provided', () async {
      final (client, requests) = _capturingClient(200, {'conversationId': 'x'});
      await http.runWithClient(
        () => AIChatService.startNewConversation(
            userId: '1', title: 'My Session'),
        () => client,
      );
      final body = jsonDecode(requests.single.body) as Map;
      expect(body['title'], 'My Session');
    });

    test('request body omits title when not provided', () async {
      final (client, requests) = _capturingClient(200, {'conversationId': 'x'});
      await http.runWithClient(
        () => AIChatService.startNewConversation(userId: '1'),
        () => client,
      );
      final body = jsonDecode(requests.single.body) as Map;
      expect(body.containsKey('title'), isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 8 — getUserConversations()
  //
  // GET that fetches the user's conversation list from the backend.
  // Returns a typed List; falls back to an empty list on any error.
  // ──────────────────────────────────────────────────────────────────────────
  group('getUserConversations()', () {
    test('uses GET method', () async {
      final (client, requests) = _capturingClient(200, {'conversations': []});
      await http.runWithClient(
        () => AIChatService.getUserConversations(userId: '1'),
        () => client,
      );
      expect(requests.single.method, 'GET');
    });

    test('hits the /v1/api/ai-chat/conversations endpoint', () async {
      final (client, requests) = _capturingClient(200, {'conversations': []});
      await http.runWithClient(
        () => AIChatService.getUserConversations(userId: '1'),
        () => client,
      );
      expect(requests.single.url.path, '/v1/api/ai-chat/conversations');
    });

    test('returns the list from the conversations key on HTTP 200', () async {
      final result = await http.runWithClient(
        () => AIChatService.getUserConversations(userId: '1'),
        () => _mockJson(200, {
          'conversations': [
            {'id': 'c1', 'title': 'Session 1'},
            {'id': 'c2', 'title': 'Session 2'},
          ]
        }),
      );
      expect(result, hasLength(2));
      expect(result.first['title'], 'Session 1');
    });

    test('returns empty list when conversations key is absent', () async {
      // Defensive: missing key must not crash.
      final result = await http.runWithClient(
        () => AIChatService.getUserConversations(userId: '1'),
        () => _mockJson(200, {}),
      );
      expect(result, isEmpty);
    });

    test('query parameters include userId', () async {
      final (client, requests) = _capturingClient(200, {'conversations': []});
      await http.runWithClient(
        () => AIChatService.getUserConversations(userId: '77'),
        () => client,
      );
      expect(requests.single.url.queryParameters['userId'], '77');
    });

    test('query parameters include limit', () async {
      final (client, requests) = _capturingClient(200, {'conversations': []});
      await http.runWithClient(
        () => AIChatService.getUserConversations(userId: '1', limit: 5),
        () => client,
      );
      expect(requests.single.url.queryParameters['limit'], '5');
    });

    test('returns empty list on non-200 status', () async {
      final result = await http.runWithClient(
        () => AIChatService.getUserConversations(userId: '1'),
        () => _mockRaw(500, 'Server Error'),
      );
      expect(result, isEmpty);
    });

    test('returns empty list on transport exception', () async {
      final result = await http.runWithClient(
        () => AIChatService.getUserConversations(userId: '1'),
        () => _mockThrows(http.ClientException('Timeout')),
      );
      expect(result, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 9 — deleteConversation()
  //
  // DELETE request.  Returns true on HTTP 200, false on any other outcome.
  // ──────────────────────────────────────────────────────────────────────────
  group('deleteConversation()', () {
    test('uses DELETE method', () async {
      final (client, requests) = _capturingClient(200, {});
      await http.runWithClient(
        () => AIChatService.deleteConversation(conversationId: 'conv-abc'),
        () => client,
      );
      expect(requests.single.method, 'DELETE');
    });

    test('embeds conversationId in the URL path', () async {
      final (client, requests) = _capturingClient(200, {});
      await http.runWithClient(
        () => AIChatService.deleteConversation(conversationId: 'conv-xyz'),
        () => client,
      );
      expect(requests.single.url.path, contains('conv-xyz'));
    });

    test('hits /v1/api/ai-chat/conversation/{id} endpoint', () async {
      final (client, requests) = _capturingClient(200, {});
      await http.runWithClient(
        () => AIChatService.deleteConversation(conversationId: 'my-id'),
        () => client,
      );
      expect(requests.single.url.path, endsWith('/my-id'));
    });

    test('returns true on HTTP 200', () async {
      final result = await http.runWithClient(
        () => AIChatService.deleteConversation(conversationId: 'conv-abc'),
        () => _mockRaw(200, ''),
      );
      expect(result, isTrue);
    });

    test('returns false on HTTP 404', () async {
      // Deleting a non-existent conversation is a non-critical failure.
      final result = await http.runWithClient(
        () => AIChatService.deleteConversation(conversationId: 'conv-abc'),
        () => _mockRaw(404, 'Not Found'),
      );
      expect(result, isFalse);
    });

    test('returns false on HTTP 500', () async {
      final result = await http.runWithClient(
        () => AIChatService.deleteConversation(conversationId: 'conv-abc'),
        () => _mockRaw(500, 'Server Error'),
      );
      expect(result, isFalse);
    });

    test('returns false on transport exception', () async {
      final result = await http.runWithClient(
        () => AIChatService.deleteConversation(conversationId: 'conv-abc'),
        () => _mockThrows(http.ClientException('Connection refused')),
      );
      expect(result, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 10 — getRetentionPeriodDays()
  //
  // GET that fetches the chat retention configuration from the backend.
  // Returns the value from the response, or 30 (default) on any failure.
  // ──────────────────────────────────────────────────────────────────────────
  group('getRetentionPeriodDays()', () {
    test('uses GET method', () async {
      final (client, requests) = _capturingClient(200, {'retentionDays': 30});
      await http.runWithClient(
        () => AIChatService.getRetentionPeriodDays(),
        () => client,
      );
      expect(requests.single.method, 'GET');
    });

    test('hits the /v1/api/ai-chat/config/retention-period endpoint', () async {
      final (client, requests) = _capturingClient(200, {'retentionDays': 30});
      await http.runWithClient(
        () => AIChatService.getRetentionPeriodDays(),
        () => client,
      );
      expect(
        requests.single.url.path,
        '/v1/api/ai-chat/config/retention-period',
      );
    });

    test('returns the retentionDays value from the response on HTTP 200',
        () async {
      // Callers use this value to determine how long chat history is available.
      final days = await http.runWithClient(
        () => AIChatService.getRetentionPeriodDays(),
        () => _mockJson(200, {'retentionDays': 90}),
      );
      expect(days, 90);
    });

    test('returns default 30 when retentionDays is absent from response',
        () async {
      // Backend may not set this field; 30 days is a sensible default.
      final days = await http.runWithClient(
        () => AIChatService.getRetentionPeriodDays(),
        () => _mockJson(200, {}),
      );
      expect(days, 30);
    });

    test('returns default 30 on non-200 status', () async {
      // If the endpoint does not exist yet, fall back gracefully.
      final days = await http.runWithClient(
        () => AIChatService.getRetentionPeriodDays(),
        () => _mockRaw(404, 'Not Found'),
      );
      expect(days, 30);
    });

    test('returns default 30 on transport exception', () async {
      final days = await http.runWithClient(
        () => AIChatService.getRetentionPeriodDays(),
        () => _mockThrows(http.ClientException('Timeout')),
      );
      expect(days, 30);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 11 — analyzeFile(): error path
  //
  // analyzeFile() wraps all exceptions and returns a user-facing error string
  // rather than propagating them.  A non-existent file path is used here to
  // trigger the catch-all without requiring a real HTTP server.
  // ──────────────────────────────────────────────────────────────────────────
  group('analyzeFile() — error handling', () {
    test(
        'returns error string when file does not exist (no unhandled exception)',
        () async {
      // MultipartFile.fromPath throws a FileSystemException for missing files;
      // the service must catch this and return a fallback string.
      final result = await http.runWithClient(
        () => AIChatService.analyzeFile(
          filePath: '/nonexistent/path/to/file.pdf',
          userId: '1',
        ),
        () => _mockRaw(200, '{"response":"ok"}'),
      );
      // Any non-empty string is acceptable; what matters is no exception escapes.
      expect(result, isA<String>());
      expect(result, isNotEmpty);
    });
  });

  group('askRecords() — grounded contract', () {
    test('posts JWT-identity request without a userId', () async {
      final (client, requests) = _capturingClient(200, {
        'success': true,
        'deliveryStatus': 'NO_RECORDS',
        'citations': <Object>[],
        'message': 'No matching records',
      });

      await http.runWithClient(
        () => AIChatService.askRecords(
          query: 'What medication changed?',
          patientId: 42,
        ),
        () => client,
      );

      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(requests.single.url.path, '/api/ai/ask');
      expect(body['query'], 'What medication changed?');
      expect(body['patientId'], 42);
      expect(body.containsKey('userId'), isFalse);
    });

    test('models delivered answer, citations, and safety metadata', () async {
      final result = await http.runWithClient(
        () => AIChatService.askRecords(query: 'metformin', patientId: 42),
        () => _mockJson(200, {
          'success': true,
          'deliveryStatus': 'DELIVERED',
          'requestId': '8aa0d978-a8fc-48bc-ab02-1af24f32e903',
          'sessionId': 'fd43f38b-ac0e-4adf-af84-d25992ce7855',
          'answer': {'text': 'Metformin was started.'},
          'citations': [
            {
              'citationId': 'C1',
              'recordType': 'CALL_SUMMARY',
              'excerpt': 'Metformin was started.',
              'deepLink': null,
            }
          ],
          'disclaimer': {
            'text': 'Records-based information; not medical advice.',
            'aiNoticeRequired': true,
            'recordsBasedFraming': true,
            'locale': 'en-US',
          },
          'escalation': {
            'tier': 1,
            'reason': 'Tier1_auto_deliver',
            'requiresClinicianReview': false,
          },
          'confirmation': {
            'promptConfirmWithProvider': true,
            'message': 'Confirm important details with your care provider.',
          },
        }),
      );

      expect(result.deliveryStatus, AiAskDeliveryStatus.delivered);
      expect(result.answer, 'Metformin was started.');
      expect(result.citations.single.citationId, 'C1');
      expect(result.citations.single.deepLink, isNull);
      expect(result.disclaimer?.aiNoticeRequired, isTrue);
      expect(result.escalation?.tier, 1);
      expect(result.confirmation?.required, isTrue);
    });

    test('fails closed when DELIVERED omits mandatory safety metadata',
        () async {
      final result = await http.runWithClient(
        () => AIChatService.askRecords(query: 'metformin', patientId: 42),
        () => _mockJson(200, {
          'success': true,
          'deliveryStatus': 'DELIVERED',
          'answer': {'text': 'Metformin was started.'},
          'citations': [
            {
              'citationId': 'C1',
              'recordType': 'CALL_SUMMARY',
              'excerpt': 'Metformin was started.',
            }
          ],
        }),
      );

      expect(result.deliveryStatus, AiAskDeliveryStatus.withheld);
      expect(result.error?.code, 'INVALID_RESPONSE');
      expect(result.retryInput, 'metformin');
    });

    test('never accepts DELIVERED from a non-2xx response', () async {
      final result = await http.runWithClient(
        () => AIChatService.askRecords(query: 'metformin', patientId: 42),
        () => _mockJson(503, _validDeliveredAskResponse()),
      );

      expect(result.deliveryStatus, AiAskDeliveryStatus.withheld);
      expect(result.answer, isNull);
      expect(result.citations, isEmpty);
      expect(result.retryable, isTrue);
    });

    test('fails closed for Tier2 review-required DELIVERED payloads', () async {
      final body = _validDeliveredAskResponse();
      body['escalation'] = {
        'tier': 2,
        'reason': 'Tier2_clinical_review',
        'requiresClinicianReview': true,
      };
      body['held'] = true;
      body['heldItemId'] = '11111111-1111-1111-1111-111111111111';

      final result = await http.runWithClient(
        () => AIChatService.askRecords(query: 'metformin', patientId: 42),
        () => _mockJson(200, body),
      );

      expect(result.deliveryStatus, AiAskDeliveryStatus.withheld);
      expect(result.answer, isNull);
      expect(result.citations, isEmpty);
      expect(result.disclaimer, isNull);
      expect(result.error?.code, 'INVALID_RESPONSE');
    });

    test('parses HELD Tier-2 hold without exposing draft answer', () async {
      final result = await http.runWithClient(
        () => AIChatService.askRecords(query: 'metformin', patientId: 42),
        () => _mockJson(200, {
          'success': true,
          'deliveryStatus': 'HELD',
          'held': true,
          'requestId': '8aa0d978-a8fc-48bc-ab02-1af24f32e903',
          'sessionId': 'fd43f38b-ac0e-4adf-af84-d25992ce7855',
          'heldItemId': '11111111-1111-1111-1111-111111111111',
          'pollUrl':
              '/v1/api/ai/hitl/11111111-1111-1111-1111-111111111111/status',
          'answer': {'text': 'Draft must not appear'},
          'citations': [
            {
              'citationId': 'C1',
              'recordType': 'CALL_SUMMARY',
              'excerpt': 'Draft must not appear',
            }
          ],
          'message': "We're reviewing this before showing it to you.",
          'escalation': {
            'tier': 2,
            'reason': 'hitl_hold',
            'requiresClinicianReview': true,
          },
        }),
      );

      expect(result.success, isTrue);
      expect(result.deliveryStatus, AiAskDeliveryStatus.held);
      expect(result.heldItemId, '11111111-1111-1111-1111-111111111111');
      expect(
        result.pollUrl,
        '/v1/api/ai/hitl/11111111-1111-1111-1111-111111111111/status',
      );
      expect(
        result.message,
        "We're reviewing this before showing it to you.",
      );
      expect(result.answer, isNull);
      expect(result.citations, isEmpty);
      expect(result.disclaimer, isNull);
      expect(result.escalation, isNull);
    });

    test('fails closed when HELD omits heldItemId', () async {
      final result = await http.runWithClient(
        () => AIChatService.askRecords(query: 'metformin', patientId: 42),
        () => _mockJson(200, {
          'success': true,
          'deliveryStatus': 'HELD',
          'held': true,
          'message': "We're reviewing this before showing it to you.",
        }),
      );

      expect(result.deliveryStatus, AiAskDeliveryStatus.withheld);
      expect(result.answer, isNull);
      expect(result.error?.code, 'INVALID_RESPONSE');
    });

    test('pollHitlStatus models delivered answer and citations', () async {
      final (client, requests) = _capturingClient(200, {
        'heldItemId': '11111111-1111-1111-1111-111111111111',
        'status': 'DELIVERED',
        'deliveryStatus': 'DELIVERED',
        'message': null,
        'answer': 'Metformin was started after review.',
        'citations': [
          {
            'citationId': 'C1',
            'recordType': 'CALL_SUMMARY',
            'excerpt': 'Metformin was started.',
          }
        ],
        'disclaimer': {
          'text':
              'This answer is based on your stored health records and is not medical advice.',
          'aiNoticeRequired': true,
          'recordsBasedFraming': true,
          'locale': 'en-US',
        },
        'confirmation': {
          'promptConfirmWithProvider': true,
          'message':
              'Please confirm important details with your care provider before acting on this information.',
        },
      });

      final result = await http.runWithClient(
        () => AIChatService.pollHitlStatus(
          '11111111-1111-1111-1111-111111111111',
        ),
        () => client,
      );

      expect(requests.single.method, 'GET');
      expect(
        requests.single.url.path,
        '/v1/api/ai/hitl/11111111-1111-1111-1111-111111111111/status',
      );
      expect(result.status, 'DELIVERED');
      expect(result.deliveryStatus, 'DELIVERED');
      expect(result.answer, 'Metformin was started after review.');
      expect(result.citations.single.citationId, 'C1');
      expect(result.disclaimer?.aiNoticeRequired, isTrue);
      expect(result.confirmation?.required, isTrue);
    });

    test('pollHitlStatus fails closed when DELIVERED omits disclaimer',
        () async {
      await expectLater(
        http.runWithClient(
          () => AIChatService.pollHitlStatus(
            '11111111-1111-1111-1111-111111111111',
          ),
          () => _mockJson(200, {
            'heldItemId': '11111111-1111-1111-1111-111111111111',
            'status': 'DELIVERED',
            'deliveryStatus': 'DELIVERED',
            'answer': 'Released without safety framing',
            'citations': <Object>[],
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('pollHitlStatus keeps rejected content withheld', () async {
      final result = await http.runWithClient(
        () => AIChatService.pollHitlStatus(
          '11111111-1111-1111-1111-111111111111',
        ),
        () => _mockJson(200, {
          'heldItemId': '11111111-1111-1111-1111-111111111111',
          'status': 'REJECTED',
          'deliveryStatus': 'WITHHELD_PERMANENTLY',
          'message':
              'A reviewer could not release this answer. Please contact your care provider.',
          'answer': 'should not appear',
          'citations': [
            {
              'citationId': 'C1',
              'recordType': 'CALL_SUMMARY',
              'excerpt': 'should not appear',
            }
          ],
        }),
      );

      expect(result.status, 'REJECTED');
      expect(result.deliveryStatus, 'WITHHELD_PERMANENTLY');
      expect(
        result.message,
        'A reviewer could not release this answer. Please contact your care provider.',
      );
      expect(result.answer, isNull);
      expect(result.citations, isEmpty);
    });

    test('pollHitlStatus throws HitlPollHttpException on 403', () async {
      await expectLater(
        http.runWithClient(
          () => AIChatService.pollHitlStatus(
            '11111111-1111-1111-1111-111111111111',
          ),
          () => _mockJson(403, {
            'error': 'FORBIDDEN',
            'message': 'Not authorized to poll this held item',
          }),
        ),
        throwsA(
          isA<HitlPollHttpException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.isPermanent, 'isPermanent', isTrue),
        ),
      );
    });

    test('pollHitlStatus times out stalled status requests', () async {
      await expectLater(
        http.runWithClient(
          () => AIChatService.pollHitlStatus(
            '11111111-1111-1111-1111-111111111111',
            timeout: const Duration(milliseconds: 1),
          ),
          () => MockClient((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return http.Response('{}', 200);
          }),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('fails closed when DELIVERED identifiers are not UUIDs', () async {
      final body = _validDeliveredAskResponse();
      body['requestId'] = 'not-a-uuid';

      final result = await http.runWithClient(
        () => AIChatService.askRecords(query: 'metformin', patientId: 42),
        () => _mockJson(200, body),
      );

      expect(result.deliveryStatus, AiAskDeliveryStatus.withheld);
      expect(result.answer, isNull);
      expect(result.error?.code, 'INVALID_RESPONSE');
    });

    test('fails closed when optional metadata UUIDs are malformed', () async {
      final body = _validDeliveredAskResponse();
      body['conversationId'] = 'also-not-a-uuid';
      body['heldItemId'] = 'bad-held-id';

      final result = await http.runWithClient(
        () => AIChatService.askRecords(query: 'metformin', patientId: 42),
        () => _mockJson(200, body),
      );

      expect(result.deliveryStatus, AiAskDeliveryStatus.withheld);
      expect(result.answer, isNull);
      expect(result.citations, isEmpty);
      expect(result.error?.code, 'INVALID_RESPONSE');
    });

    test('fails closed when Tier1 still requires clinician review', () async {
      final body = _validDeliveredAskResponse();
      body['escalation'] = {
        'tier': 1,
        'reason': 'Tier1_auto_deliver',
        'requiresClinicianReview': true,
      };

      final result = await http.runWithClient(
        () => AIChatService.askRecords(query: 'metformin', patientId: 42),
        () => _mockJson(200, body),
      );

      expect(result.deliveryStatus, AiAskDeliveryStatus.withheld);
      expect(result.answer, isNull);
      expect(result.error?.code, 'INVALID_RESPONSE');
    });

    test('fails closed on unknown deliveryStatus', () async {
      final result = await http.runWithClient(
        () => AIChatService.askRecords(query: 'metformin', patientId: 42),
        () => _mockJson(200, {
          'success': true,
          'deliveryStatus': 'PARTIAL',
          'answer': {'text': 'Injected'},
          'citations': [
            {
              'citationId': 'C1',
              'recordType': 'CALL_SUMMARY',
              'excerpt': 'Injected',
            }
          ],
        }),
      );

      expect(result.deliveryStatus, AiAskDeliveryStatus.withheld);
      expect(result.answer, isNull);
      expect(result.citations, isEmpty);
      expect(result.error?.code, 'INVALID_RESPONSE');
    });

    test('marks 429 as retryable without exposing held content', () async {
      final result = await http.runWithClient(
        () => AIChatService.askRecords(query: 'retry me', patientId: 42),
        () => _mockJson(429, {
          'success': false,
          'deliveryStatus': 'WITHHELD',
          'answer': {'text': 'should not appear'},
          'citations': [
            {
              'citationId': 'C1',
              'recordType': 'CALL_SUMMARY',
              'excerpt': 'should not appear',
            }
          ],
          'error': {
            'code': 'RATE_LIMITED',
            'message': 'Too many requests',
          },
        }),
      );

      expect(result.retryable, isTrue);
      expect(result.retryInput, 'retry me');
      expect(result.answer, isNull);
      expect(result.citations, isEmpty);
    });

    test('cancels in-flight ask when abortTrigger completes', () async {
      final abort = Completer<void>();
      final started = Completer<void>();
      final resultFuture = http.runWithClient(
        () => AIChatService.askRecords(
          query: 'cancel me',
          patientId: 42,
          abortTrigger: abort.future,
        ),
        () => MockClient((request) async {
          started.complete();
          await Future<void>.delayed(const Duration(seconds: 5));
          return http.Response('{}', 200);
        }),
      );

      await started.future;
      abort.complete();
      final result = await resultFuture;
      expect(result.cancelled, isTrue);
      expect(result.error?.code, 'CANCELLED');
      expect(result.answer, isNull);
    });

    for (final invalidCitation in <Map<String, dynamic>>[
      {
        'citationId': ' ',
        'recordType': 'CALL_SUMMARY',
        'excerpt': 'Metformin was started.',
      },
      {
        'citationId': 'C1',
        'recordType': 'UNKNOWN',
        'excerpt': 'Metformin was started.',
      },
      {
        'citationId': 'C1',
        'recordType': 'CALL_SUMMARY',
        'excerpt': ' ',
      },
    ]) {
      test('fails closed on invalid delivered citation $invalidCitation',
          () async {
        final body = _validDeliveredAskResponse();
        body['citations'] = [invalidCitation];

        final result = await http.runWithClient(
          () => AIChatService.askRecords(query: 'metformin', patientId: 42),
          () => _mockJson(200, body),
        );

        expect(result.deliveryStatus, AiAskDeliveryStatus.withheld);
        expect(result.answer, isNull);
        expect(result.citations, isEmpty);
        expect(result.error?.code, 'INVALID_RESPONSE');
      });
    }

    for (final invalidCitations in <Object?>[
      null,
      {'citationId': 'C1'},
      [
        {
          'citationId': 'C1',
          'recordType': 'CALL_SUMMARY',
          'excerpt': 'Metformin was started.',
        },
        'not-a-citation',
      ],
      [
        {
          'citationId': 'C1',
          'recordType': 'CALL_SUMMARY',
          'excerpt': 'Metformin was started.',
        },
        {
          'citationId': 'C1',
          'recordType': 'MEDICATION',
          'excerpt': 'Metformin 500 mg.',
        },
      ],
      [
        {
          'citationId': 'C0',
          'recordType': 'CALL_SUMMARY',
          'excerpt': 'Metformin was started.',
        },
      ],
      [
        {
          'citationId': 'C01',
          'recordType': 'CALL_SUMMARY',
          'excerpt': 'Metformin was started.',
        },
      ],
      [
        {
          'citationId': 'c1',
          'recordType': 'CALL_SUMMARY',
          'excerpt': 'Metformin was started.',
        },
      ],
    ]) {
      test('rejects malformed delivered citations payload $invalidCitations',
          () async {
        final body = _validDeliveredAskResponse();
        if (invalidCitations == null) {
          body.remove('citations');
        } else {
          body['citations'] = invalidCitations;
        }

        final result = await http.runWithClient(
          () => AIChatService.askRecords(query: 'metformin', patientId: 42),
          () => _mockJson(200, body),
        );

        expect(result.deliveryStatus, AiAskDeliveryStatus.withheld);
        expect(result.answer, isNull);
        expect(result.citations, isEmpty);
        expect(result.error?.code, 'INVALID_RESPONSE');
      });
    }

    for (final status in const ['WITHHELD', 'NO_RECORDS']) {
      test('discards injected answer and citations for $status', () async {
        final result = await http.runWithClient(
          () => AIChatService.askRecords(query: 'metformin', patientId: 42),
          () => _mockJson(200, {
            'success': status == 'NO_RECORDS',
            'deliveryStatus': status,
            'answer': {'text': 'Injected answer'},
            'citations': [
              {
                'citationId': 'C1',
                'recordType': 'CALL_SUMMARY',
                'excerpt': 'Injected evidence',
              }
            ],
          }),
        );

        expect(result.answer, isNull);
        expect(result.citations, isEmpty);
      });
    }

    test('preserves supplied session, conversation, and bounded source types',
        () async {
      final (client, requests) = _capturingClient(200, {
        'success': true,
        'deliveryStatus': 'NO_RECORDS',
        'citations': <Object>[],
      });

      await http.runWithClient(
        () => AIChatService.askRecords(
          query: 'medication',
          patientId: 42,
          sessionId: '8aa0d978-a8fc-48bc-ab02-1af24f32e903',
          conversationId: 'fd43f38b-ac0e-4adf-af84-d25992ce7855',
          sourceTypes: const ['MEDICATION'],
        ),
        () => client,
      );

      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['sessionId'], '8aa0d978-a8fc-48bc-ab02-1af24f32e903');
      expect(body['conversationId'], 'fd43f38b-ac0e-4adf-af84-d25992ce7855');
      expect(body['sourceTypes'], ['MEDICATION']);
    });

    test('models correlated withheld errors even on non-200 status', () async {
      final result = await http.runWithClient(
        () => AIChatService.askRecords(query: 'metformin', patientId: 42),
        () => _mockJson(403, {
          'success': false,
          'requestId': '22222222-2222-2222-2222-222222222222',
          'deliveryStatus': 'WITHHELD',
          'citations': <Object>[],
          'error': {
            'code': 'FORBIDDEN_SCOPE',
            'message': 'Requested records are not available for Ask AI',
          },
        }),
      );

      expect(result.deliveryStatus, AiAskDeliveryStatus.withheld);
      expect(result.requestId, '22222222-2222-2222-2222-222222222222');
      expect(result.error?.code, 'FORBIDDEN_SCOPE');
    });

    test('fails closed on malformed payload', () async {
      final result = await http.runWithClient(
        () => AIChatService.askRecords(query: 'metformin', patientId: 42),
        () => _mockRaw(200, '<html>bad gateway</html>'),
      );

      expect(result.deliveryStatus, AiAskDeliveryStatus.withheld);
      expect(result.error?.code, 'INVALID_RESPONSE');
    });

    test('times out with the original input available for retry', () async {
      final result = await http.runWithClient(
        () => AIChatService.askRecords(
          query: 'retry this question',
          patientId: 42,
          timeout: const Duration(milliseconds: 1),
        ),
        () => MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return http.Response('{}', 200);
        }),
      );

      expect(result.error?.code, 'TIMEOUT');
      expect(result.retryInput, 'retry this question');
      expect(result.retryable, isTrue);
    });
  });
}

Map<String, dynamic> _validDeliveredAskResponse() => {
      'success': true,
      'deliveryStatus': 'DELIVERED',
      'requestId': '8aa0d978-a8fc-48bc-ab02-1af24f32e903',
      'sessionId': 'fd43f38b-ac0e-4adf-af84-d25992ce7855',
      'answer': {'text': 'Metformin was started.'},
      'citations': [
        {
          'citationId': 'C1',
          'recordType': 'CALL_SUMMARY',
          'excerpt': 'Metformin was started.',
        }
      ],
      'disclaimer': {
        'text': 'Records-based information; not medical advice.',
        'aiNoticeRequired': true,
        'recordsBasedFraming': true,
        'locale': 'en-US',
      },
      'escalation': {
        'tier': 1,
        'reason': 'Tier1_auto_deliver',
        'requiresClinicianReview': false,
      },
      'confirmation': {
        'promptConfirmWithProvider': true,
        'message': 'Confirm important details with your care provider.',
      },
    };
