// More happy-path tests for StartVisitPage
// (lib/features/evv/presentation/pages/start_visit_page.dart): the loaded
// form, the not-found and error states, and Continue to Check-In.
import 'dart:convert';

import 'package:care_connect_app/features/evv/presentation/pages/start_visit_page.dart';
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
  late http.Response Function(http.Request) handler;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    handler = (_) => http.Response(
        jsonEncode([
          'not-a-map',
          {
            'patient': {
              'id': 7,
              'firstName': 'Ada',
              'lastName': 'Byron',
              'address': {
                'line1': '1 Main St',
                'line2': 'Apt 2',
                'city': 'Town',
                'state': 'MD',
                'zip': '20000',
              },
            },
          },
          {'id': 8, 'firstName': 'Flat', 'lastName': 'Row', 'maNumber': 'MA1'},
          {
            'patient': 'weird',
            'id': 9,
            'firstName': 'Odd',
            'lastName': 'Shape',
          },
        ]),
        200);
    ApiService.debugSetHttpClient(
        MockClient((request) async => handler(request)));
  });

  tearDown(ApiService.debugResetHttpClient);

  Future<GoRouter> pumpPage(WidgetTester tester, int patientId,
      {int? scheduledVisitId}) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (_, __) => StartVisitPage(
              patientId: patientId, scheduledVisitId: scheduledVisitId),
        ),
        GoRoute(
          path: '/evv/checkin-location',
          builder: (_, state) =>
              Scaffold(body: Text('checkin ${state.uri.query}')),
        ),
        GoRoute(
          path: '/evv/select-patient',
          builder: (_, __) => const Scaffold(body: Text('select patient')),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (_, __) => const Scaffold(body: Text('dashboard')),
        ),
      ],
    );
    await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(
          mockUser: MockUser(id: 1, role: 'CAREGIVER', caregiverId: 3)),
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('shows the patient, address and generated MA number',
      (tester) async {
    await pumpPage(tester, 7);
    expect(find.text('Ada Byron'), findsOneWidget);
    expect(find.text('MA000000007'), findsOneWidget);
    expect(find.text('1 Main St, Apt 2, Town, MD, 20000'), findsOneWidget);
  });

  testWidgets('continuing without a service type asks for one',
      (tester) async {
    await pumpPage(tester, 7);
    await tester.tap(find.text('Continue to Check-In'));
    await tester.pump();
    expect(find.text('Please select a service type'), findsOneWidget);
  });

  testWidgets('choosing a service type continues to check-in with the '
      'scheduled visit', (tester) async {
    await pumpPage(tester, 7, scheduledVisitId: 55);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Respite Care').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to Check-In'));
    await tester.pumpAndSettle();
    expect(find.textContaining('patientId=7'), findsOneWidget);
    expect(find.textContaining('scheduledVisitId=55'), findsOneWidget);
  });

  testWidgets('a flat patient row without an address says so',
      (tester) async {
    await pumpPage(tester, 8);
    expect(find.text('Flat Row'), findsOneWidget);
    expect(find.text('MA1'), findsOneWidget);
    expect(find.text('Address not available'), findsOneWidget);
  });

  testWidgets('a row whose patient is not a map is read flat', (tester) async {
    await pumpPage(tester, 9);
    expect(find.text('Odd Shape'), findsOneWidget);
  });

  testWidgets('an unknown patient shows the error state and Try Again reloads',
      (tester) async {
    await pumpPage(tester, 99);
    expect(find.text('Error Loading Patient'), findsOneWidget);
    expect(find.textContaining('Patient not found'), findsOneWidget);
    handler = (_) => http.Response('[]', 500);
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Failed to load patient details: 500'),
        findsOneWidget);
  });

  testWidgets('Cancel goes to the caregiver dashboard', (tester) async {
    await pumpPage(tester, 7);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('dashboard'), findsOneWidget);
  });
}
