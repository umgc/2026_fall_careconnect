import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import '../config/env_constant.dart';

/// Service for AI chat communication through Spring Boot backend
class AIChatService {
  static String get _baseUrl => '${getBackendBaseUrl()}/v1/api/ai-chat';

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
          return {
            'success': false,
            'errorMessage': responseData['errorMessage'] ?? responseData['error'] ?? 'Unknown error',
            'aiResponse': 'Sorry, I encountered an error. Please try again.',
          };
        }
      } else if (response.statusCode == 401) {
        return {
          'success': false,
          'error': 'Authentication failed. Please log in again.',
          'response': 'Your session has expired. Please log in again to continue chatting.',
          'aiResponse': 'Your session has expired. Please log in again to continue chatting.',
        };
      } else if (response.statusCode == 403) {
        return {
          'success': false,
          'error': 'Access denied.',
          'response': 'You don\'t have permission to access this chat feature.',
          'aiResponse': 'You don\'t have permission to access this chat feature.',
        };
      } else if (response.statusCode == 429) {
        return {
          'success': false,
          'error': 'Rate limit exceeded.',
          'response': 'You\'re sending messages too quickly. Please wait a moment and try again.',
          'aiResponse': 'You\'re sending messages too quickly. Please wait a moment and try again.',
        };
      } else if (response.statusCode >= 500) {
        final serverError = _extractServerErrorMessage(response.body);
        final unavailableMessage = kDebugMode
            ? 'The AI service is temporarily unavailable at $_baseUrl. Please verify BACKEND_URL and try again.'
            : 'The AI service is temporarily unavailable. Please try again in a few minutes.';
        return {
          'success': false,
          'error': 'Server error: ${response.statusCode}',
          'errorMessage': serverError,
          'response': serverError ?? unavailableMessage,
          'aiResponse': serverError ?? unavailableMessage,
        };
      } else {
        final serverError = _extractServerErrorMessage(response.body);
        return {
          'success': false,
          'error': 'Unexpected error: ${response.statusCode}',
          'errorMessage': serverError,
          'response': serverError ?? 'An unexpected error occurred. Please try again.',
          'aiResponse': serverError ?? 'An unexpected error occurred. Please try again.',
        };
      }
    } on http.ClientException catch (e) {
      return {
        'success': false,
        'error': 'Network error: $e',
        'response': 'Unable to connect to the AI service. Please check your internet connection and try again.',
        'aiResponse': 'Unable to connect to the AI service. Please check your internet connection and try again.',
      };
    } on FormatException catch (e) {
      return {
        'success': false,
        'error': 'Invalid response format: $e',
        'response': 'Received an unexpected response from the server. Please try again.',
        'aiResponse': 'Received an unexpected response from the server. Please try again.',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to send message: $e',
        'response': 'Sorry, I encountered an error. Please try again later.',
        'aiResponse': 'Sorry, I encountered an error. Please try again later.',
      };
    }
  }

  static String? _extractServerErrorMessage(String responseBody) {
    try {
      final parsed = jsonDecode(responseBody);
      if (parsed is Map<String, dynamic>) {
        final fromErrorMessage = parsed['errorMessage'];
        if (fromErrorMessage is String && fromErrorMessage.trim().isNotEmpty) {
          return fromErrorMessage;
        }
        final fromError = parsed['error'];
        if (fromError is String && fromError.trim().isNotEmpty) {
          return fromError;
        }
        final fromMessage = parsed['message'];
        if (fromMessage is String && fromMessage.trim().isNotEmpty) {
          return fromMessage;
        }
      }
    } catch (_) {
      // Ignore non-JSON error bodies.
    }
    return null;
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
        'timestamp': DateTime.now().millisecondsSinceEpoch.toString(), // Prevent caching
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
    } catch (e) {
      print('❌ Error starting new conversation: $e');
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
    } catch (e) {
      print('❌ Error getting conversations: $e');
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
    } catch (e) {
      print('❌ Error deleting conversation: $e');
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

      print('🤖 Uploading file for AI analysis: $filePath');

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('🤖 File analysis response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['response'] ?? 'File analyzed successfully';
      } else {
        throw Exception('Failed to analyze file: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error analyzing file: $e');
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
    } catch (e) {
      print('⚠️ Warning: Could not fetch retention period from backend: $e');
      // Return default retention period
      return 30;
    }
  }
}
