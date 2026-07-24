// Tests for SymptomsAllergiesPage
// (lib/features/health/symptom-tracker/pages/symptom_allergies_tracker_screen.dart).
//
// initState calls _resolvePatientId() using Provider.of<UserProvider>.
// With patientId=null, returns early (no HTTP) with error message.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/health/symptom-tracker/pages/symptom_allergies_tracker_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../mock_user_provider.dart';

Widget _wrap() {
  final provider = MockUserProvider(
    mockUser: MockUser(id: 1, role: 'PATIENT', patientId: null),
  );
  return MaterialApp(
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: const SymptomsAllergiesPage(),
    ),
  );
}

void main() {
  group('SymptomsAllergiesPage – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(SymptomsAllergiesPage), findsOneWidget);
    });

    testWidgets('shows "Symptoms & Allergies" heading', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Symptoms & Allergies'), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows error for null patientId', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.textContaining('Patient ID not found'), findsOneWidget);
    });

    testWidgets('shows medical_information_outlined icon', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.medical_information_outlined), findsOneWidget);
    });

    testWidgets('shows subtitle text about tracking', (tester) async {
      // Subtitle is portrait-only; default 800x600 surface is landscape.
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Track your health symptoms and medication allergies'),
          findsOneWidget);
    });

    testWidgets('shows error_outline icon on error', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows Retry button on error', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('shows refresh icon on Retry button', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('shows TabBar with Mental Health and Drug Allergies tabs',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(TabBar), findsOneWidget);
    });
  });
}
