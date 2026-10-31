// More happy-path tests for IncidentReportWizardScreen
// (lib/features/evv/presentation/pages/incident_report_screens.dart):
// walking all six steps, the date/time picker, and submit outcomes.
import 'dart:convert';

import 'package:care_connect_app/features/evv/presentation/pages/incident_report_screens.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late http.Response Function(http.Request) handler;
  final posts = <http.Request>[];

  setUp(() {
    posts.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    handler = (_) => http.Response(
        jsonEncode({
          'id': 5,
          'clientId': 42,
          'caregiverId': 1,
          'incidentType': 'MEDICAL_EVENT',
          'occurredAt': [2026, 8, 1, 9, 30, 0],
          'location': 'Kitchen',
          'outcome': 'Stable',
          'createdAt': '2026-08-01T10:00:00',
          'actions': ['Applied first aid'],
        }),
        201);
    ApiService.debugSetHttpClient(MockClient((request) async {
      posts.add(request);
      return handler(request);
    }));
  });

  tearDown(ApiService.debugResetHttpClient);

  Future<void> pumpWizard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: IncidentReportWizardScreen(clientId: 42, clientName: 'Mary'),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
  }

  Future<void> walkToReview(WidgetTester tester,
      {String type = 'Medical Event', bool trigger = true}) async {
    await tester.tap(find.text(type));
    await tester.pumpAndSettle();
    await next(tester);
    // Step 2: location is required.
    await next(tester);
    expect(find.text('Step 2 of 6'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Kitchen');
    await next(tester);
    // Step 3: optional triggers.
    if (trigger) {
      await tester.enterText(find.byType(TextField), 'Loud noise');
    }
    await next(tester);
    // Step 4: at least one action.
    await next(tester);
    expect(find.text('Step 4 of 6'), findsOneWidget);
    await tester.tap(find.text('Applied first aid'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Gave water');
    await next(tester);
    // Step 5: outcome is required.
    await next(tester);
    expect(find.text('Step 5 of 6'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Stable');
    await next(tester);
    expect(find.text('Review incident report'), findsOneWidget);
  }

  testWidgets('walks every step, reviews and submits to the detail screen',
      (tester) async {
    await pumpWizard(tester);
    await walkToReview(tester);
    expect(find.text('Medical Event'), findsOneWidget);
    expect(find.text('Loud noise'), findsOneWidget);
    expect(find.text('• Applied first aid'), findsOneWidget);
    expect(find.text('• Gave water'), findsOneWidget);

    await tester.tap(find.text('Submit Report'));
    await tester.pumpAndSettle();
    final body = jsonDecode(posts.single.body) as Map<String, dynamic>;
    expect(body['incident_type'], 'MEDICAL_EVENT');
    expect(find.text('Incident Report'), findsOneWidget);
  });

  for (final type in [
    'Fall',
    'Behavioral Crisis',
    'Elopement',
    'Self-Harm',
    'Property Damage',
    'Other',
  ]) {
    testWidgets('review labels the "$type" type', (tester) async {
      await pumpWizard(tester);
      await walkToReview(tester, type: type, trigger: false);
      expect(find.text(type), findsOneWidget);
      expect(find.text('None recorded'), findsOneWidget);
    });
  }

  testWidgets('a rejected submit shows the status and body', (tester) async {
    handler = (_) => http.Response('bad input', 400);
    await pumpWizard(tester);
    await walkToReview(tester);
    await tester.tap(find.text('Submit Report'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Failed to submit report: 400'), findsOneWidget);
  });

  testWidgets('a thrown submit error is reported', (tester) async {
    handler = (_) => throw http.ClientException('offline');
    await pumpWizard(tester);
    await walkToReview(tester);
    await tester.tap(find.text('Submit Report'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Error:'), findsOneWidget);
  });

  testWidgets('Back steps back from the review', (tester) async {
    await pumpWizard(tester);
    await walkToReview(tester);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Step 5 of 6'), findsOneWidget);
  });

  testWidgets('the date picker sets the date, with and without a time',
      (tester) async {
    await pumpWizard(tester);
    await tester.tap(find.text('Fall'));
    await tester.pumpAndSettle();
    await next(tester);

    // Pick a date, then cancel the time picker.
    await tester.tap(find.byIcon(Icons.schedule));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Pick a date and accept the time.
    await tester.tap(find.byIcon(Icons.schedule));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Cancel the date picker.
    await tester.tap(find.byIcon(Icons.schedule));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 6'), findsOneWidget);
  });
}
