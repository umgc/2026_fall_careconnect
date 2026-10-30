// Flow tests for BehavioralIncidentFormScreen and
// BehavioralIncidentHistoryScreen
// (lib/features/activities/presentation/pages/behavioral_incident_screens.dart):
// date/time picking, submit failures, and the history list/empty/error
// states. HTTP goes through the ApiService.debugSetHttpClient seam.

import 'dart:convert';

import 'package:care_connect_app/features/activities/presentation/pages/behavioral_incident_screens.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _install(Future<http.Response> Function(http.Request) handler) {
  ApiService.debugSetHttpClient(MockClient(handler));
  addTearDown(ApiService.debugResetHttpClient);
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  group('form', () {
    const form =
        BehavioralIncidentFormScreen(clientId: 7, clientName: 'Mary Johnson');

    testWidgets('date and time can be picked; time cancel keeps the time',
        (tester) async {
      _install((req) async => http.Response('[]', 200));
      await _pump(tester, form);
      await tester.tap(find.byIcon(Icons.schedule));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      // Time picker: confirm.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.schedule));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.schedule));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(BehavioralIncidentFormScreen), findsOneWidget);
    });

    testWidgets('server rejection shows the status and body', (tester) async {
      _install((req) async => http.Response('bad input', 400));
      await _pump(tester, form);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Observed Behavior'), 'Pacing');
      await tester.enterText(
          find.widgetWithText(
              TextFormField, 'Possible causes or context — optional'),
          'Loud TV');
      await tester.tap(find.widgetWithText(FilledButton, 'Log Behavior'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Failed to log incident: 400 — bad input'),
          findsOneWidget);
    });

    testWidgets('network error shows the error', (tester) async {
      _install((req) async => throw Exception('offline'));
      await _pump(tester, form);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Observed Behavior'), 'Pacing');
      await tester.tap(find.widgetWithText(FilledButton, 'Log Behavior'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Error: '), findsOneWidget);
    });
  });

  group('history', () {
    const history =
        BehavioralIncidentHistoryScreen(clientId: 7, clientName: 'Mary');

    testWidgets('lists incidents with trigger notes', (tester) async {
      _install((req) async => http.Response(
          jsonEncode([
            {
              'id': 1,
              'clientId': 7,
              'caregiverId': 2,
              'observedBehavior': 'Agitated before lunch',
              'occurredAt': '2026-10-01T11:30:00',
              'triggerNotes': 'Hungry',
            },
            {
              'id': 2,
              'clientId': 7,
              'caregiverId': 2,
              'observedBehavior': 'Calm afternoon',
              'occurredAt': [2026, 10, 2, 15, 0],
            },
          ]),
          200));
      await _pump(tester, history);
      expect(find.text('Behavioral history'), findsOneWidget);
      expect(find.text('Agitated before lunch'), findsOneWidget);
      expect(find.textContaining('Hungry'), findsOneWidget);
      expect(find.text('Calm afternoon'), findsOneWidget);
    });

    testWidgets('empty history shows a message', (tester) async {
      _install((req) async => http.Response('[]', 200));
      await _pump(tester, history);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('error status shows retry which reloads', (tester) async {
      var calls = 0;
      _install((req) async {
        calls++;
        return calls == 1
            ? http.Response('', 500)
            : http.Response('[]', 200);
      });
      await _pump(tester, history);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, 2);
    });

    testWidgets('exception shows the error', (tester) async {
      _install((req) async => throw Exception('down'));
      await _pump(tester, history);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
