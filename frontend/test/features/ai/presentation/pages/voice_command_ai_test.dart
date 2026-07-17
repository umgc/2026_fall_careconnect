// Tests for VoiceCommandAI widget
// (lib/features/ai/presentation/pages/voice_command_ai.dart).
//
// Notes on testing constraints:
// - porcupine_flutter and speech_to_text are native plugins, mocked via
//   method channel handlers.
// - SpeechToText uses a singleton (factory constructor). Once initialize()
//   succeeds, _initWorked stays true for the entire test suite. Therefore
//   the "speech not available" test must run before any successful init test.
//   We put it in a separate group at the top.
// - SpeechToText._stop() creates a 2-second finalTimeout timer. We must
//   flush that timer by pumping 3+ seconds before test teardown.

import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:care_connect_app/features/ai/presentation/pages/voice_command_ai.dart';
import 'package:care_connect_app/services/voice_intent_service.dart';

/// Matches debug-mode status display delay in VoiceCommandAI (5s + buffer).
const _statusSettleDelay = Duration(milliseconds: 5050);

/// Builds a GoRouter-backed app hosting VoiceCommandAI plus stub destination
/// pages, so navigation commands (context.go) resolve in widget tests.
/// MaterialApp builds using the specified locale to test display text.
Widget _buildVoiceRouterApp({String localestring = 'en', bool singleShot = false}) {
  final router = GoRouter(
    initialLocation: '/voice',
    routes: [
      GoRoute(
        path: '/voice',
        builder: (_, __) => VoiceCommandAI(singleShot: singleShot),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const Scaffold(body: Text('Dashboard Page')),
      ),
      GoRoute(
        path: '/calendar',
        builder: (_, __) => const Scaffold(body: Text('Calendar Page')),
      ),
      GoRoute(
        path: '/symptoms',
        builder: (_, __) => const Scaffold(body: Text('Symptoms Page')),
      ),
    ],
  );
  return MaterialApp.router(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale(localestring), routerConfig: router);
}

/// Sends a speech recognition result via the method channel (platform -> Dart).
Future<void> _sendSpeechResult(
  WidgetTester tester,
  String words, {
  bool isFinal = true,
}) async {
  final resultJson = jsonEncode({
    'resultType': isFinal ? 2 : 0,
    'alternates': [
      {
        'recognizedWords': words,
        'confidence': 0.95,
      }
    ],
  });
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    'plugin.csdcorp.com/speech_to_text',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('textRecognition', resultJson),
    ),
    (ByteData? data) {},
  );
  await tester.pump();
}

/// Flush all pending timers (speech_to_text 2s final timer, our 12s timeout).
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(seconds: 3));
  }
}

