import 'package:flutter/foundation.dart';
import '../../../services/tts_engine.dart';

/// Speaks envelope-level mail text for ADA audio readout (Task 3.14.10).
abstract class MailEnvelopeTts {
  Future<void> speak(String text);

  Future<void> stop();

  Future<void> dispose();
}

/// Shared TTS instance used by mail list/detail read-aloud controls.
class MailEnvelopeTtsService {
  MailEnvelopeTtsService._();

  static MailEnvelopeTts? _instance;

  static MailEnvelopeTts get instance =>
      _instance ??= FlutterMailEnvelopeTts();

  @visibleForTesting
  static void debugSetInstance(MailEnvelopeTts tts) {
    _instance = tts;
  }

  @visibleForTesting
  static void debugResetInstance() {
    _instance = null;
  }
}

class FlutterMailEnvelopeTts implements MailEnvelopeTts {
  FlutterMailEnvelopeTts({TtsEngine? engine})
      : _engine = engine ?? FlutterTtsEngine();

  final TtsEngine _engine;
  bool _ready = false;

  Future<void> _ensureReady() async {
    if (_ready) return;
    await _engine.setLanguage('en-US');
    await _engine.setSpeechRate(0.45);
    await _engine.setVolume(1.0);
    await _engine.setPitch(1.0);
    // Prefer await-completion semantics where the platform supports it.
    try {
      await _engine.awaitSpeakCompletion(true);
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
    await _engine.stop();
    await _engine.speak(utterance);
  }

  @override
  Future<void> stop() async {
    await _engine.stop();
  }

  @override
  Future<void> dispose() async {
    await _engine.stop();
  }
}
