// Tests for PatientHeaderCard widget
// (lib/features/health/caregiver-patient-list/widgets/patient_header_card.dart)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/patient_header_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

PatientHeaderCard _card({
  String fullName = 'Alice Johnson',
  String mrn = 'MRN-001',
  int age = 45,
  String sex = 'Female',
  String moodLabel = 'Good',
  String moodEmoji = '😊',
  List<String> diagnoses = const [],
  List<String> allergies = const [],
}) =>
    PatientHeaderCard(
      fullName: fullName,
      mrn: mrn,
      age: age,
      sex: sex,
      currentMoodLabel: moodLabel,
      currentMoodEmoji: moodEmoji,
      diagnoses: diagnoses,
      allergies: allergies,
    );

void _setWideViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
}

void main() {
  group('PatientHeaderCard', () {
    setUp(() {});

    testWidgets('renders without crashing', (tester) async {
      _setWideViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(_card()));
      expect(find.byType(PatientHeaderCard), findsOneWidget);
    });

    testWidgets('shows patient full name', (tester) async {
      _setWideViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(_card(fullName: 'Robert Brown')));
      expect(find.text('Robert Brown'), findsOneWidget);
    });

    testWidgets('shows age and sex', (tester) async {
      _setWideViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(_card(age: 62, sex: 'Male')));
      expect(find.text('Age 62 • Male'), findsOneWidget);
    });

    testWidgets('shows current mood label', (tester) async {
      _setWideViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(_card(moodLabel: 'Fair')));
      expect(find.textContaining('Fair'), findsWidgets);
    });

    testWidgets('shows current mood emoji', (tester) async {
      _setWideViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(_card(moodEmoji: '😐')));
      expect(find.textContaining('😐'), findsWidgets);
    });

    testWidgets('shows first letter of name in avatar', (tester) async {
      _setWideViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(_card(fullName: 'Deborah Smith')));
      expect(find.text('D'), findsOneWidget);
    });

    testWidgets('shows Current Mood label text', (tester) async {
      _setWideViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(_card()));
      expect(find.textContaining('Current Mood:'), findsWidgets);
    });

    testWidgets('shows Last Check-in text', (tester) async {
      _setWideViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(_card()));
      expect(find.textContaining('Last Check-in:'), findsWidgets);
    });

    testWidgets('shows Start Video Call button', (tester) async {
      _setWideViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(_card()));
      expect(find.text('Start Video Call'), findsOneWidget);
    });

    testWidgets('shows Emergency Contacts button', (tester) async {
      _setWideViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(_card()));
      expect(find.text('Emergency Contacts'), findsOneWidget);
    });

    testWidgets('shows diagnoses chips when provided', (tester) async {
      _setWideViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(_card(diagnoses: ['Hypertension', 'Diabetes'])));
      expect(find.text('Hypertension'), findsOneWidget);
      expect(find.text('Diabetes'), findsOneWidget);
    });

    testWidgets('shows Primary Diagnoses label when diagnoses exist', (tester) async {
      _setWideViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(_card(diagnoses: ['Asthma'])));
      expect(find.text('Primary Diagnoses'), findsOneWidget);
    });

    testWidgets('does not show Primary Diagnoses label when diagnoses empty', (tester) async {
      _setWideViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(_card(diagnoses: [])));
      expect(find.text('Primary Diagnoses'), findsNothing);
    });

    testWidgets('shows allergy pills when provided', (tester) async {
      _setWideViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(_card(allergies: ['Penicillin', 'Sulfa'])));
      expect(find.text('Penicillin'), findsOneWidget);
      expect(find.text('Sulfa'), findsOneWidget);
    });

    testWidgets('shows Allergies label when allergies exist', (tester) async {
      _setWideViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(_card(allergies: ['Latex'])));
      expect(find.text('Allergies'), findsOneWidget);
    });

    testWidgets('does not show Allergies label when allergies empty', (tester) async {
      _setWideViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(_card(allergies: [])));
      expect(find.text('Allergies'), findsNothing);
    });

    testWidgets('shows vitals when heartRateBpm provided', (tester) async {
      _setWideViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(PatientHeaderCard(
        fullName: 'Test Patient',
        mrn: 'MRN-002',
        age: 50,
        sex: 'Male',
        currentMoodLabel: 'Good',
        currentMoodEmoji: '😊',
        diagnoses: [],
        allergies: [],
        heartRateBpm: 72,
      )));
      expect(find.text('72 bpm'), findsOneWidget);
    });

    testWidgets('calls onStartVideoCall when video button tapped', (tester) async {
      _setWideViewport(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var called = false;
      await tester.pumpWidget(_wrap(PatientHeaderCard(
        fullName: 'Test',
        mrn: 'MRN-003',
        age: 40,
        sex: 'Female',
        currentMoodLabel: 'Good',
        currentMoodEmoji: '😊',
        diagnoses: [],
        allergies: [],
        onStartVideoCall: () => called = true,
      )));
      tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Start Video Call'),
      ).onPressed!();
      await tester.pump();
      expect(called, isTrue);
    });
  });
}
