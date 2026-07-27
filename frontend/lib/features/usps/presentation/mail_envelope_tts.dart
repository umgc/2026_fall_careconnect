import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Speaks envelope-level mail text for ADA audio readout (Task 3.14.10).
abstract class MailEnvelopeTts {
  Future<void> speak(String text);

  Future<void> stop();

  Future<void> dispose();
}

/// Platform TTS engine surface used by [FlutterMailEnvelopeTts].
///
/// Extracted so unit tests can inject a fake without touching MethodChannels.
abstract class MailTtsEngine {
  Future<dynamic> setLanguage(String language);

  Future<dynamic> setSpeechRate(double rate);

  Future<dynamic> setVolume(double volume);

  Future<dynamic> setPitch(double pitch);

  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion);

  Future<dynamic> speak(String text);

  Future<dynamic> stop();
}

class FlutterTtsEngine implements MailTtsEngine {
  FlutterTtsEngine({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  @override
  Future<dynamic> setLanguage(String language) => _tts.setLanguage(language);

  @override
  Future<dynamic> setSpeechRate(double rate) => _tts.setSpeechRate(rate);

  @override
  Future<dynamic> setVolume(double volume) => _tts.setVolume(volume);

  @override
  Future<dynamic> setPitch(double pitch) => _tts.setPitch(pitch);

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) =>
      _tts.awaitSpeakCompletion(awaitCompletion);

  @override
  Future<dynamic> speak(String text) => _tts.speak(text);

  @override
  Future<dynamic> stop() => _tts.stop();
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
  FlutterMailEnvelopeTts({MailTtsEngine? engine})
      : _engine = engine ?? FlutterTtsEngine();

  final MailTtsEngine _engine;
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
