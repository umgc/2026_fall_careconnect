// Coverage for VoiceCommandAI
// (lib/features/ai/presentation/pages/voice_command_ai.dart): native
// speech_to_text status/error callbacks, init failure, timeout, voice
// confirmation, partial single matches, the SOS and high-risk dialogs answered
// by voice, and flyout keyboard actions.
//
// speech_to_text is a process-wide singleton that registers its status/error
// listeners only on the first successful initialize(). The first test makes
// initialize() throw so the second test's widget is the one that registers
// the listeners. Keep that order.

import 'dart:convert';

import 'package:care_connect_app/features/ai/presentation/pages/voice_command_ai.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/services/voice_intent_registry.dart';
import 'package:care_connect_app/services/voice_intent_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _speechChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');

bool _initThrows = false;

Widget _app({
  VoiceCommandPresentation mode = VoiceCommandPresentation.page,
  VoidCallback? onClose,
}) {
  final router = GoRouter(
    initialLocation: '/voice',
    routes: [
      GoRoute(
        path: '/voice',
        builder: (_, __) => Scaffold(
          body: VoiceCommandAI(presentationMode: mode, onCloseRequested: onClose),
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

Future<void> _platformCall(String method, Object? args) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    _speechChannel.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
    (ByteData? data) {},
  );
}

Future<void> _say(WidgetTester tester, String words,
    {bool finalResult = true}) async {
  await _platformCall(
    'textRecognition',
    jsonEncode({
      'resultType': finalResult ? 2 : 0,
      'alternates': [
        {'recognizedWords': words, 'confidence': 0.95},
      ],
    }),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _status(WidgetTester tester, String status) async {
  await _platformCall('notifyStatus', status);
  await tester.pump();
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(seconds: 3));
  }
}

Future<void> _tearDown(WidgetTester tester) async {
  await _flush(tester);
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  await _flush(tester);
}

Future<void> _startListening(WidgetTester tester) async {
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
    VoiceIntentService.testOverride =
        ({required String utterance, String locale = 'en', String? screenId}) =>
            null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.picovoice.ai/porcupine_manager'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(_speechChannel, (call) async {
      if (call.method == 'initialize') {
        if (_initThrows) {
          throw PlatformException(code: 'boom', message: 'no engine');
        }
        return true;
      }
      if (call.method == 'has_permission') return true;
      if (call.method == 'listen') return true;
      return null;
    });
  });

  tearDown(() {
    VoiceIntentService.testOverride = null;
    _initThrows = false;
  });

  testWidgets('speech init failure shows unavailable message (runs first)',
      (tester) async {
    _initThrows = true;
    await _open(tester);
    await _startListening(tester);
    await tester.pump();

    expect(find.text('Speech recognition not available'), findsOneWidget);
    expect(
      find.text('Voice not supported on this device. Use manual navigation.'),
      findsWidgets,
    );
    await _tearDown(tester);
  });

  testWidgets('status and error callbacks drive the voice status',
      (tester) async {
    await _open(tester);

    // "listening" then "notListening" with nothing heard -> no-speech error.
    await _startListening(tester);
    await _status(tester, 'listening');
    await _status(tester, 'notListening');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('No speech detected.'), findsOneWidget);
    expect(find.text('No speech heard. Tap the microphone to try again.'),
        findsWidgets);
    await _flush(tester);

    // A partial result followed by "notListening" processes the buffer.
    await _startListening(tester);
    await _say(tester, 'take me home', finalResult: false);
    await _status(tester, 'notListening');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('voice_confirm_btn')), findsOneWidget);
    expect(find.textContaining('Recognized: "take me home"'), findsWidgets);
    await tester.tap(find.byKey(const Key('voice_cancel_btn')));
    await tester.pump();
    await _flush(tester);

    // A recognizer error reports voice as unavailable.
    await _startListening(tester);
    await _status(tester, 'listening');
    await _platformCall(
      'notifyError',
      jsonEncode({'errorMsg': 'error_network', 'permanent': false}),
    );
    await tester.pump();
    expect(find.text('Speech recognition not available'), findsOneWidget);
    await _tearDown(tester);
  });

  testWidgets('listening timeout with partial words processes them',
      (tester) async {
    await _open(tester);
    await _startListening(tester);
    await _say(tester, 'open calendar', finalResult: false);
    await tester.pump(const Duration(seconds: 13));
    expect(find.byKey(const Key('voice_confirm_btn')), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice_cancel_btn')));
    await tester.pump();
    await _tearDown(tester);
  });

  testWidgets('a single partial navigation match asks to confirm',
      (tester) async {
    await _open(tester);
    await _startListening(tester);
    await _say(tester, 'open ai conf');
    expect(find.byKey(const Key('voice_confirm_btn')), findsOneWidget);
    expect(find.textContaining('Recognized: "open ai conf"'), findsWidgets);
    await tester.tap(find.byKey(const Key('voice_cancel_btn')));
    await tester.pump();
    await _tearDown(tester);
  });

  testWidgets('partial "emerg" confirms the SOS intent by voice',
      (tester) async {
    await _open(tester);
    await _startListening(tester);
    await _say(tester, 'emerg');
    expect(find.text('SOS Emergency Alert — confirm?'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 400));
    await _say(tester, 'confirm');
    await tester.pump();
    expect(find.textContaining('SOS Emergency Alert'), findsWidgets);
    expect(find.textContaining('Confirmed'), findsWidgets);
    await _tearDown(tester);
  });

  testWidgets('partial "emerg" cancelled by voice', (tester) async {
    await _open(tester);
    await _startListening(tester);
    await _say(tester, 'emerg');
    await tester.pump(const Duration(milliseconds: 400));
    await _say(tester, 'no');
    expect(find.text('Action cancelled.'), findsWidgets);
    await _tearDown(tester);
  });

  testWidgets('SOS dialog answered by voice', (tester) async {
    await _open(tester);
    await _startListening(tester);
    await _say(tester, 'emergency');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Emergency Alert'), findsOneWidget);
    await _say(tester, 'send alert');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Emergency Alert'), findsNothing);
    expect(find.textContaining('Alert not currently implemented'),
        findsOneWidget);
    await _flush(tester);

    await _startListening(tester);
    await _say(tester, 'emergency');
    await tester.pump(const Duration(milliseconds: 400));
    await _say(tester, 'stop');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Emergency alert cancelled'), findsOneWidget);
    await _tearDown(tester);
  });

  testWidgets('high-risk confirmation dialog answered by voice',
      (tester) async {
    VoiceIntentService.testOverride = (
            {required String utterance, String locale = 'en', String? screenId}) =>
        VoiceIntentResult(
          intent: 'schedule',
          requiresConfirmation: true,
          success: true,
        );
    await _open(tester);
    await _startListening(tester);
    await _say(tester, 'book a visit');
    await tester.tap(find.byKey(const Key('voice_confirm_btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Confirm Schedule Appointment'), findsWidgets);
    await _say(tester, 'yes');
    await tester.pump();
    await tester.pump();
    expect(find.text('page:/calendar'), findsOneWidget);
    await _tearDown(tester);
  });

  testWidgets('high-risk confirmation dialog cancelled by voice',
      (tester) async {
    VoiceIntentService.testOverride = (
            {required String utterance, String locale = 'en', String? screenId}) =>
        VoiceIntentResult(
          intent: 'call',
          requiresConfirmation: true,
          success: true,
        );
    await _open(tester);
    await _startListening(tester);
    await _say(tester, 'ring my son');
    await tester.tap(find.byKey(const Key('voice_confirm_btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _say(tester, 'stop');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('cancelled'), findsWidgets);
    await _tearDown(tester);
  });

  testWidgets('AI intent that needs no confirmation falls back',
      (tester) async {
    VoiceIntentRegistry().registerIntent(const IntentDefinition(
      intentName: 'coverage_low_risk',
      displayLabel: 'Low Risk',
    ));
    VoiceIntentService.testOverride = (
            {required String utterance, String locale = 'en', String? screenId}) =>
        VoiceIntentResult(intent: 'coverage_low_risk', success: true);
    await _open(tester);
    await _startListening(tester);
    await _say(tester, 'do the thing');
    expect(find.text('Command not recognized — please try again.'),
        findsOneWidget);
    expect(find.textContaining('command not recognized'), findsWidgets);
    await _tearDown(tester);
  });

  testWidgets('flyout keyboard arrows and dismiss action', (tester) async {
    var closed = 0;
    await tester.pumpWidget(_app(
      mode: VoiceCommandPresentation.flyout,
      onClose: () => closed++,
    ));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    final ctx = tester.element(find
        .descendant(
          of: find.byType(Actions),
          matching: find.byType(AnimatedContainer),
        )
        .first);
    Actions.invoke(ctx, const NextFocusIntent());
    Actions.invoke(ctx, const PreviousFocusIntent());
    Actions.invoke(ctx, const DismissIntent());
    await tester.pump();
    expect(closed, 1);
    await _tearDown(tester);
  });

  testWidgets('two equally specific phrases ask to clarify', (tester) async {
    await _open(tester);
    await _startListening(tester);
    await _say(tester, 'home menu');
    expect(find.byKey(const Key('voice_clarify_cancel_btn')), findsOneWidget);
    expect(find.textContaining('Multiple matches'), findsWidgets);
    expect(find.byType(ActionChip), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('voice_clarify_cancel_btn')));
    await tester.pump();
    await _tearDown(tester);
  });

  testWidgets('disposing while the mic pulse animates stops it',
      (tester) async {
    await _open(tester);
    await _startListening(tester);
    await _say(tester, 'take me', finalResult: false);
    expect(find.textContaining('take me'), findsWidgets);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await _flush(tester);
    expect(find.byType(VoiceCommandAI), findsNothing);
  });

  testWidgets('an SOS handler failure is reported as not recognized',
      (tester) async {
    registerDefaultVoiceIntents();
    final registry = VoiceIntentRegistry();
    final original = registry.resolveIntent('sos')!;
    addTearDown(() => registry.registerIntent(original));
    registry.registerIntent(IntentDefinition(
      intentName: 'sos',
      displayLabel: original.displayLabel,
      requiresConfirmation: true,
      handler: (_) async => throw StateError('alert backend down'),
    ));

    await _open(tester);
    await _startListening(tester);
    await _say(tester, 'emergency');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Send Alert'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Alert not currently implemented'),
        findsNothing);
    expect(find.text('Emergency Alert'), findsNothing);
    expect(find.byKey(const Key('voice_confirm_btn')), findsNothing);
    await _tearDown(tester);
  });
}
