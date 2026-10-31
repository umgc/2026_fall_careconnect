// Gap-filling widget tests for VoiceCommandAI
// (lib/features/ai/presentation/pages/voice_command_ai.dart).
//
// The sibling suites cover the happy paths. This file covers speech-engine
// failure handling (unavailable engine, init exception, denied permission,
// engine errors, silence), status-driven processing of partial results, the
// spoken confirm/cancel of the SOS dialog and of a pending command, and
// single-shot capture mode.
//
// speech_to_text and porcupine are faked over their method channels and the
// AI intent service is stubbed to "no result", so the on-device keyword table
// decides what each utterance means. No microphone or network is used.

import 'dart:convert';

import 'package:care_connect_app/features/ai/presentation/pages/voice_command_ai.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/services/voice_intent_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _speechChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');

/// Behaviour of the fake speech engine for the current test.
bool _initializeResult = true;
bool _initializeThrows = false;
bool _hasPermission = true;
bool _listenThrows = false;
final List<String> _speechCalls = <String>[];

Widget _app({
  bool singleShot = false,
  ValueChanged<String?>? onSingleShotResult,
}) {
  final router = GoRouter(
    initialLocation: '/voice',
    routes: [
      GoRoute(
        path: '/voice',
        builder: (context, __) => Scaffold(
          body: singleShot
              ? Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      final result = await Navigator.of(context).push<String>(
                        MaterialPageRoute(
                          builder: (_) => const Scaffold(
                            body: VoiceCommandAI(singleShot: true),
                          ),
                        ),
                      );
                      onSingleShotResult?.call(result);
                    },
                    child: const Text('Dictate'),
                  ),
                )
              : const VoiceCommandAI(),
        ),
      ),
      GoRoute(
        path: '/:page',
        builder: (_, s) => Scaffold(body: Text('page:${s.uri.path}')),
      ),
    ],
  );
  return MaterialApp.router(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
  );
}

/// Delivers a recognition result from the fake engine to the plugin.
Future<void> _recognize(WidgetTester tester, String words,
    {required bool isFinal}) async {
  final resultJson = jsonEncode({
    'resultType': isFinal ? 2 : 0,
    'alternates': [
      {'recognizedWords': words, 'confidence': 0.95},
    ],
  });
  await _deliver(tester, 'textRecognition', resultJson);
}

/// Delivers an engine callback (notifyStatus / notifyError) to the plugin.
Future<void> _deliver(
    WidgetTester tester, String method, Object? argument) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    _speechChannel.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, argument)),
    (ByteData? data) {},
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(seconds: 3));
  }
}

Future<void> _finish(WidgetTester tester) async {
  await _flush(tester);
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  await _flush(tester);
}

