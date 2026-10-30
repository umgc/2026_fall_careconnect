// More happy-path tests for PatientSelectionPage
// (lib/features/evv/presentation/pages/patient_selection_page.dart): nested,
// flat and odd patient rows with full addresses, selecting a patient, and the
// empty list's Add Patient action.
import 'dart:convert';

import 'package:care_connect_app/features/evv/presentation/pages/patient_selection_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';

void main() {
  late List<dynamic> rows;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    rows = [
      {
        'patient': {
          'id': 7,
          'firstName': 'Ada',
          'lastName': 'Byron',
          'address': {
            'line1': '1 Main',
            'line2': 'Apt 2',
            'city': 'Town',
            'state': 'MD',
            'zip': '20000',
          },
        },
      },
      {'id': 8, 'firstName': 'Flat', 'lastName': 'Row'},
      {'patient': 'odd', 'id': 9, 'firstName': 'Odd', 'lastName': 'One'},
      'not-a-map',
    ];
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(jsonEncode(rows), 200)));
  });

  tearDown(ApiService.debugResetHttpClient);

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/select',
      routes: [
        GoRoute(
            path: '/select', builder: (_, __) => const PatientSelectionPage()),
        GoRoute(
          path: '/evv/start-visit',
          builder: (_, s) => Scaffold(body: Text('start ${s.uri.query}')),
        ),
        GoRoute(
          path: '/add-patient',
          builder: (_, __) => const Scaffold(body: Text('add patient page')),
        ),
      ],
    );
    await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(
          mockUser: MockUser(id: 1, role: 'CAREGIVER', caregiverId: 3)),
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lists each row shape with its address and opens a visit',
      (tester) async {
    await pumpPage(tester);
    expect(find.textContaining('1 Main, Apt 2, Town, MD, 20000'),
        findsOneWidget);
    expect(find.textContaining('Address not available'), findsWidgets);
    expect(find.textContaining('Odd'), findsWidgets);
    await tester.tap(find.textContaining('Ada').first);
    await tester.pumpAndSettle();
    expect(find.text('start patientId=7'), findsOneWidget);
  });

  testWidgets('an empty list offers Add Patient', (tester) async {
    rows = [];
    await pumpPage(tester);
    await tester.tap(find.text('Add Patient'));
    await tester.pumpAndSettle();
    expect(find.text('add patient page'), findsOneWidget);
  });
}
