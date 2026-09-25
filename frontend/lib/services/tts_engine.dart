import 'package:flutter_tts/flutter_tts.dart';

/// Platform TTS engine surface shared by any feature that reads text aloud.
///
/// Extracted so unit tests can inject a fake without touching MethodChannels.
abstract class TtsEngine {
  Future<dynamic> setLanguage(String language);

  Future<dynamic> setSpeechRate(double rate);

  Future<dynamic> setVolume(double volume);

  Future<dynamic> setPitch(double pitch);

  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion);

  Future<dynamic> speak(String text);

  Future<dynamic> stop();
}

class FlutterTtsEngine implements TtsEngine {
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
