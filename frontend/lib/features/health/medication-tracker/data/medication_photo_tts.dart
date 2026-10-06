import 'package:care_connect_app/services/tts_engine.dart';

/// Reads prefilled medication details aloud before the user confirms them.
/// Uses the same voice settings as the mail read-aloud feature.
class MedicationPhotoTts {
  MedicationPhotoTts({TtsEngine? engine})
      : _engine = engine ?? FlutterTtsEngine();

  final TtsEngine _engine;
  bool _ready = false;

  Future<void> _ensureReady() async {
    if (_ready) return;
    await _engine.setLanguage('en-US');
    await _engine.setSpeechRate(0.45);
    await _engine.setVolume(1.0);
    await _engine.setPitch(1.0);
    try {
      await _engine.awaitSpeakCompletion(true);
    } catch (_) {
      // Optional on some platforms.
    }
    _ready = true;
  }

  Future<void> speak(String text) async {
    final utterance = text.trim();
    if (utterance.isEmpty) return;
    await _ensureReady();
    await _engine.stop();
    await _engine.speak(utterance);
  }

  Future<void> stop() async {
    await _engine.stop();
  }
}
