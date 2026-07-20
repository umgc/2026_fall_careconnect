import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/usps/presentation/mail_envelope_tts.dart';

class _RecordingEngine implements MailTtsEngine {
  final List<String> calls = <String>[];
  bool throwOnAwaitCompletion = false;

  @override
  Future<dynamic> setLanguage(String language) async {
    calls.add('setLanguage:$language');
    return 1;
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async {
    calls.add('setSpeechRate:$rate');
    return 1;
  }

  @override
  Future<dynamic> setVolume(double volume) async {
    calls.add('setVolume:$volume');
    return 1;
  }

  @override
  Future<dynamic> setPitch(double pitch) async {
    calls.add('setPitch:$pitch');
    return 1;
  }

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async {
    calls.add('awaitSpeakCompletion:$awaitCompletion');
    if (throwOnAwaitCompletion) {
      throw Exception('unsupported');
    }
    return null;
  }

  @override
  Future<dynamic> speak(String text) async {
    calls.add('speak:$text');
    return 1;
  }

  @override
  Future<dynamic> stop() async {
    calls.add('stop');
    return 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('flutter_tts');
  final channelCalls = <String>[];

  setUp(() {
    channelCalls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      channelCalls.add(call.method);
      if (call.method == 'speak') {
        return 1;
      }
      return 1;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    MailEnvelopeTtsService.debugResetInstance();
  });

  group('MailEnvelopeTtsService', () {
    test('debugSetInstance replaces shared TTS', () async {
      final fake = _RecordingEngine();
      final tts = FlutterMailEnvelopeTts(engine: fake);
      MailEnvelopeTtsService.debugSetInstance(tts);

      expect(identical(MailEnvelopeTtsService.instance, tts), isTrue);
      await MailEnvelopeTtsService.instance.speak('From: Bank. Statement.');
      expect(fake.calls, contains('speak:From: Bank. Statement.'));
    });

    test('debugResetInstance clears shared instance until next use', () {
      final fake = FlutterMailEnvelopeTts(engine: _RecordingEngine());
      MailEnvelopeTtsService.debugSetInstance(fake);
      MailEnvelopeTtsService.debugResetInstance();
      final next = MailEnvelopeTtsService.instance;
      expect(next, isA<FlutterMailEnvelopeTts>());
      expect(identical(next, fake), isFalse);
    });
  });

  group('FlutterMailEnvelopeTts', () {
    test('speak configures engine once then speaks', () async {
      final engine = _RecordingEngine();
      final tts = FlutterMailEnvelopeTts(engine: engine);

      await tts.speak('From: Acme. Monthly statement.');
      await tts.speak('From: Acme. Monthly statement.');

      expect(engine.calls.where((c) => c.startsWith('setLanguage')).length, 1);
      expect(engine.calls.where((c) => c == 'stop').length, 2);
      expect(
        engine.calls.where((c) => c.startsWith('speak:')).length,
        2,
      );
    });

    test('speak ignores blank utterance', () async {
      final engine = _RecordingEngine();
      final tts = FlutterMailEnvelopeTts(engine: engine);

      await tts.speak('   ');
      expect(engine.calls, isEmpty);
    });

    test('awaitSpeakCompletion failures are ignored', () async {
      final engine = _RecordingEngine()..throwOnAwaitCompletion = true;
      final tts = FlutterMailEnvelopeTts(engine: engine);

      await tts.speak('Hello mail');
      expect(engine.calls, contains('speak:Hello mail'));
    });

    test('stop and dispose call engine stop', () async {
      final engine = _RecordingEngine();
      final tts = FlutterMailEnvelopeTts(engine: engine);

      await tts.stop();
      await tts.dispose();
      expect(engine.calls, ['stop', 'stop']);
    });
  });

  group('FlutterTtsEngine', () {
    test('forwards configuration and speak/stop to flutter_tts channel',
        () async {
      final engine = FlutterTtsEngine();

      await engine.setLanguage('en-US');
      await engine.setSpeechRate(0.45);
      await engine.setVolume(1.0);
      await engine.setPitch(1.0);
      try {
        await engine.awaitSpeakCompletion(true);
      } catch (_) {
        // Some platform handlers reject this; still exercise the call.
      }
      await engine.stop();
      await engine.speak('From: Acme Bank. Statement.');

      expect(channelCalls, contains('setLanguage'));
      expect(channelCalls, contains('setSpeechRate'));
      expect(channelCalls, contains('setVolume'));
      expect(channelCalls, contains('setPitch'));
      expect(channelCalls, contains('stop'));
      expect(channelCalls, contains('speak'));
    });
  });
}
