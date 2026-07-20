import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import '../config/env_constant.dart';

class VoiceIntentResult {
  final String intent;
  final Map<String, String> entities;
  final double confidence;
  final String? destination;
  final String? displayLabel;
  final bool requiresConfirmation;
  final bool success;

  VoiceIntentResult({
    required this.intent,
    this.entities = const {},
    this.confidence = 0.0,
    this.destination,
    this.displayLabel,
    this.requiresConfirmation = false,
    this.success = false,
  });

  factory VoiceIntentResult.fromJson(Map<String, dynamic> json) {
    final rawEntities = json['entities'];
    final Map<String, String> entities = rawEntities is Map
        ? rawEntities.map((k, v) => MapEntry(k.toString(), v.toString()))
        : {};

    return VoiceIntentResult(
      intent: json['intent'] as String? ?? 'unknown',
      entities: entities,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      destination: json['destination'] as String?,
      displayLabel: json['displayLabel'] as String?,
      requiresConfirmation: json['requiresConfirmation'] as bool? ?? false,
      success: json['success'] as bool? ?? false,
    );
  }
}

class VoiceIntentService {
  static String get _baseUrl => '${getBackendBaseUrl()}/api/voice';

  /// Synchronous override for testing; resolves without microtask delay.
  @visibleForTesting
  static VoiceIntentResult? Function({
    required String utterance,
    String locale,
    String? screenId,
  })? testOverride;

  static Future<VoiceIntentResult?> extractIntent({
    required String utterance,
    String locale = 'en',
    String? screenId,
  }) {
    if (testOverride != null) {
      final result = testOverride!(utterance: utterance, locale: locale, screenId: screenId);
      return SynchronousFuture(result);
    }
    return _extractIntentImpl(utterance: utterance, locale: locale, screenId: screenId);
  }

  static Future<VoiceIntentResult?> _extractIntentImpl({
    required String utterance,
    String locale = 'en',
    String? screenId,
  }) async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();
      authHeaders['Content-Type'] = 'application/json';

      final body = jsonEncode({
        'utterance': utterance,
        'locale': locale,
        if (screenId != null) 'screenId': screenId,
      });

      final response = await http.post(
        Uri.parse('$_baseUrl/intent'),
        headers: authHeaders,
        body: body,
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final result = VoiceIntentResult.fromJson(json);
        if (result.success) return result;
        return null;
      }

      debugPrint('Voice intent HTTP ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('Voice intent service error: $e');
      return null;
    }
  }
}
