// Tests for AllergyInputForm
// (lib/features/health/symptom-tracker/widgets/allergies_input_form.dart).
//
// _initApi() called in initState — catches exceptions gracefully, sets _apiReady=false.
// VoiceCommandAI only used in button onPressed (not in build/initState).
// No Provider needed.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/ai/presentation/pages/voice_command_ai.dart';
import 'package:care_connect_app/features/health/symptom-tracker/widgets/allergies_input_form.dart';

Widget _wrap() => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AllergyInputForm(
            patientId: '1',
            onAllergyAdded: (_) {},
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method != 'read') return null;
        final key = (call.arguments as Map<Object?, Object?>)['key'];
        if (key == 'jwt_token') return 'test-jwt';
        if (key == 'token_expiry') return '4102444800';
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  group('AllergyInputForm – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(AllergyInputForm), findsOneWidget);
    });

    testWidgets('shows "Add Drug Allergy" heading', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Add Drug Allergy'), findsWidgets);
    });

    testWidgets('shows Drug/Medication label', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Drug/Medication'), findsOneWidget);
    });

    testWidgets('shows Allergic Reaction label', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Allergic Reaction'), findsOneWidget);
    });

    testWidgets('shows Severity label', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Severity'), findsOneWidget);
    });

    testWidgets('shows Use AI Voice button', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Use AI Voice'), findsOneWidget);
    });

    // TC-M3-ALG-VOICE-001
    testWidgets('voice handoff consumes the returned transcript',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      await tester.tap(find.text('Use AI Voice'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final voicePage = tester.widget<VoiceCommandAI>(
        find.byType(VoiceCommandAI),
      );
      expect(voicePage.singleShot, isTrue);

      Navigator.of(tester.element(find.byType(VoiceCommandAI))).pop(
        '  hives and facial swelling  ',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('hives and facial swelling'), findsOneWidget);
    });

    testWidgets('shows severity dropdown with default "Mild" value',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Mild (Minor symptoms)'), findsOneWidget);
    });

    testWidgets('shows TextField widgets for drug and reaction',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('shows mic icon for AI Voice button', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('shows Add Drug Allergy submit button', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(
        find.byWidgetPredicate((widget) => widget is ElevatedButton),
        findsOneWidget,
      );
    });
  });

  group('AllergyInputForm – text input', () {
    testWidgets('can enter drug name', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      final drugField = find.byType(TextField).first;
      await tester.enterText(drugField, 'Penicillin');
      expect(find.text('Penicillin'), findsOneWidget);
    });

    testWidgets('can enter reaction description', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      final reactionField = find.byType(TextField).at(1);
      await tester.enterText(reactionField, 'Rash and swelling');
      expect(find.text('Rash and swelling'), findsOneWidget);
    });
  });
}
