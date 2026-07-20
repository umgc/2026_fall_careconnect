// Tests for SymptomInputForm widget
// (lib/features/health/symptom-tracker/widgets/symptom_input_form.dart)
// StatefulWidget with no API calls in initState — render tests are safe.
// API calls only happen in button onPressed handlers.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/ai/presentation/pages/voice_command_ai.dart';
import 'package:care_connect_app/features/health/symptom-tracker/widgets/symptom_input_form.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Widget _form({String patientId = '42'}) =>
    _wrap(SymptomInputForm(patientId: patientId));

void main() {
  group('SymptomInputForm', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_form());
      expect(find.byType(SymptomInputForm), findsOneWidget);
    });

    testWidgets('shows Record Mental Health Symptom title', (tester) async {
      await tester.pumpWidget(_form());
      expect(find.text('Record Mental Health Symptom'), findsOneWidget);
    });

    testWidgets('shows Mental Health Symptom field label', (tester) async {
      await tester.pumpWidget(_form());
      expect(find.text('Mental Health Symptom'), findsOneWidget);
    });

    testWidgets('shows Severity label', (tester) async {
      await tester.pumpWidget(_form());
      expect(find.text('Severity'), findsOneWidget);
    });

    testWidgets('shows Clinical Notes label', (tester) async {
      await tester.pumpWidget(_form());
      expect(find.text('Clinical Notes'), findsOneWidget);
    });

    testWidgets('shows Use AI Voice button', (tester) async {
      await tester.pumpWidget(_form());
      expect(find.text('Use AI Voice'), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    // TC-M3-SYM-VOICE-001
    testWidgets('voice handoff consumes the returned transcript',
        (tester) async {
      await tester.pumpWidget(_form());

      await tester.tap(find.text('Use AI Voice'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final voicePage = tester.widget<VoiceCommandAI>(
        find.byType(VoiceCommandAI),
      );
      expect(voicePage.singleShot, isTrue);

      Navigator.of(tester.element(find.byType(VoiceCommandAI))).pop(
        '  persistent headache  ',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('persistent headache'), findsOneWidget);
    });

    testWidgets('shows Use AI Service button', (tester) async {
      await tester.pumpWidget(_form());
      expect(find.text('Use AI Service'), findsOneWidget);
      expect(find.byIcon(Icons.smart_toy), findsOneWidget);
    });

    testWidgets('shows Record Symptom submit button', (tester) async {
      await tester.pumpWidget(_form());
      expect(find.text('Record Symptom'), findsOneWidget);
    });

    testWidgets('shows symptom text field with hint', (tester) async {
      await tester.pumpWidget(_form());
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              (w.decoration?.hintText?.contains('Suicidal thoughts') ?? false),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows Severity dropdown with Mild default', (tester) async {
      await tester.pumpWidget(_form());
      // The dropdown initially shows "Mild"
      expect(find.text('Mild'), findsOneWidget);
    });

    testWidgets('shows Moderate and Severe in severity dropdown options',
        (tester) async {
      await tester.pumpWidget(_form());
      // Open the severity dropdown
      await tester.tap(find.text('Mild'));
      await tester.pumpAndSettle();
      expect(find.text('Moderate'), findsOneWidget);
      expect(find.text('Severe'), findsOneWidget);
    });

    testWidgets('shows clinical notes text field with hint', (tester) async {
      await tester.pumpWidget(_form());
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              (w.decoration?.hintText?.contains('onset, duration') ?? false),
        ),
        findsOneWidget,
      );
    });

    testWidgets('typing in symptom field updates the text', (tester) async {
      await tester.pumpWidget(_form());
      final symptomField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.hintText?.contains('Suicidal thoughts') ?? false),
      );
      await tester.enterText(symptomField, 'Anxiety attack');
      expect(find.text('Anxiety attack'), findsOneWidget);
    });

    testWidgets('Record Symptom button has add icon when not saving',
        (tester) async {
      await tester.pumpWidget(_form());
      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });
}
