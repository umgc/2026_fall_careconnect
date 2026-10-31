// Coverage for the Porcupine wake-word setup in VoiceCommandAI
// (lib/features/ai/presentation/pages/voice_command_ai.dart). The
// "porcupine" and "flutter_voice_processor_methods" method channels are
// mocked so the init succeeds, fails with a PorcupineException, or fails
// with an unexpected error.

import 'package:care_connect_app/features/ai/presentation/pages/voice_command_ai.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/services/voice_intent_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _porcupine = MethodChannel('porcupine');
const _voiceProcessor = MethodChannel('flutter_voice_processor_methods');
const _speech = MethodChannel('plugin.csdcorp.com/speech_to_text');

Widget _app() => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: VoiceCommandAI()),
    );

void main() {
  final calls = <String>[];

  void mock(MethodChannel channel, Future<Object?> Function(MethodCall) h) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      calls.add('${channel.name}:${call.method}');
      return h(call);
    });
  }

  setUp(() {
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    VoiceIntentService.testOverride =
        ({required String utterance, String locale = 'en', String? screenId}) =>
            null;
    mock(_speech, (call) async => call.method == 'initialize' ? true : null);
  });

  tearDown(() {
    VoiceIntentService.testOverride = null;
    for (final c in [_porcupine, _voiceProcessor, _speech]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, null);
    }
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 3));
    }
  }

  testWidgets('wake word engine starts when the platform accepts it',
      (tester) async {
    mock(_porcupine, (call) async {
      if (call.method == 'FROM_BUILTIN_KEYWORDS') {
        return {
          'handle': 'h1',
          'frameLength': 512,
          'sampleRate': 16000,
          'version': '3.0.0',
        };
      }
      return null;
    });
    mock(_voiceProcessor, (call) async {
      if (call.method == 'hasRecordAudioPermission') return true;
      return null;
    });

    await tester.pumpWidget(_app());
    await settle(tester);

    expect(calls, contains('porcupine:FROM_BUILTIN_KEYWORDS'));
    expect(calls, contains('flutter_voice_processor_methods:start'));
    expect(find.text('Say wake word or tap mic'), findsOneWidget);
    expect(find.textContaining('Wake word init error'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a Porcupine error is shown in a snackbar', (tester) async {
    mock(_porcupine, (call) async {
      throw PlatformException(
          code: 'PorcupineActivationException', message: 'bad key');
    });

    await tester.pumpWidget(_app());
    await settle(tester);

    expect(find.textContaining('Wake word init error'), findsOneWidget);
    expect(find.textContaining('bad key'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('missing microphone permission is reported', (tester) async {
    mock(_porcupine, (call) async {
      if (call.method == 'FROM_BUILTIN_KEYWORDS') {
        return {
          'handle': 'h2',
          'frameLength': 512,
          'sampleRate': 16000,
          'version': '3.0.0',
        };
      }
      return null;
    });
    mock(_voiceProcessor, (call) async => false);

    await tester.pumpWidget(_app());
    await settle(tester);

    expect(
      find.text(
          'Wake word init error: User did not give permission to record audio.'),
      findsOneWidget,
    );
    await unmount(tester);
  });
}
