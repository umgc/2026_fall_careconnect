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

/// A single source citation backing a grounded answer (FR-AI-2).
class AskAiCitation {
  final String citationId;
  final String? recordType;
  final String? title;
  final String? excerpt;
  final String? deepLink;

  const AskAiCitation({
    required this.citationId,
    this.recordType,
    this.title,
    this.excerpt,
    this.deepLink,
  });

  factory AskAiCitation.fromJson(Map<String, dynamic> json) {
    return AskAiCitation(
      citationId: json['citationId'] as String? ?? '',
      recordType: json['recordType'] as String?,
      title: json['title'] as String?,
      excerpt: json['excerpt'] as String?,
      deepLink: json['deepLink'] as String?,
    );
  }
}

/// A records-grounded answer from the Ask AI gateway
/// (`POST /v1/api/ai/ask`, Task 5.3).
///
/// [deliveryStatus] is one of DELIVERED, HELD (Tier 2 human review pending),
/// WITHHELD (denied — see [message]), or NO_RECORDS. [answerText] is only
/// populated for DELIVERED. Always check [deliveryStatus] before assuming
/// there's an answer to show.
class AskAiResult {
  final bool success;
  final String deliveryStatus;
  final bool held;
  final String? answerText;
  final List<AskAiCitation> citations;
  final String? disclaimerText;
  final String? message;

  const AskAiResult({
    required this.success,
    required this.deliveryStatus,
    required this.held,
    required this.citations,
    this.answerText,
    this.disclaimerText,
    this.message,
  });

  factory AskAiResult.fromJson(Map<String, dynamic> json) {
    final answer = json['answer'] as Map<String, dynamic>?;
    final disclaimer = json['disclaimer'] as Map<String, dynamic>?;
    final citationsJson = json['citations'] as List<dynamic>? ?? [];
    return AskAiResult(
      success: json['success'] as bool? ?? false,
      deliveryStatus: json['deliveryStatus'] as String? ?? 'WITHHELD',
      held: json['held'] as bool? ?? false,
      answerText: answer?['text'] as String?,
      citations: citationsJson
          .map((c) => AskAiCitation.fromJson(c as Map<String, dynamic>))
          .toList(),
      disclaimerText: disclaimer?['text'] as String?,
      message: json['message'] as String?,
    );
  }
}

/// Client for the AI-Assisted Retrieval (Ask AI) gateway (SRS §3 / FR-AI-1).
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
            Uri.parse(_baseUrl),
            headers: headers,
            body: jsonEncode({'query': question, 'patientId': patientId}),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw AskAiException(
        'Could not reach the AI service. Check your connection and try again.',
      );
    }

    Map<String, dynamic>? body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      body = null;
    }

    if (response.statusCode == 200 && body != null) {
      return AskAiResult.fromJson(body);
    }

    // Even error responses return a structured body (message / error.message)
    // per the gateway's shared error contract — prefer that over a generic
    // per-status message when present.
    final structuredMessage = body?['message'] as String? ??
        (body?['error'] as Map<String, dynamic>?)?['message'] as String?;
    if (structuredMessage != null && structuredMessage.isNotEmpty) {
      throw AskAiException(structuredMessage);
    }

    switch (response.statusCode) {
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
