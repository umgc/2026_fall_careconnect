import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import '../config/env_constant.dart';

enum AiAskDeliveryStatus { delivered, noRecords, withheld }

class AiAskCitation {
  final String citationId;
  final String recordType;
  final String? title;
  final String excerpt;
  final String? deepLink;

  const AiAskCitation({
    required this.citationId,
    required this.recordType,
    required this.excerpt,
    this.title,
    this.deepLink,
  });

  factory AiAskCitation.fromJson(Map<String, dynamic> json) => AiAskCitation(
        citationId: json['citationId']?.toString() ?? '',
        recordType: json['recordType']?.toString() ?? 'UNKNOWN',
        title: json['title']?.toString(),
        excerpt: json['excerpt']?.toString() ?? '',
        deepLink: json['deepLink']?.toString(),
      );
}

class AiAskError {
  final String code;
  final String message;
  final List<String> details;

  const AiAskError(this.code, this.message, [this.details = const []]);

  factory AiAskError.fromJson(Map<String, dynamic> json) => AiAskError(
        json['code']?.toString() ?? 'UNKNOWN_ERROR',
        json['message']?.toString() ?? 'Ask AI could not complete the request.',
        (json['details'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList(growable: false),
      );
}

class AiAskResult {
  final bool success;
  final AiAskDeliveryStatus deliveryStatus;
  final String? requestId;
  final String? sessionId;
  final String? answer;
  final String? message;
  final List<AiAskCitation> citations;
  final AiAskError? error;

  const AiAskResult({
    required this.success,
    required this.deliveryStatus,
    this.requestId,
    this.sessionId,
    this.answer,
    this.message,
    this.citations = const [],
    this.error,
  });

  factory AiAskResult.fromJson(Map<String, dynamic> json) {
    final status = switch (json['deliveryStatus']?.toString()) {
      'DELIVERED' => AiAskDeliveryStatus.delivered,
      'NO_RECORDS' => AiAskDeliveryStatus.noRecords,
      _ => AiAskDeliveryStatus.withheld,
    };
    final answerJson = json['answer'];
    final errorJson = json['error'];
    return AiAskResult(
      success: json['success'] == true,
      deliveryStatus: status,
      requestId: json['requestId']?.toString(),
      sessionId: json['sessionId']?.toString(),
      answer: answerJson is Map<String, dynamic>
          ? answerJson['text']?.toString()
          : null,
      message: json['message']?.toString(),
      citations: (json['citations'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AiAskCitation.fromJson)
          .toList(growable: false),
      error: errorJson is Map<String, dynamic>
          ? AiAskError.fromJson(errorJson)
          : null,
    );
  }
}

/// Service for AI chat communication through Spring Boot backend
class AIChatService {
  static String get _baseUrl => '${getBackendBaseUrl()}/v1/api/ai-chat';

  /// Records-grounded Ask AI client. Identity is supplied only by the JWT.
  static Future<AiAskResult> askRecords({
    required String query,
    required int patientId,
    String? sessionId,
    String? conversationId,
    String locale = 'en-US',
  }) async {
    try {
      final headers = await ApiService.getAuthHeaders();
      headers['Content-Type'] = 'application/json';
      headers['Accept'] = 'application/json';
      final response = await http.post(
        Uri.parse('${getBackendBaseUrl()}/api/ai/ask'),
        headers: headers,
        body: jsonEncode({
          'query': query,
          'patientId': patientId,
          'inputModality': 'TEXT',
          'locale': locale,
          if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
          if (conversationId != null && conversationId.isNotEmpty)
            'conversationId': conversationId,
        }),
      );
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Ask AI response is not an object');
      }
      return AiAskResult.fromJson(decoded);
    } on FormatException {
      return const AiAskResult(
        success: false,
        deliveryStatus: AiAskDeliveryStatus.withheld,
        error: AiAskError(
          'INVALID_RESPONSE',
          'Ask AI returned an unexpected response. Please try again.',
        ),
      );
    } on http.ClientException {
      return const AiAskResult(
        success: false,
        deliveryStatus: AiAskDeliveryStatus.withheld,
        error: AiAskError(
          'NETWORK_ERROR',
          'Unable to connect to Ask AI. Please check your connection.',
        ),
      );
    } catch (_) {
      return const AiAskResult(
        success: false,
        deliveryStatus: AiAskDeliveryStatus.withheld,
        error: AiAskError(
          'REQUEST_FAILED',
          'Ask AI could not complete the request. Please try again.',
        ),
      );
    }
  }

  /// Send a chat message to the AI through the backend
  static Future<Map<String, dynamic>> sendMessage({
    required String message,
    int? patientId,
    required int userId,
    String? conversationId,
    String chatType = 'GENERAL_SUPPORT',
    String? title,
    String? preferredModel,
    double temperature = 0.7,
    int maxTokens = 1000,
    bool includeVitals = true,
    bool includeMedications = true,
    bool includeNotes = true,
    bool includeMoodPainLogs = true,
    bool includeAllergies = true,
    List<Map<String, dynamic>>? uploadedFiles,
  }) async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();
      authHeaders['Content-Type'] = 'application/json';
      authHeaders['Accept'] = '*/*';

      final requestBody = {
        'message': message,
        if (patientId != null) 'patientId': patientId,
        'userId': userId,
        if (conversationId != null) 'conversationId': conversationId,
        'chatType': chatType,
        if (title != null) 'title': title,
        if (preferredModel != null && preferredModel.trim().isNotEmpty)
          'preferredModel': preferredModel,
        'temperature': temperature,
        'maxTokens': maxTokens,
        'includeVitals': includeVitals,
        'includeMedications': includeMedications,
        'includeNotes': includeNotes,
        'includeMoodPainLogs': includeMoodPainLogs,
        'includeAllergies': includeAllergies,
        if (uploadedFiles != null && uploadedFiles.isNotEmpty)
          'uploadedFiles': uploadedFiles,
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/chat'),
        headers: authHeaders,
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        // Handle the response structure from our backend ChatResponse
        if (responseData['success'] == true) {
          return {
            'success': true,
            'aiResponse': responseData['aiResponse'],
            'conversationId': responseData['conversationId'],
            'modelUsed': responseData['modelUsed'],
            'processingTimeMs': responseData['processingTimeMs'],
          };
        } else {
          const safeMessage =
              'The AI service could not complete your request. Please try again.';
          return {
            'success': false,
            'errorMessage': safeMessage,
            'aiResponse': 'Sorry, I encountered an error. Please try again.',
          };
        }
      } else if (response.statusCode == 401) {
        return {
          'success': false,
          'error': 'Authentication failed. Please log in again.',
          'response':
              'Your session has expired. Please log in again to continue chatting.',
          'aiResponse':
              'Your session has expired. Please log in again to continue chatting.',
        };
      } else if (response.statusCode == 403) {
        return {
          'success': false,
          'error': 'Access denied.',
          'response': 'You don\'t have permission to access this chat feature.',
          'aiResponse':
              'You don\'t have permission to access this chat feature.',
        };
      } else if (response.statusCode == 429) {
        return {
          'success': false,
          'error': 'Rate limit exceeded.',
          'response':
              'You\'re sending messages too quickly. Please wait a moment and try again.',
          'aiResponse':
              'You\'re sending messages too quickly. Please wait a moment and try again.',
        };
      } else if (response.statusCode >= 500) {
        const unavailableMessage =
            'The AI service is temporarily unavailable. Please try again in a few minutes.';
        if (kDebugMode) {
          debugPrint('AI chat request failed with HTTP ${response.statusCode}');
        }
        return {
          'success': false,
          'error': 'Server error: ${response.statusCode}',
          'errorMessage': unavailableMessage,
          'response': unavailableMessage,
          'aiResponse': unavailableMessage,
        };
      } else {
        const safeMessage =
            'The AI request could not be completed. Please check your input and try again.';
        if (kDebugMode) {
          debugPrint(
              'AI chat request rejected with HTTP ${response.statusCode}');
        }
        return {
          'success': false,
          'error': 'Unexpected error: ${response.statusCode}',
          'errorMessage': safeMessage,
          'response': safeMessage,
          'aiResponse': safeMessage,
        };
      }
    } on http.ClientException {
      return {
        'success': false,
        'error': 'Network error',
        'response':
            'Unable to connect to the AI service. Please check your internet connection and try again.',
        'aiResponse':
            'Unable to connect to the AI service. Please check your internet connection and try again.',
      };
    } on FormatException {
      return {
        'success': false,
        'error': 'Invalid response format',
        'response':
            'Received an unexpected response from the server. Please try again.',
        'aiResponse':
            'Received an unexpected response from the server. Please try again.',
      };
    } catch (_) {
      return {
        'success': false,
        'error': 'Failed to send message',
        'response': 'Sorry, I encountered an error. Please try again later.',
        'aiResponse': 'Sorry, I encountered an error. Please try again later.',
      };
    }
  }

