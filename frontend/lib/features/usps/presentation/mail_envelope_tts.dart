import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Speaks envelope-level mail text for ADA audio readout (Task 3.14.10).
abstract class MailEnvelopeTts {
  Future<void> speak(String text);

  Future<void> stop();

  Future<void> dispose();
}

/// Shared TTS instance used by mail list/detail read-aloud controls.
class MailEnvelopeTtsService {
  MailEnvelopeTtsService._();

  static MailEnvelopeTts _instance = FlutterMailEnvelopeTts();

  static MailEnvelopeTts get instance => _instance;

  @visibleForTesting
  static void debugSetInstance(MailEnvelopeTts tts) {
    _instance = tts;
  }

  @visibleForTesting
  static void debugResetInstance() {
    _instance = FlutterMailEnvelopeTts();
  }
}

class FlutterMailEnvelopeTts implements MailEnvelopeTts {
  FlutterMailEnvelopeTts({FlutterTts? engine}) : _tts = engine ?? FlutterTts();

  final FlutterTts _tts;
  bool _ready = false;

  Future<void> _ensureReady() async {
    if (_ready) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    // Prefer await-completion semantics where the platform supports it.
    try {
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {
      // Optional on some platforms.
    }
    _ready = true;
  }

  @override
  Future<void> speak(String text) async {
    final utterance = text.trim();
    if (utterance.isEmpty) return;
    await _ensureReady();
    await _tts.stop();
    await _tts.speak(utterance);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }

  @override
  Future<void> dispose() async {
    await _tts.stop();
  }
}
