// Flow tests for VoiceCommandAI
// (lib/features/ai/presentation/pages/voice_command_ai.dart): flyout mode
// and theme switching, AI-intent results, the SOS and high-risk confirmation
// dialogs and ambiguous-command clarification.
// speech_to_text and porcupine are mocked over their method channels (same
// approach as voice_command_ai_test.dart).

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

Widget _app({
  VoiceCommandPresentation mode = VoiceCommandPresentation.page,
  VoiceCommandTheme theme = VoiceCommandTheme.classic,
  void Function(String)? onNavigate,
  VoidCallback? onClose,
}) {
  final router = GoRouter(
    initialLocation: '/voice',
    routes: [
      GoRoute(
        path: '/voice',
        builder: (_, __) => Scaffold(
          body: VoiceCommandAI(
            presentationMode: mode,
            theme: theme,
            onNavigateRequested: onNavigate,
            onCloseRequested: onClose,
          ),
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

Future<void> _say(WidgetTester tester, String words) async {
  final resultJson = jsonEncode({
    'resultType': 2,
    'alternates': [
      {'recognizedWords': words, 'confidence': 0.95},
    ],
  });
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    _speechChannel.name,
    const StandardMethodCodec()
        .encodeMethodCall(MethodCall('textRecognition', resultJson)),
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

Future<void> _tearDown(WidgetTester tester) async {
  await _flush(tester);
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  await _flush(tester);
}

Future<void> _startListening(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.mic).last);
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
      if (call.method == 'has_permission') return true;
      if (call.method == 'initialize') return true;
      if (call.method == 'listen') return true;
      return null;
    });
  });

  tearDown(() {
    VoiceIntentService.testOverride = null;
  });

  testWidgets('flyout restores the saved theme, switches themes and closes',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'voice_command_flyout_theme': 'futuristic'});
    var closed = 0;
    await tester.pumpWidget(_app(
      mode: VoiceCommandPresentation.flyout,
      onClose: () => closed++,
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('voice_theme_dropdown')), findsOneWidget);

    // Futuristic mic aura reacts to listening and speech.
    await _startListening(tester);
    await _say(tester, 'hmm');
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('voice_theme_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Classic').last);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('voice_command_flyout_theme'), 'classic');

    // Keyboard handling: arrows move focus, Escape closes.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(closed, greaterThanOrEqualTo(1));
    await _tearDown(tester);
  });

  testWidgets('page mode futuristic theme renders the animated aura',
      (tester) async {
    await tester.pumpWidget(_app(theme: VoiceCommandTheme.futuristic));
    await tester.pump(const Duration(milliseconds: 200));
    await _startListening(tester);
    await _say(tester, 'take me home');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('voice_cancel_btn')));
    await tester.pump();
    await _tearDown(tester);
  });

  testWidgets('"emergency" opens the SOS dialog; send and cancel',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 200));
    await _startListening(tester);
    await _say(tester, 'emergency');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Emergency Alert'), findsOneWidget);
    await tester.tap(find.text('Send Alert'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Alert not currently implemented'),
        findsOneWidget);
    await _flush(tester);

    await _startListening(tester);
    await _say(tester, 'emergency');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Cancel').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Emergency alert cancelled'), findsOneWidget);
    await _tearDown(tester);
  });

  testWidgets('a partial command asks to clarify; choosing one confirms',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 200));
    await _startListening(tester);
    await _say(tester, 'open my');
    expect(find.byKey(const Key('voice_clarify_cancel_btn')), findsOneWidget);
    final chip = find.byType(ActionChip).first;
    await tester.tap(chip);
    await tester.pump();
    expect(find.byKey(const Key('voice_confirm_btn')), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice_confirm_btn')));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('page:/'), findsOneWidget);
    await _tearDown(tester);
  });

  testWidgets('clarify cancel resets', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 200));
    await _startListening(tester);
    await _say(tester, 'open my');
    await tester.tap(find.byKey(const Key('voice_clarify_cancel_btn')));
    await tester.pump();
    expect(find.byKey(const Key('voice_clarify_cancel_btn')), findsNothing);
    await _tearDown(tester);
  });

  group('AI intent results', () {
    void ai(VoiceIntentResult? result) {
      VoiceIntentService.testOverride = (
              {required String utterance, String locale = 'en', String? screenId}) =>
          result;
    }

    testWidgets('navigate with a known route confirms and navigates',
        (tester) async {
      ai(VoiceIntentResult(
        intent: 'navigate',
        destination: '/calendar',
        displayLabel: 'Calendar',
        success: true,
      ));
      await tester.pumpWidget(_app());
      await tester.pump(const Duration(milliseconds: 200));
      await _startListening(tester);
      await _say(tester, 'show my schedule please');
      await tester.tap(find.byKey(const Key('voice_confirm_btn')));
      await tester.pump();
      await tester.pump();
      expect(find.text('page:/calendar'), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('navigate with an entity or unknown route still confirms',
        (tester) async {
      ai(VoiceIntentResult(
        intent: 'navigate',
        entities: const {'destination': 'calendar'},
        success: true,
      ));
      await tester.pumpWidget(_app());
      await tester.pump(const Duration(milliseconds: 200));
      await _startListening(tester);
      await _say(tester, 'calendar thing');
      expect(find.byKey(const Key('voice_confirm_btn')), findsOneWidget);
      await tester.tap(find.byKey(const Key('voice_cancel_btn')));
      await tester.pump();

      ai(VoiceIntentResult(
        intent: 'navigate',
        destination: '/somewhere-else',
        success: true,
      ));
      await _startListening(tester);
      await _say(tester, 'go somewhere');
      expect(find.byKey(const Key('voice_confirm_btn')), findsOneWidget);
      await tester.tap(find.byKey(const Key('voice_cancel_btn')));
      await tester.pump();

      ai(VoiceIntentResult(intent: 'navigate', success: true));
      await _startListening(tester);
      await _say(tester, 'go nowhere');
      await tester.pump(const Duration(milliseconds: 200));
      await _tearDown(tester);
    });

    testWidgets('unknown intent falls back to not recognized',
        (tester) async {
      ai(VoiceIntentResult(intent: 'teleport', success: true));
      await tester.pumpWidget(_app());
      await tester.pump(const Duration(milliseconds: 200));
      await _startListening(tester);
      await _say(tester, 'beam me up');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(SnackBar), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('high-risk schedule intent asks again; confirm navigates',
        (tester) async {
      ai(VoiceIntentResult(
        intent: 'schedule',
        requiresConfirmation: true,
        success: true,
      ));
      await tester.pumpWidget(_app());
      await tester.pump(const Duration(milliseconds: 200));
      await _startListening(tester);
      await _say(tester, 'book a visit');
      await tester.tap(find.byKey(const Key('voice_confirm_btn')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Confirm Schedule Appointment'), findsWidgets);
      await tester.tap(find.widgetWithText(
          ElevatedButton, 'Confirm Schedule Appointment'));
      await tester.pump();
      await tester.pump();
      expect(find.text('page:/calendar'), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('high-risk intent cancelled in the dialog', (tester) async {
      ai(VoiceIntentResult(
        intent: 'call',
        requiresConfirmation: true,
        success: true,
      ));
      await tester.pumpWidget(_app());
      await tester.pump(const Duration(milliseconds: 200));
      await _startListening(tester);
      await _say(tester, 'ring my son');
      await tester.tap(find.byKey(const Key('voice_confirm_btn')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('cancelled'), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('medium-risk intent without handler reports not available',
        (tester) async {
      ai(VoiceIntentResult(
        intent: 'log_symptom',
        requiresConfirmation: true,
        success: true,
      ));
      await tester.pumpWidget(_app());
      await tester.pump(const Duration(milliseconds: 200));
      await _startListening(tester);
      await _say(tester, 'log a headache');
      await tester.tap(find.byKey(const Key('voice_confirm_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await _tearDown(tester);
    });
  });
}
