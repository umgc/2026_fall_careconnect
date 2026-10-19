import 'dart:convert';

import 'package:care_connect_app/features/ai/presentation/pages/voice_command_ai.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/services/voice_intent_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _speechChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
const _porcupineChannel =
    MethodChannel('flutter.picovoice.ai/porcupine_manager');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    VoiceIntentService.testOverride = ({
      required String utterance,
      String locale = 'en',
      String? screenId,
    }) => null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_porcupineChannel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_speechChannel, (call) async {
      switch (call.method) {
        case 'has_permission':
        case 'initialize':
        case 'listen':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    VoiceIntentService.testOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_porcupineChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_speechChannel, null);
  });

  testWidgets('does not write a recognized voice utterance to debug logs',
      (tester) async {
    final originalDebugPrint = debugPrint;
    final debugMessages = <String>[];
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) debugMessages.add(message);
    };

    try {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const VoiceCommandAI(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      const utterance = 'private care detail';
      final resultJson = jsonEncode({
        'resultType': 2,
        'alternates': [
          {'recognizedWords': utterance, 'confidence': 0.95}
        ],
      });
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        _speechChannel.name,
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall('textRecognition', resultJson)),
        (ByteData? data) {},
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(debugMessages.join('\n'), isNot(contains(utterance)));
    } finally {
      debugPrint = originalDebugPrint;
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
    }
  });
}
