// Tests for incident_report_screens.dart
// (lib/features/evv/presentation/pages/incident_report_screens.dart)
//
// This file has two screens:
//   - IncidentReportDetailScreen: a StatelessWidget rendering a saved report.
//   - IncidentReportWizardScreen: a multi-step form that posts a new report
//     via ApiService.postIncidentReport.
// These tests cover the detail screen's populated and empty-field rendering and
// the wizard's step-0 rendering plus its step-advance validation gate.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/activities/models/client_activity_model.dart';
import 'package:care_connect_app/features/evv/presentation/pages/incident_report_screens.dart';

IncidentReportEntry _report({
  String incidentType = 'FALL',
  String? triggerNotes = 'Client tripped on a rug',
  List<String> actions = const ['Applied first aid', 'Notified family'],
}) =>
    IncidentReportEntry(
      id: 1,
      clientId: 42,
      caregiverId: 1,
      incidentType: incidentType,
      occurredAt: DateTime(2026, 8, 1, 9, 30),
      location: 'Living room',
      triggerNotes: triggerNotes,
      outcome: 'Client stable, monitored for one hour',
      createdAt: DateTime(2026, 8, 1, 10, 0),
      actions: actions,
    );

Widget _detailHost(IncidentReportEntry report) => MaterialApp(
      home: IncidentReportDetailScreen(clientName: 'Mary Johnson', report: report),
    );

Widget _wizardHost() => const MaterialApp(
      home: IncidentReportWizardScreen(clientId: 42, clientName: 'Mary Johnson'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IncidentReportDetailScreen', () {
    testWidgets('renders the report fields and actions', (tester) async {
      await tester.pumpWidget(_detailHost(_report()));
      await tester.pumpAndSettle();

      expect(find.text('Incident Report'), findsOneWidget);
      expect(find.text('Mary Johnson'), findsOneWidget);
      expect(find.text('Living room'), findsOneWidget);
      expect(find.text('Client stable, monitored for one hour'), findsOneWidget);
      expect(find.text('• Applied first aid'), findsOneWidget);
      expect(find.text('• Notified family'), findsOneWidget);
    });

    testWidgets('shows fallbacks when actions and triggers are empty',
        (tester) async {
      await tester.pumpWidget(
          _detailHost(_report(triggerNotes: null, actions: const [])));
      await tester.pumpAndSettle();

      expect(find.text('No actions recorded'), findsOneWidget);
      expect(find.text('None recorded'), findsOneWidget);
    });
  });

  group('IncidentReportWizardScreen', () {
    testWidgets('renders step 0 with the app bar, type options, and Next',
        (tester) async {
      await tester.pumpWidget(_wizardHost());
      await tester.pumpAndSettle();

      expect(find.text('File Incident Report'), findsOneWidget);
      expect(find.text('Fall'), findsWidgets);
      expect(find.text('Behavioral Crisis'), findsWidgets);
      expect(find.widgetWithText(FilledButton, 'Next'), findsOneWidget);
    });

    testWidgets('gates Next until an incident type is selected', (tester) async {
      await tester.pumpWidget(_wizardHost());
      await tester.pumpAndSettle();

      // Tapping Next with no type selected stays on step 0 (Location not shown).
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Location'), findsNothing);
      expect(find.text('Location'), findsNothing);

      // Selecting a type then Next advances to step 1 (Location field appears).
      await tester.tap(find.text('Fall'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();
      expect(find.text('Location'), findsWidgets);
    });
  });
}