Future<void> _tapMic(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.mic).last);
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(_app());
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _initializeResult = true;
    _initializeThrows = false;
    _hasPermission = true;
    _listenThrows = false;
    _speechCalls.clear();
    VoiceIntentService.testOverride = (
            {required String utterance,
            String locale = 'en',
            String? screenId}) =>
        null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.picovoice.ai/porcupine_manager'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(_speechChannel, (call) async {
      _speechCalls.add(call.method);
      switch (call.method) {
        case 'has_permission':
          return _hasPermission;
        case 'initialize':
          if (_initializeThrows) {
            throw PlatformException(code: 'init_failed');
          }
          return _initializeResult;
        case 'listen':
          if (_listenThrows) {
            throw PlatformException(code: 'listen_failed');
          }
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    VoiceIntentService.testOverride = null;
  });

  group('speech engine problems', () {
    testWidgets('an unavailable engine tells the user to navigate manually',
        (tester) async {
      _initializeResult = false;
      await _open(tester);

      await _tapMic(tester);

      expect(find.text('Speech recognition not available'), findsOneWidget);
      expect(
          find.text('Voice not supported on this device. '
              'Use manual navigation.'),
          findsWidgets);
      expect(_speechCalls, isNot(contains('listen')));
      await _finish(tester);
    });

    testWidgets('an engine that throws on init is reported the same way',
        (tester) async {
      _initializeThrows = true;
      await _open(tester);

      await _tapMic(tester);

      expect(find.text('Speech recognition not available'), findsOneWidget);
      expect(_speechCalls, isNot(contains('listen')));
      await _finish(tester);
    });
  });

  // speech_to_text is a process-wide singleton that only wires its error and
  // status listeners on the first *successful* initialize(); later pages reuse
  // the first page's callbacks. This scenario therefore runs first among the
  // tests that initialise successfully and keeps one page mounted throughout.
  testWidgets('engine errors and status changes drive the voice status',
      (tester) async {
    await _open(tester);

    // 1. A permanent engine error surfaces the unavailable message.
    await _tapMic(tester);
    expect(_speechCalls, contains('listen'));
    await _deliver(
      tester,
      'notifyError',
      jsonEncode({'errorMsg': 'error_network', 'permanent': true}),
    );
    expect(find.text('Speech recognition not available'), findsOneWidget);
    await _flush(tester);
    expect(find.textContaining('Status: Ready'), findsOneWidget);

    // 2. The engine finishing without any result reports silence.
    await _tapMic(tester);
    await _deliver(tester, 'notifyStatus', 'listening');
    await _deliver(tester, 'notifyStatus', 'doneNoResult');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No speech detected.'), findsOneWidget);
    await _flush(tester);
    expect(find.textContaining('Status: Ready'), findsOneWidget);

    // 3. A partial result is processed once the engine reports it is done.
    await _tapMic(tester);
    await _recognize(tester, 'take me home', isFinal: false);
    await _deliver(tester, 'notifyStatus', 'done');
    await _deliver(tester, 'notifyStatus', 'final');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('voice_confirm_btn')), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice_confirm_btn')));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('page:/'), findsOneWidget);
    await _finish(tester);
  });

  group('more speech engine problems', () {
    testWidgets('a denied microphone permission is reported', (tester) async {
      _hasPermission = false;
      await _open(tester);

      await _tapMic(tester);

      expect(find.text('Microphone permission denied'), findsOneWidget);
      expect(
          find.text('Enable microphone in device settings or use manual '
              'navigation.'),
          findsWidgets);
      expect(_speechCalls, isNot(contains('listen')));
      await _finish(tester);
    });

    testWidgets('listening times out when nothing is said', (tester) async {
      await _open(tester);
      await _tapMic(tester);

      await tester.pump(const Duration(seconds: 13));

      expect(find.text('Listening timed out.'), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('an unrecognised phrase reports command not recognized',
        (tester) async {
      await _open(tester);
      await _tapMic(tester);

      await _recognize(tester, 'banana smoothie recipe', isFinal: true);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Command not recognized — please try again.'),
          findsOneWidget);
      await _finish(tester);
    });
  });

  group('spoken confirmation', () {
    testWidgets('saying "yes" sends the SOS alert', (tester) async {
      await _open(tester);
      await _tapMic(tester);
      await _recognize(tester, 'emergency', isFinal: true);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Emergency Alert'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));

      await _recognize(tester, 'yes', isFinal: true);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.text('Emergency Alert'), findsNothing);
      expect(find.textContaining('Alert not currently implemented'),
          findsOneWidget);
      await _finish(tester);
    });

    testWidgets('saying "cancel" dismisses the SOS alert', (tester) async {
      await _open(tester);
      await _tapMic(tester);
      await _recognize(tester, 'emergency', isFinal: true);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      await _recognize(tester, 'cancel', isFinal: true);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.text('Emergency Alert'), findsNothing);
      expect(find.textContaining('Emergency alert cancelled'), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('an unrelated phrase leaves the SOS dialog open',
        (tester) async {
      await _open(tester);
      await _tapMic(tester);
      await _recognize(tester, 'emergency', isFinal: true);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      await _recognize(tester, 'what time is it', isFinal: true);

      expect(find.text('Emergency Alert'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pump();
      await _finish(tester);
    });

    testWidgets('a pending partial command can be cancelled by voice',
        (tester) async {
      await _open(tester);
      await _tapMic(tester);
      // "emer" is a unique prefix of the "emergency" phrase.
      await _recognize(tester, 'emer', isFinal: true);
      expect(find.byKey(const Key('voice_confirm_btn')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));

      await _recognize(tester, 'cancel', isFinal: true);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('voice_confirm_btn')), findsNothing);
      expect(find.textContaining('Action cancelled'), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('a pending partial command can be confirmed by voice',
        (tester) async {
      await _open(tester);
      await _tapMic(tester);
      await _recognize(tester, 'emer', isFinal: true);
      expect(find.byKey(const Key('voice_confirm_btn')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));

      await _recognize(tester, 'confirm', isFinal: true);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('voice_confirm_btn')), findsNothing);
      await _finish(tester);
    });
  });

  group('single-shot capture', () {
    testWidgets('returns the recognized words to the caller', (tester) async {
      String? captured;
      await tester.pumpWidget(_app(
        singleShot: true,
        onSingleShotResult: (r) => captured = r,
      ));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Dictate'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      await _tapMic(tester);
      await _recognize(tester, 'my knee hurts today', isFinal: true);
      expect(find.textContaining('Speech captured'), findsWidgets);
      await _flush(tester);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(captured, 'my knee hurts today');
      expect(find.text('Dictate'), findsOneWidget);
      await _finish(tester);
    });
  });
}
