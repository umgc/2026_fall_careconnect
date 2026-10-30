// Widget tests for FamilyPatientsPage
// (lib/features/dashboard/presentation/pages/family_member_list_page.dart):
// list, empty and error states and navigation to a patient dashboard.

import 'dart:convert';

import 'package:care_connect_app/features/dashboard/presentation/pages/family_member_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

late http.Response Function() _response;
final _client = MockClient((_) async => _response());

Future<void> _pump(WidgetTester tester) async {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const FamilyPatientsPage()),
      GoRoute(
        path: '/family-patient-dashboard/:id',
        builder: (_, s) => Text('Dashboard ${s.pathParameters['id']}'),
      ),
    ],
  );
  await http.runWithClient(() async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }, () => _client);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  testWidgets('lists accessible patients and opens a dashboard',
      (tester) async {
    _response = () => http.Response(
          jsonEncode([
            {'id': 4, 'name': 'nora Hill', 'email': 'n@x.test', 'phone': '1'},
            {'id': 5},
          ]),
          200,
        );
    await _pump(tester);
    expect(find.text('nora Hill'), findsOneWidget);
    expect(find.text('N'), findsOneWidget);
    expect(find.text('Email: n@x.test'), findsOneWidget);
    expect(find.text('Phone: 1'), findsOneWidget);
    expect(find.text('Unknown Patient'), findsOneWidget);
    expect(find.text('Read-Only Access'), findsNWidgets(2));
    await tester.tap(find.text('nora Hill'));
    await tester.pumpAndSettle();
    expect(find.text('Dashboard 4'), findsOneWidget);
  });

  testWidgets('shows empty state', (tester) async {
    _response = () => http.Response('[]', 200);
    await _pump(tester);
    expect(find.text('No patients accessible'), findsOneWidget);
  });

  testWidgets('shows error and retries', (tester) async {
    _response = () => http.Response('{"error":"nope"}', 500);
    await _pump(tester);
    expect(find.textContaining('Error: '), findsOneWidget);
    _response = () => http.Response('[]', 200);
    await http.runWithClient(() async {
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }, () => _client);
    expect(find.text('No patients accessible'), findsOneWidget);
  });
}
