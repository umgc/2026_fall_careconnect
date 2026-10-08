// Tests for SymptomCard widget
// (lib/features/health/symptom-tracker/widgets/symptom_card.dart).
// Pure StatelessWidget — no platform channels or network I/O.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/symptom-tracker/widgets/symptom_card.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  group('SymptomCard', () {
    testWidgets('renders without crashing', (tester) async {
      // Verifies the widget builds without error.
      await tester.pumpWidget(_wrap(
        SymptomCard(
          title: 'Headache',
          severity: 'mild',
          time: '10:00 AM',
          description: 'Dull pain behind the eyes.',
          requiresAttention: false,
          caregiverAlert: false,
          onDelete: () {},
        ),
      ));
      expect(find.byType(SymptomCard), findsOneWidget);
    });

    testWidgets('shows the symptom title', (tester) async {
      // Verifies the title text is displayed.
      await tester.pumpWidget(_wrap(
        SymptomCard(
          title: 'Nausea',
          severity: 'moderate',
          time: '2:00 PM',
          description: 'Feeling nauseous after meals.',
          requiresAttention: false,
          caregiverAlert: false,
          onDelete: () {},
        ),
      ));
      expect(find.text('Nausea'), findsOneWidget);
    });

    testWidgets('shows the severity label', (tester) async {
      // Verifies the severity badge is displayed.
      await tester.pumpWidget(_wrap(
        SymptomCard(
          title: 'Fever',
          severity: 'severe',
          time: '3:00 PM',
          description: 'High temperature.',
          requiresAttention: true,
          caregiverAlert: false,
          onDelete: () {},
        ),
      ));
      expect(find.text('severe'), findsOneWidget);
    });

    testWidgets('shows the time', (tester) async {
      // Verifies the time label is shown.
      await tester.pumpWidget(_wrap(
        SymptomCard(
          title: 'Cough',
          severity: 'mild',
          time: '9:30 AM',
          description: 'Dry cough.',
          requiresAttention: false,
          caregiverAlert: false,
          onDelete: () {},
        ),
      ));
      expect(find.text('9:30 AM'), findsOneWidget);
    });

    testWidgets('shows the description', (tester) async {
      // Verifies the description text is shown.
      await tester.pumpWidget(_wrap(
        SymptomCard(
          title: 'Back Pain',
          severity: 'moderate',
          time: '11:00 AM',
          description: 'Persistent lower back ache.',
          requiresAttention: false,
          caregiverAlert: false,
          onDelete: () {},
        ),
      ));
      expect(find.text('Persistent lower back ache.'), findsOneWidget);
    });

    testWidgets('shows warning icon for severe severity', (tester) async {
      // Verifies the warning icon appears for severe symptoms.
      await tester.pumpWidget(_wrap(
        SymptomCard(
          title: 'Chest Pain',
          severity: 'severe',
          time: '4:00 PM',
          description: 'Sharp chest pain.',
          requiresAttention: true,
          caregiverAlert: false,
          onDelete: () {},
        ),
      ));
      expect(find.byIcon(Icons.warning), findsOneWidget);
    });

    testWidgets('shows favorite icon for non-severe severity', (tester) async {
      // Verifies the favorite icon appears for non-severe symptoms.
      await tester.pumpWidget(_wrap(
        SymptomCard(
          title: 'Fatigue',
          severity: 'mild',
          time: '8:00 AM',
          description: 'Feeling tired.',
          requiresAttention: false,
          caregiverAlert: false,
          onDelete: () {},
        ),
      ));
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('shows Caregiver Alert badge when caregiverAlert is true', (tester) async {
      // Verifies the "Caregiver Alert" badge is displayed.
      await tester.pumpWidget(_wrap(
        SymptomCard(
          title: 'Dizziness',
          severity: 'moderate',
          time: '1:00 PM',
          description: 'Sudden dizziness.',
          requiresAttention: false,
          caregiverAlert: true,
          onDelete: () {},
        ),
      ));
      expect(find.text('Caregiver Alert'), findsOneWidget);
    });

    testWidgets('does not show Caregiver Alert when caregiverAlert is false', (tester) async {
      // Verifies the caregiver badge is hidden.
      await tester.pumpWidget(_wrap(
        SymptomCard(
          title: 'Cough',
          severity: 'mild',
          time: '9:00 AM',
          description: 'Mild cough.',
          requiresAttention: false,
          caregiverAlert: false,
          onDelete: () {},
        ),
      ));
      expect(find.text('Caregiver Alert'), findsNothing);
    });

    testWidgets('shows requires attention text when true', (tester) async {
      // Verifies the attention prompt is shown for urgent symptoms.
      await tester.pumpWidget(_wrap(
        SymptomCard(
          title: 'Seizure',
          severity: 'severe',
          time: '5:00 PM',
          description: 'Brief seizure episode.',
          requiresAttention: true,
          caregiverAlert: true,
          onDelete: () {},
        ),
      ));
      expect(find.textContaining('Requires immediate attention'), findsOneWidget);
    });

    testWidgets('tapping close icon calls onDelete', (tester) async {
      // Verifies the onDelete callback fires when the close button is tapped.
      var deleted = false;
      await tester.pumpWidget(_wrap(
        SymptomCard(
          title: 'Headache',
          severity: 'mild',
          time: '10:00 AM',
          description: 'Mild headache.',
          requiresAttention: false,
          caregiverAlert: false,
          onDelete: () => deleted = true,
        ),
      ));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(deleted, isTrue);
    });
  });
}
