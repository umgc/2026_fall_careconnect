import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Speaks envelope-level mail text for ADA audio readout (Task 3.14.10).
///
/// Session-aware API: [speak] takes a [sessionId] so multiple Start/Stop
/// controls can share one engine and preempt each other cleanly.
abstract class MailEnvelopeTts {
  Future<void> speak(String sessionId, String text);

  Future<void> stop();

  Future<void> dispose();

  /// Currently speaking session, or null when idle.
  String? get activeSessionId;

  bool get isSpeaking;

  /// Notifies listeners when [activeSessionId] / [isSpeaking] change.
  ValueListenable<MailTtsSessionState> get sessionListenable;
}

/// Snapshot of the shared TTS session used by read-aloud buttons.
class MailTtsSessionState {
  const MailTtsSessionState({this.activeSessionId, this.isSpeaking = false});

  final String? activeSessionId;
  final bool isSpeaking;

  static const idle = MailTtsSessionState();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MailTtsSessionState &&
          activeSessionId == other.activeSessionId &&
          isSpeaking == other.isSpeaking;

  @override
  int get hashCode => Object.hash(activeSessionId, isSpeaking);
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

  /// Optional completion hook; engines that support it should invoke [callback].
  void setCompletionHandler(void Function() callback) {}
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

  @override
  void setCompletionHandler(void Function() callback) {
    _tts.setCompletionHandler(callback);
  }
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
      : _engine = engine ?? FlutterTtsEngine() {
    _engine.setCompletionHandler(_onEngineComplete);
  }

  final MailTtsEngine _engine;
  final ValueNotifier<MailTtsSessionState> _session =
      ValueNotifier(MailTtsSessionState.idle);
  bool _ready = false;
  int _speakGeneration = 0;

  @override
  ValueListenable<MailTtsSessionState> get sessionListenable => _session;

  @override
  String? get activeSessionId => _session.value.activeSessionId;

  @override
  bool get isSpeaking => _session.value.isSpeaking;

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

  void _publish({String? sessionId, required bool speaking}) {
    _session.value = MailTtsSessionState(
      activeSessionId: sessionId,
      isSpeaking: speaking,
    );
  }

  void _onEngineComplete() {
    // Natural completion — clear active session so buttons reset.
    _speakGeneration++;
    _publish(sessionId: null, speaking: false);
  }

  @override
  Future<void> speak(String sessionId, String text) async {
    final utterance = text.trim();
    if (utterance.isEmpty) return;

    await _ensureReady();
    // Stop any prior session before starting this one.
    await _engine.stop();
    final generation = ++_speakGeneration;
    _publish(sessionId: sessionId, speaking: true);

    try {
      await _engine.speak(utterance);
    } finally {
      // If this speak was preempted or stopped, generation will have advanced.
      if (generation == _speakGeneration) {
        _publish(sessionId: null, speaking: false);
      }
    }
  }

  @override
  Future<void> stop() async {
    _speakGeneration++;
    await _engine.stop();
    _publish(sessionId: null, speaking: false);
  }

  @override
  Future<void> dispose() async {
    _speakGeneration++;
    await _engine.stop();
    _publish(sessionId: null, speaking: false);
    _session.dispose();
  }
}