  /// Clear a conversation from the backend
  static Future<void> clearConversation(String conversationId) async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();

      final response = await http.post(
        Uri.parse('$_baseUrl/conversation/$conversationId/deactivate'),
        headers: authHeaders,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to clear conversation: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get conversation history
  static Future<Map<String, dynamic>> getConversationHistory({
    required String userId,
    String? conversationId,
    int limit = 50,
  }) async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();

      final params = {
        'userId': userId,
        if (conversationId != null) 'conversationId': conversationId,
        'limit': limit.toString(),
        'timestamp':
            DateTime.now().millisecondsSinceEpoch.toString(), // Prevent caching
      };

      final uri = Uri.parse(
        '$_baseUrl/history',
      ).replace(queryParameters: params);

      final response = await http.get(uri, headers: authHeaders);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Map<String, dynamic>.from(data);
      } else {
        throw Exception(
          'Failed to get conversation history: ${response.statusCode}',
        );
      }
    } catch (e) {
      return {'messages': []};
    }
  }

  /// Start a new conversation
  static Future<String?> startNewConversation({
    required String userId,
    String? title,
  }) async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();

      final requestBody = {'userId': userId, if (title != null) 'title': title};

      final response = await http.post(
        Uri.parse('$_baseUrl/conversation/new'),
        headers: authHeaders,
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['conversationId'];
      } else {
        throw Exception(
          'Failed to start new conversation: ${response.statusCode}',
        );
      }
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Unable to start AI conversation');
      }
      return null;
    }
  }

  /// Get user conversations list
  static Future<List<Map<String, dynamic>>> getUserConversations({
    required String userId,
    int limit = 20,
  }) async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();

      final params = {'userId': userId, 'limit': limit.toString()};

      final uri = Uri.parse(
        '$_baseUrl/conversations',
      ).replace(queryParameters: params);

      final response = await http.get(uri, headers: authHeaders);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['conversations'] ?? []);
      } else {
        throw Exception('Failed to get conversations: ${response.statusCode}');
      }
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Unable to load AI conversations');
      }
      return [];
    }
  }

  /// Delete a conversation
  static Future<bool> deleteConversation({
    required String conversationId,
  }) async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();

      final response = await http.delete(
        Uri.parse('$_baseUrl/conversation/$conversationId'),
        headers: authHeaders,
      );

      return response.statusCode == 200;
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Unable to delete AI conversation');
      }
      return false;
    }
  }

  /// Send file for AI analysis
  static Future<String> analyzeFile({
    required String filePath,
    required String userId,
    String? question,
    String? conversationId,
  }) async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/analyze-file'),
      );

      // Add headers
      request.headers.addAll(authHeaders);

      // Add file
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      // Add form fields
      request.fields['userId'] = userId;
      if (question != null) request.fields['question'] = question;
      if (conversationId != null) {
        request.fields['conversationId'] = conversationId;
      }

      if (kDebugMode) {
        debugPrint('Uploading file for AI analysis');
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (kDebugMode) {
        debugPrint('File analysis response status: ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['response'] ?? 'File analyzed successfully';
      } else {
        throw Exception('Failed to analyze file: ${response.statusCode}');
      }
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Unable to analyze file');
      }
      return 'Sorry, I encountered an error analyzing the file. Please try again later.';
    }
  }

  /// Get chat retention period in days
  static Future<int> getRetentionPeriodDays() async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();

      final response = await http.get(
        Uri.parse('$_baseUrl/config/retention-period'),
        headers: authHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['retentionDays'] ?? 30;
      } else {
        // Fallback to default if endpoint doesn't exist yet
        return 30;
      }
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Unable to fetch AI chat retention period');
      }
      // Return default retention period
      return 30;
    }
  }
}
