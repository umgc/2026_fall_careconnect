import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

/// Service providing local MoE inference via the Colibri engine.
/// Connects to Colibri's OpenAI-compatible API gateway (typically at localhost:8000/v1).
/// Implements Tiered Hybrid Edge-Cloud AI Triage for clinical medication safety.
class ColibriService {
  static final ColibriService _instance = ColibriService._internal();
  factory ColibriService() => _instance;
  ColibriService._internal();

  static const String escalateToken = '[ESCALATE_TO_CLINICAL_CLOUD]';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 120),
  ));

  /// Evaluates whether a query must be escalated to the Cloud AI (Claude/Bedrock)
  /// due to clinical medication safety, symptoms, or multi-campus directory searches.
  static bool shouldEscalateToCloud(String message) {
    if (message.trim().isEmpty) return false;
    final lower = message.toLowerCase();

    // 1. Pharmacological / dosage alterations (e.g. cut pill in half, change dose)
    final dosageRegex = RegExp(
      r'\b(cut|split|break|halve|half|increase|decrease|double|stop|skip|adjust|change)\b.*\b(dosage|dose|pill|pills|tablet|tablets|medication|medicine|capsule)\b',
      caseSensitive: false,
    );
    if (dosageRegex.hasMatch(lower)) return true;

    if (lower.contains('in half') || lower.contains('half of')) {
      final halfAction = RegExp(r'\b(cut|split|halve|take|break|divide)\b', caseSensitive: false);
      if (halfAction.hasMatch(lower)) return true;
    }

    // 2. Clinical symptoms, medical diagnosis, drug interactions
    final clinicalRegex = RegExp(
      r'\b(chest pain|shortness of breath|diagnos|symptoms?|severe rash|bleeding|emergency|drug interactions?|side effects?|allergy reaction)\b',
      caseSensitive: false,
    );
    if (clinicalRegex.hasMatch(lower)) return true;

    // 3. Multi-campus / external clinic directory inquiries
    final directoryRegex = RegExp(
      r'\b(other|another|different|second|main|downtown)\b\s+(office|clinic|branch|location|facility|building|campus)\b',
      caseSensitive: false,
    );
    if (directoryRegex.hasMatch(lower)) return true;

    return false;
  }

  String? _resolvedBaseUrl;

  /// Resolves the default Colibri base URL depending on platform
  String getDefaultColibriUrl() {
    if (_resolvedBaseUrl != null) return _resolvedBaseUrl!;
    if (kIsWeb) return 'http://127.0.0.1:8000/v1';
    if (!kIsWeb && Platform.isAndroid) {
      // Android Emulator loopback to host PC
      return 'http://10.0.2.2:8000/v1';
    }
    // Windows, macOS, Linux, or iOS Simulator
    return 'http://127.0.0.1:8000/v1';
  }

  /// Checks if the Colibri server is active and returns available models
  Future<List<String>> checkHealth({String? customBaseUrl}) async {
    final candidateUrls = customBaseUrl != null
        ? [customBaseUrl]
        : (!kIsWeb && Platform.isAndroid
            ? ['http://10.0.2.2:8000/v1', 'http://127.0.0.1:8000/v1']
            : [getDefaultColibriUrl()]);

    for (final baseUrl in candidateUrls) {
      try {
        final response = await _dio.get(
          '$baseUrl/models',
          options: Options(receiveTimeout: const Duration(seconds: 3)),
        );
        if (response.statusCode == 200 && response.data != null) {
          final data = response.data;
          if (data is Map && data.containsKey('data')) {
            final models = data['data'] as List<dynamic>? ?? [];
            _resolvedBaseUrl = baseUrl;
            return models.map((m) => m['id'].toString()).toList();
          }
        }
      } catch (e) {
        debugPrint('Colibri health check failed at $baseUrl: $e');
      }
    }
    return [];
  }

  /// Sends a chat completion request to Colibri
  Future<Map<String, dynamic>> completeChat({
    required String prompt,
    String model = 'olmoe-colibri',
    String? customBaseUrl,
    String? systemPrompt,
    double temperature = 0.3,
  }) async {
    final baseUrl = customBaseUrl ?? getDefaultColibriUrl();
    final system = systemPrompt ??
        'You are CareConnect Edge Assistant. Answer routine questions using the provided patient data concisely in 1 to 2 sentences.';

    final stopwatch = Stopwatch()..start();

    try {
      final response = await _dio.post(
        '$baseUrl/chat/completions',
        data: {
          'model': model,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': prompt},
          ],
          'temperature': temperature,
          'max_tokens': 512,
          'stream': false,
        },
        options: Options(headers: {'Content-Type': 'application/json'}),
      );

      stopwatch.stop();

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        String content = '';
        if (data['choices'] != null && (data['choices'] as List).isNotEmpty) {
          content = data['choices'][0]['message']?['content'] ?? '';
        }

        final usage = data['usage'] ?? {};
        final totalTokens = usage['total_tokens'] ?? 0;
        final latencyMs = stopwatch.elapsedMilliseconds;
        final tokPerSec = latencyMs > 0 && totalTokens > 0
            ? (totalTokens / (latencyMs / 1000.0)).toStringAsFixed(1)
            : '0.0';

        final bool escalated = content.contains(escalateToken);

        return {
          'success': true,
          'content': content,
          'model': model,
          'latencyMs': latencyMs,
          'totalTokens': totalTokens,
          'tokensPerSec': tokPerSec,
          'escalateToCloud': escalated,
        };
      }

      return {
        'success': false,
        'error': 'Colibri returned HTTP ${response.statusCode}',
        'escalateToCloud': false,
      };
    } catch (e) {
      stopwatch.stop();
      return {
        'success': false,
        'error': 'Colibri connection error: $e',
        'escalateToCloud': false,
      };
    }
  }

  /// Clinical voice / query triage helper with local patient grounding
  Future<Map<String, dynamic>> queryLocalClinicalAssistant({
    required String question,
    Map<String, dynamic>? localPatientData,
    String model = 'olmoe-colibri',
  }) async {
    // If the question explicitly requires cloud clinical reasoning or directory, escalate immediately
    if (shouldEscalateToCloud(question)) {
      return {
        'success': true,
        'content': '$escalateToken This inquiry involves medication dosage changes, symptoms, or multi-campus facility information.',
        'model': model,
        'escalateToCloud': true,
      };
    }

    String contextBlock = '';
    if (localPatientData != null && localPatientData.isNotEmpty) {
      contextBlock = '\n[LOCAL PATIENT CONTEXT]\n${jsonEncode(localPatientData)}\n';
    }

    final systemPrompt =
        'You are CareConnect Edge Assistant. Answer routine questions using the provided patient data concisely in 1 to 2 sentences.'
        '$contextBlock';

    return completeChat(
      prompt: question,
      model: model,
      systemPrompt: systemPrompt,
      temperature: 0.2,
    );
  }
}
