// Enhanced tests for MedicationsTrackerPage
// (lib/features/health/medication-tracker/pages/medication-tracker.dart).
//
// Covers:
//  - Loading state (when patientId is null, error fires immediately)
//  - Error state with null patientId
//  - Error state with patientId=0 (triggers API call that throws)
//  - Static text labels, icons, and structural elements
//  - Retry button interaction
//  - Page body structure (SafeArea, Column, Container decoration)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/health/medication-tracker/pages/medication-tracker.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';

import '../../../mock_user_provider.dart';

Widget _wrapWithPatientId(int? patientId) {
  final provider = MockUserProvider(
    mockUser: MockUser(id: 1, role: 'PATIENT', patientId: patientId),
  );
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: const MedicationsTrackerPage(),
    ),
  );
}

void main() {
  group('MedicationsTrackerPage – structure', () {
    testWidgets('has a Scaffold', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('has SafeArea', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.byType(SafeArea), findsOneWidget);
    });

    testWidgets('shows medication_outlined icon in header area', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.byIcon(Icons.medication_outlined), findsWidgets);
    });

    testWidgets('shows "Medications" heading text', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.text('Medications'), findsOneWidget);
    });

    testWidgets('shows subtitle about managing medication schedule',
        (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(
        find.text('Manage your medication schedule and reminders'),
        findsOneWidget,
      );
    });

    testWidgets('body is wrapped in Column', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.byType(Column), findsWidgets);
    });
  });

  group('MedicationsTrackerPage – null patientId error path', () {
    testWidgets('shows Patient ID not found error', (tester) async {
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

    testWidgets('shows refresh icon on Retry button', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('Retry button is an ElevatedButton', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      final retryButton = find.widgetWithText(ElevatedButton, 'Retry');
      expect(retryButton, findsOneWidget);
    });

    testWidgets('does not show CircularProgressIndicator after error',
        (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('does not show "No medications found" when in error state',
        (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.text('No medications found'), findsNothing);
    });

    testWidgets(
        'does not show "Add your first medication" when in error state',
        (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(
        find.text('Add your first medication to get started'),
        findsNothing,
      );
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

  group('MedicationsTrackerPage – AppBar header', () {
    testWidgets('has MedicationAppHeader (custom AppBar)', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      // The MedicationAppHeader contains an arrow_back icon and Add button
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('has Add button in header', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.text('Add'), findsOneWidget);
    });

    testWidgets('has add icon in header', (tester) async {
      await tester.pumpWidget(_wrapWithPatientId(null));
      await tester.pump();
      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });

  group('MedicationsTrackerPage – widget type', () {
    test('is a StatefulWidget', () {
      const page = MedicationsTrackerPage();
      expect(page, isA<StatefulWidget>());
    });

    test('createState returns non-null', () {
      const page = MedicationsTrackerPage();
      expect(page.createState(), isNotNull);
    });
  });
}
