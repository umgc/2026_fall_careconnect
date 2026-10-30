// Tests for AuditLogScreen (lib/features/audit/audit_log_screen.dart).
// HTTP goes through the ApiService.debugSetHttpClient test seam.

import 'dart:convert';

import 'package:care_connect_app/features/audit/audit_log_screen.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final List<Uri> _requests = [];

void _install(Future<http.Response> Function(http.Request) handler) {
  ApiService.debugSetHttpClient(MockClient((req) {
    _requests.add(req.url);
    return handler(req);
  }));
  addTearDown(ApiService.debugResetHttpClient);
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(
    home: AuditLogScreen(clientId: 9, clientName: 'Pat Doe'),
  ));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 500));
}

final _items = [
  for (final t in [
    'ACTIVITY_LOG',
    'BEHAVIORAL_INCIDENT',
    'INCIDENT_REPORT',
    'CLIENT_EVENT',
    'OTHER',
  ])
    {
      'type': t,
      'summary': 'Summary $t',
      'caregiverName': 'Cara Giver',
      'createdAt': '2026-10-01T08:05:00',
    },
];

void main() {
  setUp(() {
    _requests.clear();
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

  testWidgets('lists entries of every type', (tester) async {
    _install((req) async => http.Response(jsonEncode(_items), 200));
    await _pump(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await _settle(tester);
    expect(find.text('Audit Log — Pat Doe'), findsOneWidget);
    for (final i in _items) {
      expect(find.text(i['summary']!), findsOneWidget);
    }
    expect(find.text('Cara Giver • 10/1/2026 08:05'), findsNWidgets(5));
  });

  testWidgets('type chips reload with a filter', (tester) async {
    _install((req) async => http.Response('[]', 200));
    await _pump(tester);
    await _settle(tester);
    expect(find.text('No audit log entries for this client.'), findsOneWidget);
    await tester.tap(find.text('Incident reports'));
    await _settle(tester);
    expect(_requests.last.toString(), contains('INCIDENT_REPORT'));
    await tester.tap(find.text('All'));
    await _settle(tester);
    expect(_requests.length, 3);
  });

  testWidgets('date range filter applies and clears', (tester) async {
    _install((req) async => http.Response('[]', 200));
    await _pump(tester);
    await _settle(tester);
    await tester.tap(find.text('Filter by date range'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Filter by date range'), findsNothing);
    expect(find.byTooltip('Clear date filter'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear date filter'));
    await _settle(tester);
    expect(find.text('Filter by date range'), findsOneWidget);
    expect(_requests.length, 3);
  });

  testWidgets('error status and exception show messages', (tester) async {
    var calls = 0;
    _install((req) async {
      calls++;
      if (calls == 1) return http.Response('', 403);
      throw Exception('down');
    });
    await _pump(tester);
    await _settle(tester);
    expect(find.text('Failed to load audit log (403)'), findsOneWidget);
    await tester.tap(find.text('Activity logs'));
    await _settle(tester);
    expect(find.textContaining('Error loading audit log:'), findsOneWidget);
  });
}
