// Tests for ActivityLogHistoryScreen
// (lib/features/activities/presentation/pages/activity_log_history_screen.dart).
// HTTP goes through the ApiService.debugSetHttpClient test seam.

import 'dart:convert';

import 'package:care_connect_app/features/activities/presentation/pages/activity_log_history_screen.dart';
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

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(
    home: ActivityLogHistoryScreen(clientId: 5, clientName: 'Alex Rivera'),
  ));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
  });

  testWidgets('lists logs with every satisfaction rating', (tester) async {
    _install((req) async => http.Response(
        jsonEncode([
          for (var r = 1; r <= 6; r++)
            {
              'id': r,
              'clientId': 5,
              'activityId': 10 + r,
              'activityName': r == 6 ? '' : 'Activity $r',
              'competencyScore': r,
              'satisfactionRating': r,
              'notes': r == 1 ? 'Went well' : null,
              'createdAt': r.isEven
                  ? '2026-10-0${r}T09:30:00'
                  : [2026, 10, r, 9, 30, 0],
            },
        ]),
        200));
    await _pump(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await _settle(tester);
    expect(find.text('Activity log history'), findsOneWidget);
    expect(find.text('Alex Rivera'), findsOneWidget);
    expect(find.text('Activity 1'), findsOneWidget);
    expect(find.text('Activity #16'), findsOneWidget);
    expect(find.text('Notes: Went well'), findsOneWidget);
    for (final e in ['😫', '😕', '😐', '🙂', '😄']) {
      expect(find.text('Satisfaction: $e'), findsOneWidget);
    }
  });

  testWidgets('empty list shows the no-logs message', (tester) async {
    _install((req) async => http.Response('[]', 200));
    await _pump(tester);
    await _settle(tester);
    expect(find.textContaining('No activity logs yet'), findsOneWidget);
  });

  testWidgets('error status shows retry which reloads', (tester) async {
    var calls = 0;
    _install((req) async {
      calls++;
      return calls == 1
          ? http.Response('', 503)
          : http.Response('[]', 200);
    });
    await _pump(tester);
    await _settle(tester);
    expect(find.text('Failed to load: 503'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await _settle(tester);
    expect(find.textContaining('No activity logs yet'), findsOneWidget);
  });

  testWidgets('exception shows the error text', (tester) async {
    _install((req) async => throw Exception('down'));
    await _pump(tester);
    await _settle(tester);
    expect(find.textContaining('Error: '), findsOneWidget);
  });
}
