import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'colibri_service.dart';

/// Service providing on-device LLM inference on Android via Google MediaPipe / LiteRT.
/// Interacts with native Android LlmInference via MethodChannel.
class MediaPipeLlmService {
  static final MediaPipeLlmService _instance = MediaPipeLlmService._internal();
  factory MediaPipeLlmService() => _instance;
  MediaPipeLlmService._internal();

  static const MethodChannel _channel = MethodChannel('care_connect/mediapipe_llm');

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Checks if MediaPipe LLM inference is available on the current platform and if a model exists.
  Future<Map<String, dynamic>> checkAvailability() async {
    if (kIsWeb || !Platform.isAndroid) {
      return {
        'available': false,
        'reason': 'MediaPipe on-device LLM is only supported on Android',
      };
    }

    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('isAvailable');
      if (res != null) {
        final available = res['available'] as bool? ?? false;
        final initialized = res['isInitialized'] as bool? ?? false;
        _isInitialized = initialized;
        return {
          'available': available,
          'isInitialized': initialized,
          'modelPath': res['modelPath'] as String? ?? '',
          'suggestedPath': res['suggestedPath'] as String? ?? '',
        };
      }
      return {'available': false, 'reason': 'Null response from native engine'};
    } catch (e) {
      debugPrint('MediaPipeLlmService checkAvailability failed: $e');
      return {'available': false, 'reason': e.toString()};
    }
  }

  /// Initializes the on-device LiteRT/MediaPipe engine with the specified model file
  Future<bool> initialize({
    String? modelPath,
    int maxTokens = 256,
    int topK = 40,
    double temperature = 0.2,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return false;

    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('initialize', {
        if (modelPath != null) 'modelPath': modelPath,
        'maxTokens': maxTokens,
        'topK': topK,
        'temperature': temperature,
      });
      _isInitialized = res != null && (res['success'] as bool? ?? false);
      return _isInitialized;
    } catch (e) {
      debugPrint('MediaPipeLlmService initialization failed: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// Generates a response directly on-device using the mobile GPU
  Future<Map<String, dynamic>> generateResponse(String prompt) async {
    if (kIsWeb || !Platform.isAndroid) {
      return {
        'success': false,
        'error': 'MediaPipe on-device LLM only supported on Android',
      };
    }

    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('generate', {
        'prompt': prompt,
      });

      if (res != null && (res['success'] as bool? ?? false)) {
        return {
          'success': true,
          'content': res['content'] as String? ?? '',
          'model': res['model'] as String? ?? 'gemma-2b-mediapipe',
          'latencyMs': res['latencyMs'] as int? ?? 0,
        };
      }

      return {
        'success': false,
        'error': 'Inference failed on native Android engine',
      };
    } catch (e) {
      debugPrint('MediaPipe on-device inference error: $e');
      return {
        'success': false,
        'error': 'Inference error: $e',
      };
    }
  }

  /// Clinical voice / query triage helper with local patient grounding
  Future<Map<String, dynamic>> queryLocalClinicalAssistant({
    required String question,
    Map<String, dynamic>? localPatientData,
  }) async {
    // 1. Unified safety triage: Check if question involves dosage alteration, symptoms, or multi-campus directory
    if (ColibriService.shouldEscalateToCloud(question)) {
      return {
        'success': true,
        'content': '${ColibriService.escalateToken} This inquiry involves medication dosage changes, symptoms, or multi-campus facility information.',
        'model': 'gemma-2b-mediapipe',
        'escalateToCloud': true,
      };
    }

    // 2. Assemble concise context block for mobile model
    String contextBlock = '';
    if (localPatientData != null && localPatientData.isNotEmpty) {
      contextBlock = 'Patient Data: ${jsonEncode(localPatientData)}\n';
    }

    final prompt =
        'You are CareConnect Edge Assistant. Answer routine questions concisely in 1 to 2 sentences using patient data.\n'
        '$contextBlock'
        'Question: $question\n'
        'Answer:';

    final result = await generateResponse(prompt);
    if (result['success'] == true) {
      final content = (result['content'] as String? ?? '').trim();
      final bool escalated = content.contains(ColibriService.escalateToken);
      return {
        'success': true,
        'content': content,
        'model': result['model'] ?? 'gemma-2b-mediapipe',
        'latencyMs': result['latencyMs'] ?? 0,
        'escalateToCloud': escalated,
      };
    }

    return result;
  }
}
