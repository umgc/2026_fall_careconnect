import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'colibri_service.dart';

/// Service providing on-device / local LLM inference via Google MediaPipe & LiteRT-LM.
/// - On Android (ARM64): Executes in-process via native LlmInference MethodChannel.
/// - On macOS (Apple Silicon M1/M2/M3/M4 & Intel/AMD x86_64 Hackintosh), Windows 10+,
///   Debian/Ubuntu/Mint Linux, and iOS: Bridges to the local LiteRT-LM / Gemma-2B desktop runtime
///   only when the runtime explicitly confirms that a Gemma engine is loaded and ready.
class MediaPipeLlmService {
  static final MediaPipeLlmService _instance = MediaPipeLlmService._internal();
  factory MediaPipeLlmService() => _instance;
  MediaPipeLlmService._internal();

  static const MethodChannel _channel = MethodChannel('care_connect/mediapipe_llm');

  bool _isInitialized = false;
  bool _usingDesktopBridge = false;
  bool _usingAndroidNative = false;

  bool get isInitialized => _isInitialized;

  @visibleForTesting
  bool? debugIsAndroidOverride;

  @visibleForTesting
  void resetForTesting() {
    _isInitialized = false;
    _usingDesktopBridge = false;
    _usingAndroidNative = false;
    debugIsAndroidOverride = null;
  }

  bool get _isAndroidPlatform =>
      debugIsAndroidOverride ?? (!kIsWeb && Platform.isAndroid);

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
    if (kIsWeb || _isAndroidPlatform || Platform.isIOS) return null;
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

  /// Checks if MediaPipe / LiteRT-LM inference has a confirmed, loaded Gemma engine ready.
  Future<Map<String, dynamic>> checkAvailability() async {
    if (_isAndroidPlatform) {
      try {
        final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('isAvailable');
        if (res != null && (res['available'] as bool? ?? false)) {
          var initialized = res['isInitialized'] as bool? ?? false;
          var resolvedPath = res['modelPath'] as String? ?? '';

          if (!initialized) {
            final initRes = await _channel.invokeMethod<Map<dynamic, dynamic>>(
              'initialize',
              {
                if (resolvedPath.isNotEmpty) 'modelPath': resolvedPath,
                'maxTokens': 256,
                'topK': 40,
                'temperature': 0.2,
              },
            );
            if (initRes != null && (initRes['success'] as bool? ?? false)) {
              initialized = true;
              resolvedPath = initRes['modelPath'] as String? ?? resolvedPath;
            }
          }

          if (initialized) {
            _isInitialized = true;
            _usingAndroidNative = true;
            _usingDesktopBridge = false;
            return {
              'available': true,
              'isInitialized': true,
              'engine': 'android-mediapipe-jni',
              'modelPath': resolvedPath,
              'suggestedPath':
                  res['suggestedPath'] as String? ?? '/sdcard/Download/gemma-2b.bin',
            };
          }
        }
      } catch (e) {
        debugPrint('MediaPipeLlmService Android native check failed: $e');
      }
    }

    // Desktop / Cross-Platform Bridge: require explicit Gemma engine readiness from the bridge.
    String? bridgeReason;
    try {
      final readiness = await ColibriService().checkGemmaReadiness();
      if (readiness['ready'] == true) {
        _isInitialized = true;
        _usingDesktopBridge = true;
        _usingAndroidNative = false;
        return {
          'available': true,
          'isInitialized': true,
          'engine': 'google-litert-lm-desktop-bridge',
          'modelPath':
              readiness['baseUrl'] as String? ?? ColibriService().getDefaultColibriUrl(),
          'suggestedPath': _defaultDesktopModelSuggestion(),
        };
      }
      bridgeReason = readiness['reason'] as String?;
    } catch (e) {
      debugPrint('MediaPipeLlmService desktop bridge check failed: $e');
    }

    _isInitialized = false;
    _usingDesktopBridge = false;
    _usingAndroidNative = false;

    final localModelFile = _findLocalDesktopModelFile();
    return {
      'available': false,
      'isInitialized': false,
      if (localModelFile != null) 'detectedModelFile': localModelFile,
      'suggestedPath': _defaultDesktopModelSuggestion(),
      'reason': bridgeReason ??
          'Gemma engine is not loaded. Start colibri_server.py with a loaded LiteRT-LM / Gemma model.',
    };
  }

