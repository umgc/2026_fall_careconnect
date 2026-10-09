// MedicationPhotoTts: reads prefilled medication details aloud before the
// user confirms them (FEAT-32). Tested with a recording engine, no real speech.

import 'package:care_connect_app/features/health/medication-tracker/data/medication_photo_tts.dart';
import 'package:care_connect_app/services/tts_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingEngine implements TtsEngine {
  final List<String> calls = [];
  bool failAwaitCompletion = false;

  @override
  Future<dynamic> setLanguage(String language) async => calls.add('language:$language');

  @override
  Future<dynamic> setSpeechRate(double rate) async => calls.add('rate:$rate');

  @override
  Future<dynamic> setVolume(double volume) async => calls.add('volume:$volume');

  @override
  Future<dynamic> setPitch(double pitch) async => calls.add('pitch:$pitch');

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async {
    if (failAwaitCompletion) throw UnsupportedError('not on this platform');
    calls.add('await:$awaitCompletion');
  }

  @override
  Future<dynamic> speak(String text) async => calls.add('speak:$text');

  @override
  Future<dynamic> stop() async => calls.add('stop');
}

void main() {
  late _RecordingEngine engine;
  late MedicationPhotoTts tts;

  setUp(() {
    engine = _RecordingEngine();
    tts = MedicationPhotoTts(engine: engine);
  });

  test('the first speak sets the voice up, stops anything playing, then speaks the trimmed text', () async {
    await tts.speak('  Lisinopril 20 mg  ');

    expect(engine.calls, [
      'language:en-US',
      'rate:0.45',
      'volume:1.0',
      'pitch:1.0',
      'await:true',
      'stop',
      'speak:Lisinopril 20 mg',
    ]);
  });

  test('the voice is set up once, not before every utterance', () async {
    await tts.speak('first');
    engine.calls.clear();

    await tts.speak('second');

    expect(engine.calls, ['stop', 'speak:second']);
  });

  test('blank text says nothing and does not touch the engine', () async {
    await tts.speak('   ');
    await tts.speak('');

    expect(engine.calls, isEmpty);
  });

  test('a platform without awaitSpeakCompletion still speaks', () async {
    engine.failAwaitCompletion = true;

    await tts.speak('Take with food');

    expect(engine.calls, contains('speak:Take with food'));
  });

  test('stop stops the engine', () async {
    await tts.stop();

    expect(engine.calls, ['stop']);
  });
}
