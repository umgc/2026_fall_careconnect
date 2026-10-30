// Tests for BehavioralIncidentFormScreen and BehavioralIncidentHistoryScreen
// (lib/features/activities/presentation/pages/behavioral_incident_screens.dart).
import 'dart:convert';

import 'package:care_connect_app/features/activities/presentation/pages/behavioral_incident_screens.dart';
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
  final requests = <http.Request>[];

  setUp(() {
    requests.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    ApiService.debugSetHttpClient(MockClient((request) async {
      requests.add(request);
      if (request.method == 'POST') {
        return http.Response(jsonEncode({'id': 1}), 201);
      }
      return http.Response(jsonEncode([]), 200);
    }));
  });

  tearDown(ApiService.debugResetHttpClient);

  Future<void> pumpForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    probe = TitledRouteProbe();
    final navKey = GlobalKey<NavigatorState>();
    // The form replaces itself with the history page, so it sits above a home
    // page the probe can return to.
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      navigatorObservers: [probe],
      home: const Scaffold(body: Text('Home')),
    ));
    navKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const BehavioralIncidentFormScreen(
            clientId: 7, clientName: 'Mary Johnson')));
    await tester.pumpAndSettle();
  }

  testWidgets('an empty behavior is refused with a message', (tester) async {
    await pumpForm(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Log Behavior'));
    await tester.pump();
    expect(find.text('Please describe the observed behavior'), findsOneWidget);
    expect(requests, isEmpty);
  });

  testWidgets(
      'logging a behavior posts it, then opens a page titled '
      '"Behavioral Incident History"', (tester) async {
    await pumpForm(tester);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Observed Behavior'),
        'Agitated before lunch');
    expect(
        await probe.tapAndReadTitle(
            tester, find.widgetWithText(FilledButton, 'Log Behavior')),
        'Behavioral Incident History');
    expect(requests.where((r) => r.method == 'POST'), hasLength(1));
    expect(requests.firstWhere((r) => r.method == 'POST').url.path,
        contains('/7/'));
  });
}
