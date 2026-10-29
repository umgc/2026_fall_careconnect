// Tests for IncidentReportHistoryScreen
// (lib/features/health/caregiver-patient-list/page/incident_report_history_screen.dart).
import 'dart:convert';

import 'package:care_connect_app/features/health/caregiver-patient-list/page/incident_report_history_screen.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../helpers/titled_route_probe.dart';

void main() {
  late TitledRouteProbe probe;

  void serve(int status, Object body) {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(jsonEncode(body), status)));
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  tearDown(ApiService.debugResetHttpClient);

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    probe = TitledRouteProbe();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [probe],
      home: const IncidentReportHistoryScreen(
          clientId: 7, clientName: 'Mary Johnson'),
    ));
    await tester.pumpAndSettle();
  }

  final report = {
    'id': 1,
    'clientId': 7,
    'caregiverId': 42,
    'incidentType': 'FALL_NO_INJURY',
    'occurredAt': '2026-10-20T09:30:00',
    'location': 'Kitchen',
    'outcome': 'Resolved',
    'createdAt': '2026-10-20T09:45:00',
    'actions': ['Checked for injury'],
  };

  testWidgets('lists reports by type', (tester) async {
    serve(200, [report]);
    await pumpScreen(tester);
    expect(find.text('FALL NO INJURY'), findsOneWidget);
  });

  testWidgets('a server error is shown', (tester) async {
    serve(500, {'error': 'x'});
    await pumpScreen(tester);
    expect(find.textContaining('500'), findsWidgets);
  });

  testWidgets('opening a report pushes a page titled "Incident Report Details"',
      (tester) async {
    serve(200, [report]);
    await pumpScreen(tester);
    expect(await probe.tapAndReadTitle(tester, find.text('FALL NO INJURY')),
        'Incident Report Details');
  });
}
