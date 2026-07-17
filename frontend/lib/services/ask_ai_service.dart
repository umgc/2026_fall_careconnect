import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_token_manager.dart';
import '../config/env_constant.dart';

/// Thrown when the Ask AI request fails. [message] is safe to show directly
/// to the user.
class AskAiException implements Exception {
  final String message;
  AskAiException(this.message);

  @override
  String toString() => message;
}

/// A records-grounded answer from the Ask AI retrieval endpoint
/// (`POST /v1/api/ai/ask/{patientId}`).
///
/// [chunksUsed] is the number of indexed record chunks the answer was
/// grounded in; 0 means no matching records were found and [answer] will
/// be a "no records" message rather than a general answer (FR-AI-1).
class AskAiResult {
  final String answer;
  final int chunksUsed;

  const AskAiResult({required this.answer, required this.chunksUsed});

  factory AskAiResult.fromJson(Map<String, dynamic> json) {
    return AskAiResult(
      answer: json['answer'] as String? ?? '',
      chunksUsed: (json['chunksUsed'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Client for the AI-Assisted Retrieval (Ask AI) endpoint (SRS §3 / FR-AI-1).
class AskAiService {
  static String get _baseUrl => '${getBackendBaseUrl()}/v1/api/ai/ask';

  /// Submits [question] scoped to [patientId] and returns a grounded,
  /// cited answer. Never falls back to the model's general knowledge —
  /// the backend only answers from the caller's authorized records.
  static Future<AskAiResult> ask({
    required int patientId,
    required String question,
  }) async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/json';

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$_baseUrl/$patientId'),
            headers: headers,
            body: jsonEncode({'question': question}),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw AskAiException(
        'Could not reach the AI service. Check your connection and try again.',
      );
    }

    switch (response.statusCode) {
      case 200:
        return AskAiResult.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      case 401:
        throw AskAiException('Please log in again to use Ask AI.');
      case 403:
        throw AskAiException(
          "You aren't authorized to ask about this patient's records.",
        );
      case 503:
        throw AskAiException(
          'The AI service is temporarily unavailable. Please try again shortly.',
        );
      default:
        throw AskAiException('Something went wrong. Please try again.');
    }
  }
}
