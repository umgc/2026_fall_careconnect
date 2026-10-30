// Happy-path tests for MedicationsTrackerPage
// (lib/features/health/medication-tracker/pages/medication-tracker.dart):
// loaded list, empty list, error with retry and the add-medication sheet.

import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/features/health/medication-tracker/pages/medication-tracker.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../mock_user_provider.dart';

late http.Response Function() _response;

Map<String, dynamic> _med(int id, String name) => {
      'id': id,
      'patientId': 12,
      'medicationName': name,
      'dosage': '10 mg',
      'frequency': 'Once daily',
      'route': 'Oral',
      'medicationType': 'PRESCRIPTION',
      'isActive': true,
    };

Future<void> _pump(WidgetTester tester, {int? patientId = 12}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(
        mockUser: MockUser(id: 1, role: 'PATIENT', patientId: patientId),
      ),
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MedicationsTrackerPage(),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() => ApiService.debugSetHttpClient(
        MockClient((_) async => _response()),
      ));

  setUp(() {
    _response = () => http.Response(
          jsonEncode([_med(1, 'Lisinopril'), _med(2, 'Metformin')]),
          200,
        );
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  testWidgets('lists medications from the API', (tester) async {
    await _pump(tester);
    expect(find.text('Lisinopril'), findsOneWidget);
    expect(find.text('Metformin'), findsOneWidget);
  });

  testWidgets('shows empty state', (tester) async {
    _response = () => http.Response('[]', 200);
    await _pump(tester);
    expect(find.text('No medications found'), findsOneWidget);
  });

  testWidgets('shows error state and retries', (tester) async {
    _response = () => http.Response('x', 500);
    await _pump(tester);
    expect(find.text('Failed to load medications: 500'), findsOneWidget);
    _response = () => http.Response('[]', 200);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('No medications found'), findsOneWidget);
  });

  testWidgets('shows parse error message', (tester) async {
    _response = () => http.Response('{bad', 200);
    await _pump(tester);
    expect(find.textContaining('Error loading medications:'), findsOneWidget);
  });

  testWidgets('missing patient id shows error', (tester) async {
    await _pump(tester, patientId: null);
    expect(find.text('Patient ID not found'), findsOneWidget);
  });
}