  /// Initializes the on-device LiteRT/MediaPipe engine and confirms engine readiness.
  Future<bool> initialize({
    String? modelPath,
    int maxTokens = 256,
    int topK = 40,
    double temperature = 0.2,
  }) async {
    if (_isAndroidPlatform) {
      try {
        final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('initialize', {
          if (modelPath != null) 'modelPath': modelPath,
          'maxTokens': maxTokens,
          'topK': topK,
          'temperature': temperature,
        });
        if (res != null && (res['success'] as bool? ?? false)) {
          _isInitialized = true;
          _usingAndroidNative = true;
          _usingDesktopBridge = false;
          return true;
        }
      } catch (e) {
        debugPrint('MediaPipeLlmService Android native initialization failed: $e');
      }
    }

    try {
      final readiness = await ColibriService().checkGemmaReadiness();
      if (readiness['ready'] == true) {
        _isInitialized = true;
        _usingDesktopBridge = true;
        _usingAndroidNative = false;
        return true;
      }
    } catch (e) {
      debugPrint('MediaPipeLlmService desktop bridge initialization failed: $e');
    }

    _isInitialized = false;
    _usingDesktopBridge = false;
    _usingAndroidNative = false;
    return false;
  }

  /// Generates a response using a confirmed, loaded Gemma engine, rejecting unavailable inference.
  Future<Map<String, dynamic>> generateResponse(String prompt) async {
    if (prompt.trim().isEmpty) {
      return {
        'success': false,
        'error': 'Prompt cannot be empty.',
      };
    }

    if (!_isInitialized || (!_usingAndroidNative && !_usingDesktopBridge)) {
      return {
        'success': false,
        'error': 'Gemma engine is not initialized or ready.',
      };
    }

    if (_usingAndroidNative) {
      try {
        final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('generate', {
          'prompt': prompt,
        });

        if (res != null && (res['success'] as bool? ?? false)) {
          final content = res['content'] as String? ?? '';
          if (content.trim().isEmpty) {
            return {
              'success': false,
              'error': 'Gemma native engine returned an empty response.',
            };
          }
          return {
            'success': true,
            'content': content,
            'model': res['model'] as String? ?? ColibriService.gemmaModelId,
            'latencyMs': res['latencyMs'] as int? ?? 0,
          };
        }
      } catch (e) {
        debugPrint('MediaPipe Android JNI inference error: $e');
      }

      _isInitialized = false;
      _usingAndroidNative = false;
      return {
        'success': false,
        'error': 'Android MediaPipe Gemma engine failed during inference.',
      };
    }

    try {
      final edgeRes = await ColibriService().completeChat(
        prompt: prompt,
        model: ColibriService.gemmaModelId,
        temperature: 0.2,
      );
      final content = (edgeRes['content'] as String? ?? '').trim();
      final servedModel = edgeRes['model'] as String? ?? '';
      if (edgeRes['success'] == true &&
          content.isNotEmpty &&
          servedModel == ColibriService.gemmaModelId) {
        return {
          'success': true,
          'content': content,
          'model': servedModel,
          'latencyMs': edgeRes['latencyMs'] as int? ?? 0,
        };
      }

      _isInitialized = false;
      _usingDesktopBridge = false;
      return {
        'success': false,
        'error': edgeRes['error'] ??
            'Gemma desktop bridge engine is unavailable or returned an invalid response.',
      };
    } catch (e) {
      _isInitialized = false;
      _usingDesktopBridge = false;
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
        'content':
            '${ColibriService.escalateToken} This inquiry involves medication dosage changes, symptoms, or multi-campus facility information.',
        'model': ColibriService.gemmaModelId,
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
        'model': result['model'] ?? ColibriService.gemmaModelId,
        'latencyMs': result['latencyMs'] ?? 0,
        'escalateToCloud': escalated,
      };
    }

    return result;
  }
}
