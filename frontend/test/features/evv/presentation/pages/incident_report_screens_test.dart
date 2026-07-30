// Tests for incident_report_screens.dart
// (lib/features/evv/presentation/pages/incident_report_screens.dart)
//
// This file has two screens:
//   - IncidentReportDetailScreen: a StatelessWidget rendering a saved report.
//   - IncidentReportWizardScreen: a multi-step form that posts a new report
//     via ApiService.postIncidentReport.
// These tests cover the detail screen's populated and empty-field rendering and
// the wizard's step-0 rendering plus its step-advance validation gate.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:care_connect_app/features/activities/models/client_activity_model.dart';
import 'package:care_connect_app/features/evv/presentation/pages/incident_report_screens.dart';
import 'package:care_connect_app/services/api_service.dart';

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

String _createdBody() => jsonEncode({
      'id': 7,
      'clientId': 42,
      'caregiverId': 1,
      'incident_type': 'FALL',
      'occurred_at': '2026-08-01T09:30:00.000',
      'location': 'Living room',
      'trigger_notes': 'Tripped on a rug',
      'outcome': 'Client stable',
      'created_at': '2026-08-01T10:00:00.000',
      'actions': ['Applied first aid'],
    });

/// Walk the wizard from step 0 through the review step, filling each required
/// field, so the final Submit button is reachable.
Future<void> _walkToReview(WidgetTester tester) async {
  Future<void> next() async {
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
  }

  // Step 0: incident type
  await tester.tap(find.text('Fall'));
  await tester.pumpAndSettle();
  await next();
  // Step 1: location
  await tester.enterText(find.byType(TextField).first, 'Living room');
  await tester.pumpAndSettle();
  await next();
  // Step 2: triggers (optional) — fill it to cover the non-null branch
  await tester.enterText(find.byType(TextField).first, 'Tripped on a rug');
  await tester.pumpAndSettle();
  await next();
  // Step 3: actions — check one, plus an "other" action
  await tester.tap(find.text('Applied first aid'));
  await tester.pumpAndSettle();
  await next();
  // Step 4: outcome
  await tester.enterText(find.byType(TextField).first, 'Client stable');
  await tester.pumpAndSettle();
  await next();
  // Now on step 5 (review) — Submit button is present.
}

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // AuthTokenManager.getAuthHeaders() reads the JWT from secure storage; stub
    // it so the submit reaches the HTTP client instead of throwing.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async {
      if (call.method == 'read') return 'test-token';
      if (call.method == 'readAll') return <String, String>{};
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });

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

    testWidgets('walks all steps and submits, landing on the detail screen',
        (tester) async {
      ApiService.debugSetHttpClient(MockClient((req) async {
        expect(req.url.toString(), contains('/incident-reports'));
        return http.Response(_createdBody(), 201);
      }));
      addTearDown(() => ApiService.debugResetHttpClient());

      tester.view.physicalSize = const Size(1200, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wizardHost());
      await tester.pumpAndSettle();

      await _walkToReview(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Submit Report'));
      // The Submit button shows a spinner while _submitting, so pump bounded
      // frames rather than pumpAndSettle (which never settles).
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // pushReplacement to the detail screen ran.
      expect(find.byType(IncidentReportDetailScreen), findsOneWidget);
      expect(find.text('Incident Report'), findsOneWidget);
    });

    testWidgets('shows an error snackbar when the submit fails', (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((req) async => http.Response('boom', 500)));
      addTearDown(() => ApiService.debugResetHttpClient());

      tester.view.physicalSize = const Size(1200, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wizardHost());
      await tester.pumpAndSettle();

      await _walkToReview(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Submit Report'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(IncidentReportDetailScreen), findsNothing);
      expect(find.textContaining('Failed to submit report'), findsWidgets);
    });

    testWidgets('opens the date/time picker and cancels', (tester) async {
      tester.view.physicalSize = const Size(1200, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wizardHost());
      await tester.pumpAndSettle();

      // Advance to step 1, which hosts the date/time button.
      await tester.tap(find.text('Fall'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.schedule));
      await tester.pumpAndSettle();
      // Cancel the date picker (early return, no state change).
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(IncidentReportWizardScreen), findsOneWidget);
    });
  });
}
