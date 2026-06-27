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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/ai/presentation/pages/voice_command_ai.dart';

/// Sends a speech recognition result via the method channel (platform -> Dart).
Future<void> _sendSpeechResult(
  WidgetTester tester,
  String words, {
  bool isFinal = true,
}) async {
  final resultJson = jsonEncode({
    'finalResult': isFinal,
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

    testWidgets('shows error when speech recognition not available',
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

      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Speech recognition not available'), findsOneWidget);

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
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Voice Commands'), findsOneWidget);
      expect(find.byIcon(Icons.mic_none), findsOneWidget);
      expect(find.text('Say wake word or tap mic'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('renders Scaffold with AppBar titled Voice Commands',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Voice Commands'), findsOneWidget);
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('AppBar has blue shade 900 background', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, equals(Colors.blue.shade900));
    });

    testWidgets('renders mic_none icon initially (not wake-detected)',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.mic_none), findsOneWidget);
    });

    testWidgets('initial icon is grey and size 64', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      final icon = tester.widget<Icon>(find.byIcon(Icons.mic_none));
      expect(icon.size, equals(64));
      expect(icon.color, equals(Colors.grey));
    });

    testWidgets('shows "Say wake word or tap mic" text initially (non-web)',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Say wake word or tap mic'), findsOneWidget);
    });

    testWidgets('instruction text has fontSize 18', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      final text = tester.widget<Text>(find.text('Say wake word or tap mic'));
      expect(text.style?.fontSize, equals(18));
    });

    testWidgets('renders FloatingActionButton with mic icon', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('uses Center and Column layout', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(Center), findsWidgets);
      expect(find.byType(Column), findsOneWidget);
    });
  });

  group('VoiceCommandAI mic button start', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('tapping FAB shows Listening and mic_off on FAB',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Listening...'), findsOneWidget);
      expect(find.byIcon(Icons.mic_off), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('large icon turns red when wake-detected', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
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
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
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

    testWidgets('tapping FAB while listening shows error if no speech',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('No speech detected.'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('tapping FAB while listening processes buffered text',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
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
  });

  group('VoiceCommandAI speech recognition', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('final result with unrecognized command shows error',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'hello world', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Command not recognized \u2014 please try again.'),
          findsOneWidget);
      expect(find.text('Say wake word or tap mic'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('partial result does not trigger processing', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me', isFinal: false);

      expect(find.text('Listening...'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('final result with empty words falls back to buffer',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
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
  });

  group('VoiceCommandAI navigation commands', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('"take me home" navigates via pushNamedAndRemoveUntil',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        initialRoute: '/voice',
        routes: {
          '/': (context) => const Scaffold(body: Text('Home Page')),
          '/voice': (context) => const VoiceCommandAI(),
        },
      ));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me home', isFinal: true);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Home Page'), findsOneWidget);

      await _flush(tester);
    });

    testWidgets('"take me to calendar" navigates to /telehealth',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: const VoiceCommandAI(),
        routes: {
          '/telehealth': (context) =>
              const Scaffold(body: Text('Telehealth Page')),
        },
      ));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me to calendar', isFinal: true);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Telehealth Page'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('"take me to my tracker" navigates to /symptomTracker',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: const VoiceCommandAI(),
        routes: {
          '/symptomTracker': (context) =>
              const Scaffold(body: Text('Symptom Tracker Page')),
        },
      ));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'take me to my tracker', isFinal: true);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Symptom Tracker Page'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('commands are case-insensitive', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: const VoiceCommandAI(),
        routes: {
          '/telehealth': (context) =>
              const Scaffold(body: Text('Telehealth Page')),
        },
      ));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'TAKE ME TO CALENDAR', isFinal: true);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Telehealth Page'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('command with extra words matches via contains',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: const VoiceCommandAI(),
        routes: {
          '/symptomTracker': (context) =>
              const Scaffold(body: Text('Tracker Page')),
        },
      ));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'please take me to my tracker now',
          isFinal: true);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Tracker Page'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('unrecognized command shows error snackbar', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'do something random', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Command not recognized \u2014 please try again.'),
          findsOneWidget);

      await _tearDown(tester);
    });
  });

  group('VoiceCommandAI singleShot mode', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('final result pops navigator with recognized words',
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

    testWidgets('timeout with no speech shows "Listening timed out."',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Listening...'), findsOneWidget);

      // Advance past the 12-second timeout
      await tester.pump(const Duration(seconds: 13));

      expect(find.text('Listening timed out.'), findsOneWidget);
      expect(find.text('Say wake word or tap mic'), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('timeout with buffered text processes it', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'some unknown command', isFinal: false);

      await tester.pump(const Duration(seconds: 13));

      expect(find.text('Command not recognized \u2014 please try again.'),
          findsOneWidget);

      await _tearDown(tester);
    });
  });

  group('VoiceCommandAI permission denied', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('shows error when microphone permission denied',
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

      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Microphone permission denied'), findsOneWidget);

      await _tearDown(tester);
    });
  });

  group('VoiceCommandAI dispose', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('disposes cleanly while listening', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _tearDown(tester);
      expect(true, isTrue);
    });

    testWidgets('disposes cleanly when not listening', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await _tearDown(tester);
      expect(true, isTrue);
    });
  });

  group('VoiceCommandAI reset', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('after processing, widget returns to initial state',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      await _sendSpeechResult(tester, 'random words', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.mic_none), findsOneWidget);
      expect(find.text('Say wake word or tap mic'), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsOneWidget);

      await _tearDown(tester);
    });

    testWidgets('stop is called on speech plugin during reset', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      speechMethodCalls.clear();

      await _sendSpeechResult(tester, 'random words', isFinal: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(speechMethodCalls, contains('stop'));

      await _tearDown(tester);
    });
  });

  group('VoiceCommandAI processing state', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('shows Processing when wakeDetected but not yet listening',
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

      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
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
  });

  group('VoiceCommandAI multiple interactions', () {
    setUp(setupDefaultMocks);
    tearDown(clearMocks);

    testWidgets('can start listening again after reset', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: VoiceCommandAI()));
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
  });
}
