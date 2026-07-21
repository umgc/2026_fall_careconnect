// Enhanced tests for SymptomsAllergiesPage
// (lib/features/health/symptom-tracker/pages/symptom_allergies_tracker_screen.dart).
//
// Covers:
//  - Page structure (Scaffold, SafeArea, TabBar, TabController)
//  - Text labels and icons
//  - Error state with null patientId
//  - Error state with patientId=0 (treated as invalid)
//  - Retry button interaction
//  - Tab labels (Mental Health Symptoms, Drug Allergies)
//  - SymptomEntry model class

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/health/symptom-tracker/pages/symptom_allergies_tracker_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../mock_user_provider.dart';

Widget _wrapWithPatientId(int? patientId) {
  final provider = MockUserProvider(
    mockUser: MockUser(id: 1, role: 'PATIENT', patientId: patientId),
  );
  return MaterialApp(
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: const SymptomsAllergiesPage(),
    ),
  );
}

void main() {
  group('SymptomsAllergiesPage – structure', () {
    testWidgets('renders a Scaffold', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('renders SafeArea', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.byType(SafeArea), findsWidgets);
    });

    testWidgets('renders Column', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.byType(Column), findsWidgets);
    });

    testWidgets('is a StatefulWidget', (tester) async {
      const page = SymptomsAllergiesPage();
      expect(page, isA<StatefulWidget>());
    });
  });

  group('SymptomsAllergiesPage – header content', () {
    testWidgets('shows medical_information_outlined icon', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.byIcon(Icons.medical_information_outlined), findsOneWidget);
    });

    testWidgets('shows "Symptoms & Allergies" heading', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.text('Symptoms & Allergies'), findsOneWidget);
    });

    testWidgets('shows subtitle about tracking', (tester) async {
      // Subtitle is portrait-only; default 800x600 surface is landscape.
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(
        find.text('Track your health symptoms and medication allergies'),
        findsOneWidget,
      );
    });
  });

  group('SymptomsAllergiesPage – TabBar', () {
    testWidgets('shows TabBar widget', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.byType(TabBar), findsOneWidget);
    });

    testWidgets('shows Mental Health Symptoms tab', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.textContaining('Mental Health'), findsOneWidget);
    });

    testWidgets('shows Drug Allergies tab', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.text('Drug Allergies'), findsOneWidget);
    });

    testWidgets('TabBar has exactly 2 Tab children', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.byType(Tab), findsNWidgets(2));
    });
  });

  group('SymptomsAllergiesPage – null patientId error', () {
    testWidgets('shows "Patient ID not found" error', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.text('Patient ID not found'), findsOneWidget);
    });

    testWidgets('shows error_outline icon', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows Retry button', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('shows refresh icon', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('Retry is an ElevatedButton', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(
        find.widgetWithText(ElevatedButton, 'Retry'),
        findsOneWidget,
      );
    });

    testWidgets('no CircularProgressIndicator after error', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('no TabBarView shown in error state', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.byType(TabBarView), findsNothing);
    });

    testWidgets('tapping Retry does not crash', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      // Still shows error since patientId is still null
      expect(find.text('Patient ID not found'), findsOneWidget);
    });
  });

  group('SymptomsAllergiesPage – patientId=0 treated as invalid', () {
    testWidgets('shows error when patientId is 0', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(0));
      await tester.pump();
      expect(find.text('Patient ID not found'), findsOneWidget);
    });

    testWidgets('shows error_outline icon when patientId is 0',
        (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(0));
      await tester.pump();
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });

  group('SymptomEntry model', () {
    test('creates with required fields', () {
      final entry = SymptomEntry(
        symptom: 'Headache',
        severity: 7.0,
        timestamp: DateTime(2024, 12, 27),
      );
      expect(entry.symptom, 'Headache');
      expect(entry.severity, 7.0);
      expect(entry.timestamp, DateTime(2024, 12, 27));
      expect(entry.image, isNull);
    });

    test('creates with optional image field', () {
      final file = File('/tmp/test.png');
      final entry = SymptomEntry(
        symptom: 'Rash',
        severity: 3.0,
        timestamp: DateTime(2024, 12, 25),
        image: file,
      );
      expect(entry.image, isNotNull);
      expect(entry.image!.path, '/tmp/test.png');
    });

    test('severity stores decimal values', () {
      final entry = SymptomEntry(
        symptom: 'Pain',
        severity: 5.5,
        timestamp: DateTime(2024, 1, 1),
      );
      expect(entry.severity, 5.5);
    });

    test('symptom stores arbitrary text', () {
      final entry = SymptomEntry(
        symptom: 'Multiple symptoms: headache, nausea, fatigue',
        severity: 8.0,
        timestamp: DateTime(2024, 6, 15),
      );
      expect(entry.symptom, contains('headache'));
      expect(entry.symptom, contains('nausea'));
    });

    test('timestamp stores precise date and time', () {
      final ts = DateTime(2024, 3, 15, 14, 30, 0);
      final entry = SymptomEntry(
        symptom: 'Dizziness',
        severity: 4.0,
        timestamp: ts,
      );
      expect(entry.timestamp.hour, 14);
      expect(entry.timestamp.minute, 30);
    });
  });
}
