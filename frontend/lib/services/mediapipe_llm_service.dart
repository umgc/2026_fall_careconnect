import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'colibri_service.dart';

/// Service providing on-device / local LLM inference via Google MediaPipe & LiteRT-LM.
/// - On Android (ARM64): Executes in-process via native LlmInference MethodChannel.
/// - On macOS (Apple Silicon M1/M2/M3/M4 & Intel/AMD x86_64 Hackintosh), Windows 10+,
///   Debian/Ubuntu/Mint Linux, and iOS: Bridges to the local LiteRT-LM / Gemma-2B desktop runtime.
class MediaPipeLlmService {
  static final MediaPipeLlmService _instance = MediaPipeLlmService._internal();
  factory MediaPipeLlmService() => _instance;
  MediaPipeLlmService._internal();

  static const MethodChannel _channel = MethodChannel('care_connect/mediapipe_llm');

  bool _isInitialized = false;
  bool _usingDesktopBridge = false;
  bool get isInitialized => _isInitialized;

  /// Resolves the standard local model path on Windows 10+, macOS (M2 & Hackintosh), and Linux.
  String _defaultDesktopModelSuggestion() {
    if (kIsWeb) return 'http://127.0.0.1:8000/v1 (Web Edge Bridge)';
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'] ?? r'C:\Users\Public';
      return '$home\\Downloads\\gemma-2b.bin';
    }
    if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '/tmp';
      return '$home/Downloads/gemma-2b.bin';
    }
    return '/sdcard/Download/gemma-2b.bin';
  }

  /// Checks if a local `.bin` or `.litertlm` model file exists on Windows, macOS, or Linux.
  String? _findLocalDesktopModelFile() {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) return null;
    final home = Platform.isWindows
        ? (Platform.environment['USERPROFILE'] ?? '')
        : (Platform.environment['HOME'] ?? '');
    if (home.isEmpty) return null;
    final sep = Platform.pathSeparator;
    final candidates = [
      '$home${sep}Downloads${sep}gemma-2b.litertlm',
      '$home${sep}Downloads${sep}gemma-2b.bin',
      '$home${sep}Downloads${sep}gemma-2b-it-gpu-int4.bin',
      '$home${sep}Models${sep}gemma-2b.litertlm',
      '$home${sep}Models${sep}gemma-2b.bin',
    ];
    for (final path in candidates) {
      try {
        final f = File(path);
        if (f.existsSync() && f.lengthSync() > 0) {
          return f.path;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Checks if MediaPipe / LiteRT-LM inference is available on the current platform
  /// (Android ARM64 native, or Windows 10+ / macOS M2 & Hackintosh / Debian & Ubuntu Linux bridge).
  Future<Map<String, dynamic>> checkAvailability() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('isAvailable');
        if (res != null && (res['available'] as bool? ?? false)) {
          final initialized = res['isInitialized'] as bool? ?? false;
          _isInitialized = initialized;
          _usingDesktopBridge = false;
          return {
            'available': true,
            'isInitialized': initialized,
            'engine': 'android-mediapipe-jni',
            'modelPath': res['modelPath'] as String? ?? '',
            'suggestedPath': res['suggestedPath'] as String? ?? '/sdcard/Download/gemma-2b.bin',
          };
        }
      } catch (e) {
        debugPrint('MediaPipeLlmService Android native check failed, trying local edge bridge: $e');
      }
    }

    // Desktop / Cross-Platform Bridge for Windows 10+, macOS (Apple Silicon & Hackintosh x86_64),
    // Debian/Ubuntu Linux, iOS, Web, or Android x86_64 Emulator:
    try {
      final models = await ColibriService().checkHealth();
      final localModelFile = _findLocalDesktopModelFile();
      if (models.isNotEmpty || localModelFile != null) {
        _isInitialized = true;
        _usingDesktopBridge = true;
        return {
          'available': true,
          'isInitialized': true,
          'engine': 'google-litert-lm-desktop-bridge',
          'modelPath': localModelFile ?? ColibriService().getDefaultColibriUrl(),
          'suggestedPath': _defaultDesktopModelSuggestion(),
        };
      }
    } catch (e) {
      debugPrint('MediaPipeLlmService desktop bridge check failed: $e');
    }

    return {
      'available': false,
      'isInitialized': false,
      'suggestedPath': _defaultDesktopModelSuggestion(),
      'reason':
          'Start colibri_server.py (or place gemma-2b.bin / gemma-2b.litertlm in Downloads) to enable local Gemma-2B inference.',
    };
  }

  /// Initializes the on-device LiteRT/MediaPipe engine with the specified model file
  Future<bool> initialize({
    String? modelPath,
    int maxTokens = 256,
    int topK = 40,
    double temperature = 0.2,
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('initialize', {
          if (modelPath != null) 'modelPath': modelPath,
          'maxTokens': maxTokens,
          'topK': topK,
          'temperature': temperature,
        });
        if (res != null && (res['success'] as bool? ?? false)) {
          _isInitialized = true;
          _usingDesktopBridge = false;
          return true;
        }
      } catch (e) {
        debugPrint('MediaPipeLlmService Android native initialization failed: $e');
      }
    }

    final status = await checkAvailability();
    _isInitialized = status['available'] == true;
    return _isInitialized;
  }

  /// Generates a response directly on-device (Android GPU JNI or Desktop LiteRT-LM / Gemma-2B bridge)
  Future<Map<String, dynamic>> generateResponse(String prompt) async {
    if (!kIsWeb && Platform.isAndroid && !_usingDesktopBridge) {
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
      } catch (e) {
        debugPrint('MediaPipe Android JNI inference error, falling back to local edge bridge: $e');
      }
    }

    // Cross-platform execution for Windows 10+, macOS (M2 & Hackintosh), Debian/Ubuntu Linux, and iOS
    try {
      final edgeRes = await ColibriService().completeChat(
        prompt: prompt,
        model: 'gemma-2b-mediapipe',
        temperature: 0.2,
      );
      if (edgeRes['success'] == true) {
        return {
          'success': true,
          'content': edgeRes['content'] as String? ?? '',
          'model': edgeRes['model'] as String? ?? 'gemma-2b-mediapipe',
          'latencyMs': edgeRes['latencyMs'] as int? ?? 0,
        };
      }
      return {
        'success': false,
        'error': edgeRes['error'] ?? 'Desktop LiteRT-LM / Colibri bridge unavailable',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Local inference error: $e',
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