/// Safely tear down by flushing timers then replacing the widget tree.
Future<void> _tearDown(WidgetTester tester) async {
  await _flush(tester);
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  await _flush(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> speechMethodCalls;

  /// Set up default mock handlers for both plugins.
  void setupDefaultMocks() {
    speechMethodCalls = [];

    // Default AI intent override: return null to fall through to keyword matching
    VoiceIntentService.testOverride = ({
      required String utterance,
      String locale = 'en',
      String? screenId,
    }) => null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.picovoice.ai/porcupine_manager'),
      (call) async => null,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugin.csdcorp.com/speech_to_text'),
      (call) async {
        speechMethodCalls.add(call.method);
        if (call.method == 'has_permission') return true;
        if (call.method == 'initialize') return true;
        if (call.method == 'listen') return true;
        if (call.method == 'cancel') return null;
        if (call.method == 'stop') return null;
        return null;
      },
    );
  }

  void clearMocks() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.picovoice.ai/porcupine_manager'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugin.csdcorp.com/speech_to_text'),
      null,
    );
  }

  // ─────────────────── Speech unavailable tests (MUST RUN FIRST) ───────────────────
  // These run before any test that successfully initializes the singleton.

  group('VoiceCommandAI speech unavailable', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('shows error when speech recognition not available - English',
        (tester) async {
      // Override to return false for initialize
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugin.csdcorp.com/speech_to_text'),
        (call) async {
          if (call.method == 'has_permission') return true;
          if (call.method == 'initialize') return false;
          if (call.method == 'stop') return null;
          if (call.method == 'cancel') return null;
          return null;
        },
      );

      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Speech recognition not available'), findsOneWidget);
      expect(find.text('Status: Error'), findsOneWidget);
      expect(
        find.text('Voice not supported on this device. Use manual navigation.'),
        findsOneWidget,
      );

      await _tearDown(tester);
    });

    testWidgets('shows error when speech recognition not available - Spanish',
        (tester) async {
      // Override to return false for initialize
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugin.csdcorp.com/speech_to_text'),
        (call) async {
          if (call.method == 'has_permission') return true;
          if (call.method == 'initialize') return false;
          if (call.method == 'stop') return null;
          if (call.method == 'cancel') return null;
          return null;
        },
      );

      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Reconocimiento de voz no disponible'), findsOneWidget);
      expect(find.text('Estado: Error'), findsOneWidget);
      expect(
        find.text('Voz no compatible con este dispositivo. Use la navegación manual.'),
        findsOneWidget,
      );

      await _tearDown(tester);
    });
  });

  // ──────────────────────── All other tests ────────────────────────

  group('VoiceCommandAI construction', () {
    test('can be constructed with default parameters', () {
      const widget = VoiceCommandAI();
      expect(widget, isA<StatefulWidget>());
      expect(widget.singleShot, isFalse);
    });

    test('singleShot can be set to true', () {
      const widget = VoiceCommandAI(singleShot: true);
      expect(widget.singleShot, isTrue);
    });

    test('accepts a key parameter', () {
      const key = ValueKey('voice');
      const widget = VoiceCommandAI(key: key);
      expect(widget.key, equals(key));
    });

    test('createState returns a State object', () {
      const widget = VoiceCommandAI();
      expect(widget.createState(), isA<State<VoiceCommandAI>>());
    });
  });

  group('VoiceCommandAI rendering', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('Team C smoke: renders primary voice controls', (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Voice Commands'), findsOneWidget);
      expect(find.byIcon(Icons.mic_none), findsOneWidget);
      expect(find.text('Say wake word or tap mic'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('renders Scaffold with AppBar titled Voice Commands - English',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Voice Commands'), findsOneWidget);
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('renders Scaffold with AppBar titled Voice Commands - Spanish',
        (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Comandos de Voz'), findsOneWidget);
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('AppBar has blue shade 900 background', (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, equals(Colors.blue.shade900));
    });

    testWidgets('renders mic_none icon initially (not wake-detected)',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.mic_none), findsOneWidget);
    });

    testWidgets('initial icon is grey and size 64', (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      final icon = tester.widget<Icon>(find.byIcon(Icons.mic_none));
      expect(icon.size, equals(64));
      expect(icon.color, equals(Colors.grey));
    });

    testWidgets('shows "Say wake word or tap mic" text initially (non-web and English only)',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Say wake word or tap mic'), findsOneWidget);
    });

    testWidgets('shows translated "Tap mic to start" text initially - (Spanish)',
        (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Toca el micrófono para comenzar'), findsOneWidget);
    });

    testWidgets('instruction text has fontSize 18', (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      final text = tester.widget<Text>(find.text('Say wake word or tap mic'));
      expect(text.style?.fontSize, equals(18));
    });

    testWidgets('renders FloatingActionButton with mic icon', (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('uses Center and Column layout', (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(Center), findsWidgets);
      expect(find.byType(Column), findsWidgets);
    });
  });

  group('VoiceCommandAI mic button start', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('tapping FAB shows Listening and mic_off on FAB - English',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Listening...'), findsOneWidget);
      expect(find.byIcon(Icons.mic_off), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('tapping FAB shows Listening and mic_off on FAB - Spanish',
        (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Escuchando...'), findsOneWidget);
      expect(find.byIcon(Icons.mic_off), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('large icon turns red when wake-detected', (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      final largeIcon = icons.firstWhere((i) => i.size == 64);
      expect(largeIcon.color, equals(Colors.red));

      await _tearDown(tester);
    });

    testWidgets('tapping FAB calls initialize and listen on speech plugin',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      speechMethodCalls.clear();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      // initialize may be skipped due to singleton, but listen should be called
      expect(speechMethodCalls, contains('listen'));

      await _tearDown(tester);
    });
  });

  group('VoiceCommandAI mic button stop', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('tapping FAB while listening shows error if no speech - English',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('No speech detected.'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('tapping FAB while listening shows error if no speech - Spanish',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('No se detectó ninguna voz.'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('tapping FAB while listening processes buffered text - English',
        (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      // Fill buffer with partial
      await _sendSpeechResult(tester, 'hello there', isFinal: false);

      // Stop => processes buffer (unrecognized)
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Command not recognized \u2014 please try again.'),
          findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('tapping FAB while listening processes buffered text - Spanish',
        (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      // Fill buffer with partial
      await _sendSpeechResult(tester, 'hello there', isFinal: false);

      // Stop => processes buffer (unrecognized)
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Comando no reconocido; inténtelo de nuevo.'),
          findsOneWidget);

      await _tearDown(tester);
    });
  });

  group('VoiceCommandAI speech recognition', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('final result with unrecognized command shows error - English',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'hello world', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Command not recognized \u2014 please try again.'),
          findsOneWidget);
      expect(find.text('Status: Command not recognized'), findsOneWidget);

      await tester.pump(_statusSettleDelay);
      expect(find.text('Say wake word or tap mic'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('final result with unrecognized command shows error - Spanish', (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'hello world', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(
          find.text('Comando no reconocido; inténtelo de nuevo.'),
          findsOneWidget);
      expect(find.text('Estado: Comando no reconocido'), findsOneWidget);

      await tester.pump(_statusSettleDelay);
      expect(find.text('Toca el micrófono para comenzar'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('partial result does not trigger processing - English',
        (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me', isFinal: false);

      expect(find.text('Listening...'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('partial result does not trigger processing - Spanish',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me', isFinal: false);

      expect(find.text('Escuchando...'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('final result with empty words falls back to buffer - English',
        (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'something unknown', isFinal: false);
      await _sendSpeechResult(tester, '', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Command not recognized \u2014 please try again.'),
          findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('final result with empty words falls back to buffer - Spanish',
        (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'something unknown', isFinal: false);
      await _sendSpeechResult(tester, '', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Comando no reconocido; inténtelo de nuevo.'),
          findsOneWidget);

      await _tearDown(tester);
    });
  });

  group('VoiceCommandAI navigation commands', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('"take me home" enters confirming then navigates on confirm',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me home', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Status: Confirm command'), findsOneWidget);
      expect(find.byKey(const Key('voice_confirm_btn')), findsOneWidget);

      await tester.tap(find.byKey(const Key('voice_confirm_btn')));
      await tester.pump();
      await tester.pump();

      expect(find.text('Dashboard Page'), findsOneWidget);

      await _flush(tester);
    });

    testWidgets('"take me to calendar" confirms then navigates to /calendar',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me to calendar', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('voice_confirm_btn')));
      await tester.pump();
      await tester.pump();

      expect(find.text('Calendar Page'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('"take me to my tracker" confirms then navigates to /symptoms',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me to my tracker', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('voice_confirm_btn')));
      await tester.pump();
      await tester.pump();

      expect(find.text('Symptoms Page'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('commands are case-insensitive', (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'TAKE ME TO CALENDAR', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('voice_confirm_btn')));
      await tester.pump();
      await tester.pump();

      expect(find.text('Calendar Page'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('command with extra words matches via contains',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(
          tester, 'please take me to my tracker now', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('voice_confirm_btn')));
      await tester.pump();
      await tester.pump();

      expect(find.text('Symptoms Page'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('unrecognized command shows error snackbar - English', (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'do something random', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Command not recognized \u2014 please try again.'),
          findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('unrecognized command shows error snackbar - Spanish', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'do something random', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Comando no reconocido; inténtelo de nuevo.'),
          findsOneWidget);

      await _tearDown(tester);
    });
  });

  group('VoiceCommandAI singleShot mode', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    // TC-M3-VOICE-001
    testWidgets('singleShot returns simulated recognized text to its caller',
        (tester) async {
      String? poppedResult;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                poppedResult = await Navigator.of(ctx).push<String>(
                  MaterialPageRoute(
                    builder: (_) => const VoiceCommandAI(singleShot: true),
                  ),
                );
              },
              child: const Text('Open Voice'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Voice'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'call my doctor', isFinal: true);
      await tester.pump(const Duration(milliseconds: 200));

      // Pop animation
      await _flush(tester);

      expect(poppedResult, equals('call my doctor'));

      await _flush(tester);
    });

    testWidgets('singleShot pops even for navigation-like words',
        (tester) async {
      String? poppedResult;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                poppedResult = await Navigator.of(ctx).push<String>(
                  MaterialPageRoute(
                    builder: (_) => const VoiceCommandAI(singleShot: true),
                  ),
                );
              },
              child: const Text('Open Voice'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Voice'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me home', isFinal: true);
      await tester.pump(const Duration(milliseconds: 200));

      await _flush(tester);

      expect(poppedResult, equals('take me home'));

      await _flush(tester);
    });
  });

  group('VoiceCommandAI timeout', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('timeout with no speech shows "Listening timed out." - English',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Listening...'), findsOneWidget);

      // Advance past the 12-second timeout and error display delay
      await tester.pump(const Duration(seconds: 13));
      await tester.pump(_statusSettleDelay);

      expect(find.text('Listening timed out.'), findsOneWidget);
      expect(find.text('Say wake word or tap mic'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('timeout with no speech shows "Listening timed out." - Spanish',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Escuchando...'), findsOneWidget);

      // Advance past the 12-second timeout and error display delay
      await tester.pump(const Duration(seconds: 13));
      await tester.pump(_statusSettleDelay);

      expect(find.text('La escucha ha expirado.'), findsOneWidget);
      expect(find.text('Toca el micrófono para comenzar'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('timeout with buffered text processes it - English', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'some unknown command', isFinal: false);

      await tester.pump(const Duration(seconds: 13));

      expect(find.text('Command not recognized \u2014 please try again.'),
          findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('timeout with buffered text processes it - Spanish', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'some unknown command', isFinal: false);

      await tester.pump(const Duration(seconds: 13));

      expect(find.text('Comando no reconocido; inténtelo de nuevo.'),
          findsOneWidget);

      await _tearDown(tester);
    });
  });

  group('VoiceCommandAI permission denied', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('shows error when microphone permission denied - English',
        (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugin.csdcorp.com/speech_to_text'),
        (call) async {
          if (call.method == 'has_permission') return false;
          if (call.method == 'initialize') return true;
          if (call.method == 'stop') return null;
          if (call.method == 'cancel') return null;
          return null;
        },
      );

      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Microphone permission denied'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('shows error when microphone permission denied - Spanish',
        (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugin.csdcorp.com/speech_to_text'),
        (call) async {
          if (call.method == 'has_permission') return false;
          if (call.method == 'initialize') return true;
          if (call.method == 'stop') return null;
          if (call.method == 'cancel') return null;
          return null;
        },
      );

      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Permiso de micrófono denegado'), findsOneWidget);

      await _tearDown(tester);
    });
  });

  group('VoiceCommandAI dispose', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('disposes cleanly while listening', (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _tearDown(tester);
      expect(true, isTrue);
    });

    testWidgets('disposes cleanly when not listening', (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await _tearDown(tester);
      expect(true, isTrue);
    });
  });

  group('VoiceCommandAI reset', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('after processing, widget returns to initial state - English',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'random words', isFinal: true);
      await tester.pump(_statusSettleDelay);

      expect(find.byIcon(Icons.mic_none), findsOneWidget);
      expect(find.text('Say wake word or tap mic'), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('after processing, widget returns to initial state - Spanish',
        (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'random words', isFinal: true);
      await tester.pump(_statusSettleDelay);

      expect(find.byIcon(Icons.mic_none), findsOneWidget);
      expect(find.text('Toca el micrófono para comenzar'), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('stop is called on speech plugin during reset', (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      speechMethodCalls.clear();

      await _sendSpeechResult(tester, 'random words', isFinal: true);
      await tester.pump(_statusSettleDelay);

      expect(speechMethodCalls, contains('stop'));

      await _tearDown(tester);
    });
  });

  group('VoiceCommandAI processing state', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('shows Processing when wakeDetected but not yet listening - English',
        (tester) async {
      final completer = Completer<bool>();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugin.csdcorp.com/speech_to_text'),
        (call) async {
          if (call.method == 'has_permission') return completer.future;
          if (call.method == 'initialize') return true;
          if (call.method == 'stop') return null;
          if (call.method == 'cancel') return null;
          if (call.method == 'listen') return true;
          return null;
        },
      );

      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      // Tap FAB — sets wakeDetected=true then awaits hasPermission
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();

      // wakeDetected=true, isListening=false => "Processing..."
      expect(find.text('Processing...'), findsOneWidget);

      // Complete
      completer.complete(true);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Listening...'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('shows Processing when wakeDetected but not yet listening - Spanish',
        (tester) async {
      final completer = Completer<bool>();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugin.csdcorp.com/speech_to_text'),
        (call) async {
          if (call.method == 'has_permission') return completer.future;
          if (call.method == 'initialize') return true;
          if (call.method == 'stop') return null;
          if (call.method == 'cancel') return null;
          if (call.method == 'listen') return true;
          return null;
        },
      );

      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      // Tap FAB — sets wakeDetected=true then awaits hasPermission
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();

      // wakeDetected=true, isListening=false => "Processing..."
      expect(find.text('Procesando...'), findsOneWidget);

      // Complete
      completer.complete(true);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Escuchando...'), findsOneWidget);

      await _tearDown(tester);
    });
  });

  group('VoiceCommandAI multiple interactions', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('can start listening again after reset - English', (tester) async {
      await tester.pumpWidget(const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      // Start
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Listening...'), findsOneWidget);

      // Stop (no speech)
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      // Flush timers
      await _flush(tester);

      // Start again
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Listening...'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('can start listening again after reset - Spanish', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      // Start
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Escuchando...'), findsOneWidget);

      // Stop (no speech)
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      // Flush timers
      await _flush(tester);

      // Start again
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Escuchando...'), findsOneWidget);

      await _tearDown(tester);
    });
  });

  group('VoiceCommandAI status feedback', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    // TC-S1-VC-001
    testWidgets('recognized navigate command shows heard text and confirm status - English',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me to calendar', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Status: Confirm command'), findsOneWidget);
      expect(find.text('Heard: "take me to calendar"'), findsOneWidget);
      expect(
        find.text('Recognized: "take me to calendar" \u2014 open Calendar?'),
        findsOneWidget,
      );

      await _tearDown(tester);
    });

    testWidgets('recognized navigate command shows heard text and confirm status - Spanish',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp(localestring: 'es'));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'vaya al calendario', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Estado: Confirmar comando'), findsOneWidget);
      expect(find.text('Escuchó: "vaya al calendario"'), findsOneWidget);
      expect(
        find.text('Reconocido: "vaya al calendario" — ¿abrir el Calendario?'),
        findsOneWidget,
      );

      await _tearDown(tester);
    });

    // TC-S1-VC-002
    testWidgets('unknown command shows heard text and fallback status - English',
        (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'do something random', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Status: Command not recognized'), findsOneWidget);
      expect(find.text('Heard: "do something random"'), findsOneWidget);
      expect(
        find.text('Recognized: "do something random" — command not recognized'),
        findsOneWidget,
      );
      expect(find.text('Command not recognized \u2014 please try again.'),
          findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('unknown command shows heard text and fallback status - Spanish',
        (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'do something random', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Estado: Comando no reconocido'), findsOneWidget);
      expect(find.text('Escuchó: "do something random"'), findsOneWidget);
      expect(
        find.text(
            'Reconocido: "do something random" — comando no reconocido'),
        findsOneWidget,
      );
      expect(find.text('Comando no reconocido; inténtelo de nuevo.'),
          findsOneWidget);

      await _tearDown(tester);
    });

    // TC-S1-VC-003
    testWidgets('timeout with no speech shows error status - English', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      var sawErrorStatus = false;
      for (var i = 0; i < 140; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Status: Error').evaluate().isNotEmpty) {
          sawErrorStatus = true;
          break;
        }
      }

      expect(sawErrorStatus, isTrue);
      expect(find.text('Listening timed out.'), findsOneWidget);
      expect(find.text('Tap the microphone to try again.'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('timeout with no speech shows error status - Spanish', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      var sawErrorStatus = false;
      for (var i = 0; i < 140; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Estado: Error').evaluate().isNotEmpty) {
          sawErrorStatus = true;
          break;
        }
      }

      expect(sawErrorStatus, isTrue);
      expect(find.text('La escucha ha expirado.'), findsOneWidget);
      expect(find.text('Toque el micrófono para intentar de nuevo.'), findsOneWidget);

      await _tearDown(tester);
    });

    // TC-S1-VC-004
    testWidgets('timeout with buffered text shows fallback status - English',
        (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'some unknown command', isFinal: false);

      var sawFallbackStatus = false;
      for (var i = 0; i < 140; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Status: Command not recognized').evaluate().isNotEmpty) {
          sawFallbackStatus = true;
          break;
        }
      }

      expect(sawFallbackStatus, isTrue);
      expect(find.text('Heard: "some unknown command"'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('timeout with buffered text shows fallback status - Spanish',
        (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'some unknown command', isFinal: false);

      var sawFallbackStatus = false;
      for (var i = 0; i < 140; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Estado: Comando no reconocido').evaluate().isNotEmpty) {
          sawFallbackStatus = true;
          break;
        }
      }

      expect(sawFallbackStatus, isTrue);
      expect(find.text('Escuchó: "some unknown command"'), findsOneWidget);

      await _tearDown(tester);
    });

    // TC-S1-VC-005
    testWidgets('singleShot pops caller with recognized words and shows status',
        (tester) async {
      String? poppedResult;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                poppedResult = await Navigator.of(ctx).push<String>(
                  MaterialPageRoute(
                    builder: (_) => const VoiceCommandAI(singleShot: true),
                  ),
                );
              },
              child: const Text('Open Voice'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Voice'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'call my doctor', isFinal: true);
      await tester.pump();

      expect(find.text('Status: Captured'), findsOneWidget);
      expect(find.text('Heard: "call my doctor"'), findsOneWidget);
      expect(find.text('Speech captured: "call my doctor"'), findsOneWidget);

      await tester.pump(_statusSettleDelay);

      expect(poppedResult, equals('call my doctor'));

      await _flush(tester);
    });

    // TC-S1-VC-006
    testWidgets('partial STT result updates heard text while listening - English',
        (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me', isFinal: false);

      expect(find.text('Status: Listening'), findsOneWidget);
      expect(find.text('Heard: "take me"'), findsOneWidget);
      expect(find.text('Listening...'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('partial STT result updates heard text while listening - Spanish',
        (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me', isFinal: false);

      expect(find.text('Estado: Escuchando'), findsOneWidget);
      expect(find.text('Escuchó: "take me"'), findsOneWidget);
      expect(find.text('Escuchando...'), findsOneWidget);

      await _tearDown(tester);
    });

    // TC-S1-VC-007
    testWidgets('after reset, status area returns to idle - English', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('en'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Status: Ready'), findsOneWidget);
      expect(find.byKey(const Key('voice_status_heard')), findsNothing);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'random words', isFinal: true);
      await tester.pump(_statusSettleDelay);
      await tester.pump();

      expect(find.text('Status: Ready'), findsOneWidget);
      expect(find.byKey(const Key('voice_status_heard')), findsNothing);
      expect(find.byKey(const Key('voice_status_detail')), findsNothing);

      await _tearDown(tester);
    });

    testWidgets('after reset, status area returns to idle - Spanish', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, locale: Locale('es'), home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Estado: Listo'), findsOneWidget);
      expect(find.byKey(const Key('voice_status_heard')), findsNothing);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'random words', isFinal: true);
      await tester.pump(_statusSettleDelay);
      await tester.pump();

      expect(find.text('Estado: Listo'), findsOneWidget);
      expect(find.byKey(const Key('voice_status_heard')), findsNothing);
      expect(find.byKey(const Key('voice_status_detail')), findsNothing);

      await _tearDown(tester);
    });
  });

  // ──────────── T11 confirmation and clarification tests ────────────

  group('VoiceCommandAI confirmation and clarification', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('"take me home" enters confirming state before navigating - English',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me home', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Status: Confirm command'), findsOneWidget);
      expect(find.text('Heard: "take me home"'), findsOneWidget);
      // Should NOT have navigated yet
      expect(find.text('Dashboard Page'), findsNothing);

      await _tearDown(tester);
    });

    testWidgets('"take me home" enters confirming state before navigating - Spanish',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp(localestring: 'es'));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'vaya a la página de inicio', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Estado: Confirmar comando'), findsOneWidget);
      expect(find.text('Escuchó: "vaya a la página de inicio"'), findsOneWidget);
      // Should NOT have navigated yet
      expect(find.text('Dashboard Page'), findsNothing);

      await _tearDown(tester);
    });

    testWidgets('confirming state shows confirm and cancel buttons - English',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me home', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('voice_confirm_btn')), findsOneWidget);
      expect(find.byKey(const Key('voice_cancel_btn')), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('confirming state shows confirm and cancel buttons - Spanish',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp(localestring: 'es'));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'vaya a la página de inicio', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('voice_confirm_btn')), findsOneWidget);
      expect(find.byKey(const Key('voice_cancel_btn')), findsOneWidget);
      expect(find.text('Confirmar'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('tapping confirm navigates to destination', (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me home', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('voice_confirm_btn')));
      await tester.pump();
      await tester.pump();

      expect(find.text('Dashboard Page'), findsOneWidget);

      await _flush(tester);
    });

    testWidgets('tapping cancel returns to idle without navigation - English',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me home', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('voice_cancel_btn')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Status: Ready'), findsOneWidget);
      expect(find.text('Dashboard Page'), findsNothing);
      expect(find.byKey(const Key('voice_confirm_btn')), findsNothing);

      await _tearDown(tester);
    });

    testWidgets('tapping cancel returns to idle without navigation - Spanish',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp(localestring: 'es'));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'vaya a la página de inicio', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('voice_cancel_btn')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Estado: Listo'), findsOneWidget);
      expect(find.text('Dashboard Page'), findsNothing);
      expect(find.byKey(const Key('voice_confirm_btn')), findsNothing);

      await _tearDown(tester);
    });

    testWidgets('ambiguous input "take me to" enters clarifying state - English',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      // "take me to" matches both "take me to calendar" and "take me to my tracker"
      await _sendSpeechResult(tester, 'take me to', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Status: Clarify command'), findsOneWidget);
      expect(find.text('Multiple matches \u2014 please choose one'),
          findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('ambiguous input "take me to" enters clarifying state - Spanish',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp(localestring: 'es'));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      // "take me to" matches both "take me to calendar" and "take me to my tracker"
      await _sendSpeechResult(tester, 'vaya al', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Estado: Aclarar comando'), findsOneWidget);
      expect(find.text('Múltiples coincidencias \u2014 Seleccione una opción'),
          findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('clarifying state shows multiple options and cancel - English',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me to', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Symptom Tracker'), findsOneWidget);
      expect(find.byKey(const Key('voice_clarify_cancel_btn')), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('clarifying state shows multiple options and cancel - Spanish',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp(localestring: 'es'));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'vaya al', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('el Calendario'), findsOneWidget);
      expect(find.text('el Rastreador de Síntomas'), findsOneWidget);
      expect(find.byKey(const Key('voice_clarify_cancel_btn')), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('selecting an option from clarifying moves to confirming - English',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me to', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('voice_clarify_/calendar')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Status: Confirm command'), findsOneWidget);
      expect(find.byKey(const Key('voice_confirm_btn')), findsOneWidget);
      expect(find.text('Selected: Calendar \u2014 confirm?'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('selecting an option from clarifying moves to confirming - Spanish',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp(localestring: 'es'));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'vaya al', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('voice_clarify_/calendar')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Estado: Confirmar comando'), findsOneWidget);
      expect(find.byKey(const Key('voice_confirm_btn')), findsOneWidget);
      expect(find.text('Seleccionado: el Calendario \u2014 ¿confirmar?'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('canceling clarification returns to idle - English', (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me to', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('voice_clarify_cancel_btn')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Status: Ready'), findsOneWidget);
      expect(find.text('Calendar Page'), findsNothing);
      expect(find.text('Symptoms Page'), findsNothing);

      await _tearDown(tester);
    });

    testWidgets('canceling clarification returns to idle - Spanish', (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp(localestring: 'es'));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'vaya al', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('voice_clarify_cancel_btn')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Estado: Listo'), findsOneWidget);
      expect(find.text('Calendar Page'), findsNothing);
      expect(find.text('Symptoms Page'), findsNothing);

      await _tearDown(tester);
    });

    testWidgets('singleShot mode skips confirmation', (tester) async {
      String? poppedResult;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                poppedResult = await Navigator.of(ctx).push<String>(
                  MaterialPageRoute(
                    builder: (_) => const VoiceCommandAI(singleShot: true),
                  ),
                );
              },
              child: const Text('Open Voice'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Voice'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me home', isFinal: true);
      await tester.pump(const Duration(milliseconds: 200));

      // Should NOT show confirmation — singleShot pops directly
      expect(find.byKey(const Key('voice_confirm_btn')), findsNothing);

      await _flush(tester);

      expect(poppedResult, equals('take me home'));

      await _flush(tester);
    });

    testWidgets('clarify then confirm navigates to chosen destination',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me to', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      // Pick "Symptom Tracker" from clarification
      await tester.tap(find.byKey(const Key('voice_clarify_/symptoms')));
      await tester.pump(const Duration(milliseconds: 100));

      // Now confirm
      await tester.tap(find.byKey(const Key('voice_confirm_btn')));
      await tester.pump();
      await tester.pump();

      expect(find.text('Symptoms Page'), findsOneWidget);

      await _flush(tester);
    });
  });

  // ──────────── T11 confirmation and clarification tests ────────────

  group('VoiceCommandAI confirmation and clarification', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('"take me home" enters confirming state before navigating',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me home', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Status: Confirm command'), findsOneWidget);
      expect(find.text('Heard: "take me home"'), findsOneWidget);
      // Should NOT have navigated yet
      expect(find.text('Dashboard Page'), findsNothing);

      await _tearDown(tester);
    });

    testWidgets('confirming state shows confirm and cancel buttons',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me home', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('voice_confirm_btn')), findsOneWidget);
      expect(find.byKey(const Key('voice_cancel_btn')), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('tapping confirm navigates to destination', (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me home', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('voice_confirm_btn')));
      await tester.pump();
      await tester.pump();

      expect(find.text('Dashboard Page'), findsOneWidget);

      await _flush(tester);
    });

    testWidgets('tapping cancel returns to idle without navigation',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me home', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('voice_cancel_btn')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Status: Ready'), findsOneWidget);
      expect(find.text('Dashboard Page'), findsNothing);
      expect(find.byKey(const Key('voice_confirm_btn')), findsNothing);

      await _tearDown(tester);
    });

    testWidgets('ambiguous input "take me to" enters clarifying state',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      // "take me to" matches both "take me to calendar" and "take me to my tracker"
      await _sendSpeechResult(tester, 'take me to', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Status: Clarify command'), findsOneWidget);
      expect(find.text('Multiple matches \u2014 please choose one'),
          findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('clarifying state shows multiple options and cancel',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me to', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Symptom Tracker'), findsOneWidget);
      expect(find.byKey(const Key('voice_clarify_cancel_btn')), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('selecting an option from clarifying moves to confirming',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me to', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('voice_clarify_/calendar')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Status: Confirm command'), findsOneWidget);
      expect(find.byKey(const Key('voice_confirm_btn')), findsOneWidget);
      expect(find.text('Selected: Calendar \u2014 confirm?'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('canceling clarification returns to idle', (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me to', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('voice_clarify_cancel_btn')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Status: Ready'), findsOneWidget);
      expect(find.text('Calendar Page'), findsNothing);
      expect(find.text('Symptoms Page'), findsNothing);

      await _tearDown(tester);
    });

    testWidgets('singleShot mode skips confirmation', (tester) async {
      String? poppedResult;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                poppedResult = await Navigator.of(ctx).push<String>(
                  MaterialPageRoute(
                    builder: (_) => const VoiceCommandAI(singleShot: true),
                  ),
                );
              },
              child: const Text('Open Voice'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Voice'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me home', isFinal: true);
      await tester.pump(const Duration(milliseconds: 200));

      // Should NOT show confirmation — singleShot pops directly
      expect(find.byKey(const Key('voice_confirm_btn')), findsNothing);

      await _flush(tester);

      expect(poppedResult, equals('take me home'));

      await _flush(tester);
    });

    testWidgets('clarify then confirm navigates to chosen destination',
        (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me to', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      // Pick "Symptom Tracker" from clarification
      await tester.tap(find.byKey(const Key('voice_clarify_/symptoms')));
      await tester.pump(const Duration(milliseconds: 100));

      // Now confirm
      await tester.tap(find.byKey(const Key('voice_confirm_btn')));
      await tester.pump();
      await tester.pump();

      expect(find.text('Symptoms Page'), findsOneWidget);

      await _flush(tester);
    });
  });

  // ──────────── T16 hardening: failure, timeout, and fallback tests ────────────

  group('VoiceCommandAI T16 fallback guidance', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('permission denied shows guidance in status detail - English',
        (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugin.csdcorp.com/speech_to_text'),
        (call) async {
          if (call.method == 'has_permission') return false;
          if (call.method == 'initialize') return true;
          if (call.method == 'stop') return null;
          if (call.method == 'cancel') return null;
          return null;
        },
      );

      await tester.pumpWidget(const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Microphone permission denied'), findsOneWidget);
      expect(find.text('Status: Error'), findsOneWidget);
      expect(
        find.text('Enable microphone in device settings or use manual navigation.'),
        findsOneWidget,
      );

      await _tearDown(tester);
    });

    testWidgets('permission denied shows guidance in status detail - Spanish',
        (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugin.csdcorp.com/speech_to_text'),
        (call) async {
          if (call.method == 'has_permission') return false;
          if (call.method == 'initialize') return true;
          if (call.method == 'stop') return null;
          if (call.method == 'cancel') return null;
          return null;
        },
      );

      await tester.pumpWidget(const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('es'),
          home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Permiso de micrófono denegado'), findsOneWidget);
      expect(find.text('Estado: Error'), findsOneWidget);
      expect(
        find.text('Habilite el micrófono en la configuración del dispositivo o use la navegación manual.'),
        findsOneWidget,
      );

      await _tearDown(tester);
    });

    testWidgets('timeout shows guidance in status detail - English',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.pump(const Duration(seconds: 13));

      expect(find.text('Listening timed out.'), findsWidgets);
      expect(
        find.text('Tap the microphone to try again.'),
        findsOneWidget,
      );

      await _tearDown(tester);
    });

    testWidgets('timeout shows guidance in status detail - Spanish',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('es'),
          home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.pump(const Duration(seconds: 13));

      expect(find.text('La escucha ha expirado.'), findsWidgets);
      expect(
        find.text('Toque el micrófono para intentar de nuevo.'),
        findsOneWidget,
      );

      await _tearDown(tester);
    });

    testWidgets('no speech on mic stop shows guidance in status detail - English',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('No speech detected.'), findsOneWidget);
      expect(
        find.text('No speech heard. Tap the microphone to try again.'),
        findsOneWidget,
      );

      await _tearDown(tester);
    });

    testWidgets('no speech on mic stop shows guidance in status detail - Spanish',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('es'),
          home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('No se detectó ninguna voz.'), findsOneWidget);
      expect(
        find.text('No se detectó voz. Toque el micrófono para intentar de nuevo.'),
        findsOneWidget,
      );

      await _tearDown(tester);
    });
  });

  group('VoiceCommandAI T16 retry after failure', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('can retry listening after timeout - English', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      // Wait for timeout
      await tester.pump(const Duration(seconds: 13));
      await tester.pump(_statusSettleDelay);

      // Should be back to idle
      expect(find.text('Status: Ready'), findsOneWidget);

      // Retry
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Listening...'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('can retry listening after no speech detected - English',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      // Start listening
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      // Stop with no speech
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      // Wait for reset
      await tester.pump(_statusSettleDelay);

      // Should be back to idle
      expect(find.text('Status: Ready'), findsOneWidget);

      // Retry
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Listening...'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('can retry listening after unknown command - English',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'unknown phrase', isFinal: true);
      await tester.pump(_statusSettleDelay);

      // Should be back to idle
      expect(find.text('Status: Ready'), findsOneWidget);

      // Retry
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Listening...'), findsOneWidget);

      await _tearDown(tester);
    });
  });

  group('VoiceCommandAI T16 no stuck states', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('unknown command does not leave UI in processing state',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'gibberish words', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      // Should be in fallback, not stuck in processing
      expect(find.text('Status: Command not recognized'), findsOneWidget);
      expect(find.text('Status: Processing'), findsNothing);

      // After delay, resets to idle
      await tester.pump(_statusSettleDelay);
      expect(find.text('Status: Ready'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('mic button ignored while in confirming state', (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me home', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Status: Confirm command'), findsOneWidget);

      // Tap mic while in confirming state — should be ignored
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      // Still in confirming state, not listening
      expect(find.text('Status: Confirm command'), findsOneWidget);
      expect(find.text('Listening...'), findsNothing);

      await _tearDown(tester);
    });

    testWidgets('mic button ignored while in clarifying state', (tester) async {
      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me to', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Status: Clarify command'), findsOneWidget);

      // Tap mic while in clarifying state — should be ignored
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      // Still in clarifying state, not listening
      expect(find.text('Status: Clarify command'), findsOneWidget);
      expect(find.text('Listening...'), findsNothing);

      await _tearDown(tester);
    });

    testWidgets('timeout resets to idle with usable mic button', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      // Timeout fires
      await tester.pump(const Duration(seconds: 13));
      await tester.pump(_statusSettleDelay);

      // Confirm UI is in idle state
      expect(find.text('Status: Ready'), findsOneWidget);
      expect(find.byIcon(Icons.mic_none), findsOneWidget);

      // FAB shows mic icon (not mic_off)
      final fab = tester.widget<FloatingActionButton>(
          find.byType(FloatingActionButton));
      final fabIcon = fab.child as Icon;
      expect(fabIcon.icon, equals(Icons.mic));

      await _tearDown(tester);
    });
  });

  group('VoiceCommandAI AI intent extraction', () {
    setUp(setupDefaultMocks);

    testWidgets('AI navigate intent enters confirming state', (tester) async {
      VoiceIntentService.testOverride = ({
        required String utterance,
        String locale = 'en',
        String? screenId,
      }) {
        return VoiceIntentResult(
          intent: 'navigate',
          entities: {'destination': 'calendar'},
          confidence: 0.95,
          destination: '/calendar',
          displayLabel: 'Navigate to calendar',
          requiresConfirmation: true,
          success: true,
        );
      };

      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'show me the calendar');
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('Navigate to calendar'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      VoiceIntentService.testOverride = null;
      await _tearDown(tester);
    });

    testWidgets('AI navigate confirm navigates to destination', (tester) async {
      VoiceIntentService.testOverride = ({
        required String utterance,
        String locale = 'en',
        String? screenId,
      }) {
        return VoiceIntentResult(
          intent: 'navigate',
          entities: {'destination': 'calendar'},
          confidence: 0.95,
          destination: '/calendar',
          displayLabel: 'Navigate to calendar',
          requiresConfirmation: true,
          success: true,
        );
      };

      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'show me the calendar');
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('voice_confirm_btn')));
      await tester.pump();
      await tester.pump();

      expect(find.text('Calendar Page'), findsOneWidget);

      VoiceIntentService.testOverride = null;
      await _flush(tester);
    });

    testWidgets('AI call intent shows confirming then not yet supported', (tester) async {
      VoiceIntentService.testOverride = ({
        required String utterance,
        String locale = 'en',
        String? screenId,
      }) {
        return VoiceIntentResult(
          intent: 'call',
          entities: {'target': 'Dr. Smith'},
          confidence: 0.88,
          displayLabel: 'Call Dr. Smith',
          requiresConfirmation: true,
          success: true,
        );
      };

      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'call Dr. Smith');
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('Call Dr. Smith'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('not yet available'), findsOneWidget);

      VoiceIntentService.testOverride = null;
      await _tearDown(tester);
    });

    testWidgets('AI service returns null falls back to keyword matching', (tester) async {
      VoiceIntentService.testOverride = ({
        required String utterance,
        String locale = 'en',
        String? screenId,
      }) {
        return null;
      };

      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me home');
      await tester.pump(const Duration(milliseconds: 200));

      // Keyword match should fire - confirming state with "Home"
      expect(find.textContaining('Home'), findsWidgets);
      expect(find.text('Confirm'), findsOneWidget);

      VoiceIntentService.testOverride = null;
      await _tearDown(tester);
    });

    testWidgets('AI returns unknown intent falls back to keyword matching', (tester) async {
      VoiceIntentService.testOverride = ({
        required String utterance,
        String locale = 'en',
        String? screenId,
      }) {
        return VoiceIntentResult(
          intent: 'unknown',
          confidence: 0.1,
          success: false,
        );
      };

      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me to calendar');
      await tester.pump(const Duration(milliseconds: 200));

      // Keyword match should fire - confirming state with "Calendar"
      expect(find.textContaining('Calendar'), findsWidgets);
      expect(find.text('Confirm'), findsOneWidget);

      VoiceIntentService.testOverride = null;
      await _tearDown(tester);
    });

    testWidgets('AI cancel returns to idle', (tester) async {
      VoiceIntentService.testOverride = ({
        required String utterance,
        String locale = 'en',
        String? screenId,
      }) {
        return VoiceIntentResult(
          intent: 'schedule',
          entities: {'target': 'dentist'},
          confidence: 0.85,
          displayLabel: 'Schedule with dentist',
          requiresConfirmation: true,
          success: true,
        );
      };

      await tester.pumpWidget(_buildVoiceRouterApp());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'schedule dentist');
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('Schedule with dentist'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump(_statusSettleDelay);

      expect(find.text('Status: Ready'), findsOneWidget);

      VoiceIntentService.testOverride = null;
      await _tearDown(tester);
    });
  });
}
