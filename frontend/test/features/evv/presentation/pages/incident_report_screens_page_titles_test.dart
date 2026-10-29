// Page-title tests for IncidentReportWizardScreen
// (lib/features/evv/presentation/pages/incident_report_screens.dart):
// submitting a report replaces the wizard with a page titled
// "Incident Report Details" (WCAG 2.4.2).
import 'dart:convert';

import 'package:care_connect_app/features/evv/presentation/pages/incident_report_screens.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../helpers/titled_route_probe.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    ApiService.debugSetHttpClient(MockClient((_) async => http.Response(
        jsonEncode({
          'id': 5,
          'clientId': 42,
          'caregiverId': 1,
          'incidentType': 'FALL',
          'occurredAt': '2026-10-26T09:30:00',
          'location': 'Kitchen',
          'outcome': 'Resolved',
          'createdAt': '2026-10-26T09:45:00',
          'actions': ['Checked for injury'],
        }),
        201)));
  });

  tearDown(ApiService.debugResetHttpClient);

  testWidgets(
      'submitting a report opens a page titled "Incident Report Details"',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final probe = TitledRouteProbe();
    final navKey = GlobalKey<NavigatorState>();
    // The wizard replaces itself, so it sits above a home page.
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      navigatorObservers: [probe],
      home: const Scaffold(body: Text('Home')),
    ));
    navKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const IncidentReportWizardScreen(
            clientId: 42, clientName: 'Mary Johnson')));
    await tester.pumpAndSettle();

    Future<void> next() async {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Fall'));
    await tester.pump();
    await next();
    await tester.enterText(
        find.widgetWithText(TextField, 'Location'), 'Kitchen');
    await next();
    await next(); // trigger notes are optional
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await next();
    await tester.enterText(find.byType(TextField).first, 'Resolved');
    await next();

    expect(await probe.tapAndReadTitle(tester, find.text('Submit Report')),
        'Incident Report Details');
  });
}
