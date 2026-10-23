// Tests for PainLevelCard widget
// (lib/features/health/caregiver-patient-list/widgets/pain_level_card.dart).
// Pure StatelessWidget — no platform channels or network I/O.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/pain_level_card.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  group('PainLevelCard', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(const PainLevelCard(
        lastReportedText: '2 hours ago',
        currentPain: 4,
        location: 'Lower back',
        dizziness: 2,
        fatigue: 5,
      )));
      expect(find.byType(PainLevelCard), findsOneWidget);
    });

    testWidgets('shows Pain Level header', (tester) async {
      await tester.pumpWidget(_wrap(const PainLevelCard(
        lastReportedText: '2 hours ago',
        currentPain: 4,
        location: 'Lower back',
        dizziness: 2,
        fatigue: 5,
      )));
      expect(find.text('Pain Level'), findsOneWidget);
    });

    testWidgets('shows last reported text', (tester) async {
      await tester.pumpWidget(_wrap(const PainLevelCard(
        lastReportedText: 'yesterday',
        currentPain: 3,
        location: 'Knee',
        dizziness: 1,
        fatigue: 4,
      )));
      expect(find.text('Last reported yesterday'), findsOneWidget);
    });

    testWidgets('shows location', (tester) async {
      await tester.pumpWidget(_wrap(const PainLevelCard(
        lastReportedText: 'an hour ago',
        currentPain: 5,
        location: 'Shoulder',
        dizziness: 0,
        fatigue: 3,
      )));
      expect(find.text('Location: Shoulder'), findsOneWidget);
    });

    testWidgets('shows Current Pain label and score', (tester) async {
      await tester.pumpWidget(_wrap(const PainLevelCard(
        lastReportedText: 'now',
        currentPain: 7,
        location: 'Head',
        dizziness: 3,
        fatigue: 6,
      )));
      expect(find.text('Current Pain'), findsOneWidget);
      expect(find.text('7/10'), findsOneWidget);
    });

    testWidgets('shows Dizziness label and score', (tester) async {
      await tester.pumpWidget(_wrap(const PainLevelCard(
        lastReportedText: 'now',
        currentPain: 2,
        location: 'None',
        dizziness: 8,
        fatigue: 4,
      )));
      expect(find.text('Dizziness'), findsOneWidget);
      expect(find.text('8/10'), findsOneWidget);
    });

    testWidgets('shows Fatigue label and score', (tester) async {
      await tester.pumpWidget(_wrap(const PainLevelCard(
        lastReportedText: 'now',
        currentPain: 1,
        location: 'Legs',
        dizziness: 0,
        fatigue: 9,
      )));
      expect(find.text('Fatigue'), findsOneWidget);
      expect(find.text('9/10'), findsOneWidget);
    });

    testWidgets('shows No Pain and Severe labels for current pain bar', (tester) async {
      await tester.pumpWidget(_wrap(const PainLevelCard(
        lastReportedText: 'now',
        currentPain: 5,
        location: 'Back',
        dizziness: 3,
        fatigue: 3,
      )));
      expect(find.text('No Pain'), findsOneWidget);
      // "Severe" appears once for pain bar (dizziness and fatigue use None/Severe)
      expect(find.text('Severe'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows None and Severe labels for dizziness bar', (tester) async {
      await tester.pumpWidget(_wrap(const PainLevelCard(
        lastReportedText: 'now',
        currentPain: 5,
        location: 'Back',
        dizziness: 3,
        fatigue: 3,
      )));
      expect(find.text('None'), findsNWidgets(2)); // dizziness + fatigue
    });

    testWidgets('renders three LinearProgressIndicators', (tester) async {
      await tester.pumpWidget(_wrap(const PainLevelCard(
        lastReportedText: 'now',
        currentPain: 5,
        location: 'Back',
        dizziness: 3,
        fatigue: 7,
      )));
      expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
    });
  });
}
