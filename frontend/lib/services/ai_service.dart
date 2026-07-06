import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'ai_chat_service.dart';
import 'subscription_service.dart';

enum AIModel {
  deepseek,
  gpt4,
  claude;

  String get displayName {
    switch (this) {
      case AIModel.deepseek:
        return 'DeepSeek Coder';
      case AIModel.gpt4:
        return 'GPT-4 Turbo';
      case AIModel.claude:
        return 'Claude 3';
    }
  }

  String get modelName {
    switch (this) {
      case AIModel.deepseek:
        return 'deepseek-chat';
      case AIModel.gpt4:
        return 'gpt-4o-mini';
      case AIModel.claude:
        return 'claude-3-haiku';
    }
  }
}

class AIService {
  // Performance optimization: Cache for recent responses
  static final Map<String, String> _responseCache = {};
  static const int _maxCacheSize = 100;
  static const Duration _cacheTimeout = Duration(minutes: 10);
  static final Map<String, DateTime> _cacheTimestamps = {};

  // Connection pooling for better performance
  static final http.Client _httpClient = http.Client();

  static Future<String> askAI(
    String question, {
    String role = 'patient',
    AIModel model = AIModel.deepseek,
    String? healthDataContext,
    required int patientId,
    required int userId,
    BuildContext? context,
  }) async {
    // Check subscription access for caregivers
    if (context != null && role == 'caregiver') {
      final canUseAI = await SubscriptionService.canUseAIAssistant(context);
      if (!canUseAI) {
        // This will show the premium dialog
        await SubscriptionService.checkPremiumAccessWithDialog(
          context,
          'AI Health Assistant',
        );
        return 'AI Assistant requires a Premium subscription. Please upgrade to continue.';
      }
    }

    // Create cache key
    final cacheKey = _createCacheKey(question, role, model, healthDataContext);

    // Check cache first
    if (_responseCache.containsKey(cacheKey)) {
      final timestamp = _cacheTimestamps[cacheKey];
      if (timestamp != null &&
          DateTime.now().difference(timestamp) < _cacheTimeout) {
        return _responseCache[cacheKey]!;
      } else {
        // Remove expired cache entry
        _responseCache.remove(cacheKey);
        _cacheTimestamps.remove(cacheKey);
      }
    }

    try {
      // Use the corrected AIChatService for API requests
      String chatType = 'GENERAL_SUPPORT';
      if (role == 'analytics') {
        chatType = 'MEDICAL_CONSULTATION';
      } else if (role == 'caregiver') {
        chatType = 'MEDICAL_CONSULTATION';
      }

      // Create enhanced message with context
      String enhancedMessage = question;
      if (healthDataContext != null && healthDataContext.isNotEmpty) {
        enhancedMessage =
            '$healthDataContext\n\nBased on the above context, please answer: $question';
      }

      final response = await AIChatService.sendMessage(
        message: enhancedMessage,
        patientId: patientId,
        userId: userId,
        chatType: chatType,
        temperature: 0.7,
        maxTokens: 1000,
        includeVitals: role == 'analytics' || role == 'caregiver',
        includeMedications: role == 'analytics' || role == 'caregiver',
        includeNotes: role == 'analytics' || role == 'caregiver',
        includeMoodPainLogs: role == 'analytics',
        includeAllergies: role == 'analytics' || role == 'caregiver',
      );

      if (response['success'] != false && response['aiResponse'] != null) {
        final aiResponse = response['aiResponse'] as String;

        // Cache the response
        _cacheResponse(cacheKey, aiResponse);

        return aiResponse;
      } else {
        return response['aiResponse'] ??
            'Sorry, I encountered an error. Please try again later.';
      }
    } catch (e) {
      // Better error handling
      if (e.toString().contains('TimeoutException')) {
        return 'The request timed out. Please try again with a shorter message.';
      } else if (e.toString().contains('SocketException')) {
        return 'Network error. Please check your internet connection and try again.';
      } else {
        return 'Sorry, I encountered an error. Please try again later. ($e)';
      }
    }
  }

  // Helper method to create cache key
  static String _createCacheKey(
    String question,
    String role,
    AIModel model,
    String? healthDataContext,
  ) {
    final contextHash = healthDataContext?.hashCode ?? 0;
    return '${question.hashCode}_${role}_${model.modelName}_$contextHash';
  }

  // Helper method to cache responses
  static void _cacheResponse(String key, String response) {
    // Implement LRU cache by removing oldest entries when cache is full
    if (_responseCache.length >= _maxCacheSize) {
      final oldestKey = _cacheTimestamps.keys.first;
      _responseCache.remove(oldestKey);
      _cacheTimestamps.remove(oldestKey);
    }

    _responseCache[key] = response;
    _cacheTimestamps[key] = DateTime.now();
  }

  // Method to clear cache (useful for testing or memory management)
  static void clearCache() {
    _responseCache.clear();
    _cacheTimestamps.clear();
  }

  // Method to dispose of resources
  static void dispose() {
    _httpClient.close();
    clearCache();
  }

  // Legacy method for backward compatibility
  static Future<String> askHealthQuestion(
    String question, {
    required int patientId,
    required int userId,
  }) async {
    return askAI(
      question,
      role: 'patient',
      model: AIModel.deepseek,
      patientId: patientId,
      userId: userId,
    );
  }
}
