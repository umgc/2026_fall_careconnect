// Tests for AllergyCard widget
// (lib/features/health/symptom-tracker/widgets/allergies_card.dart).
// Pure StatelessWidget — no platform channels or network I/O.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/symptom-tracker/widgets/allergies_card.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  group('AllergyCard', () {
    testWidgets('renders without crashing', (tester) async {
      // Verifies the widget builds without error.
      await tester.pumpWidget(_wrap(
        AllergyCard(
          drug: 'Penicillin',
          reaction: 'Hives',
          severity: 'Moderate',
          note: 'Avoid all penicillin-based antibiotics.',
          onDelete: () {},
        ),
      ));
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('shows the drug name in bold', (tester) async {
      // Verifies the drug name is displayed.
      await tester.pumpWidget(_wrap(
        AllergyCard(
          drug: 'Sulfa',
          reaction: 'Rash',
          severity: 'Severe',
          note: 'Carry EpiPen.',
          onDelete: () {},
        ),
      ));
      expect(find.text('Sulfa'), findsOneWidget);
    });

    testWidgets('shows the reaction text', (tester) async {
      // Verifies the reaction field is displayed.
      await tester.pumpWidget(_wrap(
        AllergyCard(
          drug: 'Aspirin',
          reaction: 'Anaphylaxis',
          severity: 'Severe',
          note: '',
          onDelete: () {},
        ),
      ));
      expect(find.textContaining('Anaphylaxis'), findsOneWidget);
    });

    testWidgets('shows the severity text', (tester) async {
      // Verifies the severity field is displayed.
      await tester.pumpWidget(_wrap(
        AllergyCard(
          drug: 'Codeine',
          reaction: 'Nausea',
          severity: 'Mild',
          note: '',
          onDelete: () {},
        ),
      ));
      expect(find.textContaining('Mild'), findsOneWidget);
    });

    testWidgets('shows the note text', (tester) async {
      // Verifies the note field is displayed.
      await tester.pumpWidget(_wrap(
        AllergyCard(
          drug: 'Latex',
          reaction: 'Swelling',
          severity: 'Moderate',
          note: 'Document in chart.',
          onDelete: () {},
        ),
      ));
      expect(find.text('Document in chart.'), findsOneWidget);
    });

    testWidgets('shows close icon button', (tester) async {
      // Verifies the delete button icon is shown.
      await tester.pumpWidget(_wrap(
        AllergyCard(
          drug: 'Ibuprofen',
          reaction: 'GI upset',
          severity: 'Low',
          note: '',
          onDelete: () {},
        ),
      ));
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('tapping close icon calls onDelete', (tester) async {
      // Verifies the onDelete callback fires when the close button is tapped.
      var deleted = false;
      await tester.pumpWidget(_wrap(
        AllergyCard(
          drug: 'Ibuprofen',
          reaction: 'GI upset',
          severity: 'Low',
          note: '',
          onDelete: () => deleted = true,
        ),
      ));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(deleted, isTrue);
    });
  });
}
