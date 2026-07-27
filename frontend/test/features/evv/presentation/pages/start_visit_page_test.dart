// Tests for StartVisitPage
// (lib/features/evv/presentation/pages/start_visit_page.dart)
//
// StartVisitPage loads the target patient (via ApiService, injectable
// http.Client) using the caregiver from UserProvider, lets the caregiver pick
// a service type, and continues to the check-in location page. These tests
// cover the load/render states, the service-type validation, and the
// continue-to-check-in navigation.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/features/evv/presentation/pages/start_visit_page.dart';

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const MethodChannel _connectivityChannel =
    MethodChannel('dev.fluttercommunity.plus/connectivity');

void _setupStubs() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(_secureStorageChannel, (call) async {
    if (call.method == 'readAll') return <String, String>{};
    return null;
  });
  m.setMockMethodCallHandler(_connectivityChannel, (call) async {
    if (call.method == 'check') return ['wifi'];
    return null;
  });
}

void _teardownStubs() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(_secureStorageChannel, null);
  m.setMockMethodCallHandler(_connectivityChannel, null);
}

UserSession _caregiver() => UserSession(
      id: 1,
      email: 'cg@careconnect.com',
      role: 'CAREGIVER',
      token: 'test-token',
      caregiverId: 1,
      name: 'Test Caregiver',
    );

String _patientsJson(int id) => jsonEncode([
      {
        'id': id,
        'firstName': 'Mary',
        'lastName': 'Johnson',
        'email': 'mary@careconnect.com',
        'phone': '555-0100',
        'dob': '1950-01-01',
        'relationship': 'parent',
        'address': {
          'line1': '123 Main St',
          'city': 'Richmond',
          'state': 'VA',
          'zip': '23220',
        },
      }
    ]);

/// Pumps the page on a tall surface — the start-visit form is a non-scrolling
/// Column that overflows the default 800x600 test viewport.
Future<void> _pump(WidgetTester tester,
    {UserSession? user, int patientId = 42}) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_host(user: user, patientId: patientId));
}

Widget _host({UserSession? user, int patientId = 42}) {
  final provider = UserProvider();
  if (user != null) provider.setUser(user);
  final router = GoRouter(
    initialLocation: '/start-visit',
    routes: [
      GoRoute(
          path: '/start-visit',
          builder: (_, __) => StartVisitPage(patientId: patientId)),
      GoRoute(
          path: '/evv/checkin-location',
          builder: (_, __) => const Scaffold(body: Text('CHECK-IN'))),
      GoRoute(
          path: '/evv/select-patient',
          builder: (_, __) => const Scaffold(body: Text('SELECT PATIENT'))),
      GoRoute(
          path: '/dashboard',
          builder: (_, __) => const Scaffold(body: Text('DASHBOARD'))),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _setupStubs();
  });

  tearDown(() {
    _teardownStubs();
    ApiService.debugResetHttpClient();
  });

  testWidgets('shows a loading indicator while the patient loads',
      (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientsJson(42), 200)));
    await _pump(tester, user: _caregiver());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('renders the "Start Visit" app bar', (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientsJson(42), 200)));
    await _pump(tester, user: _caregiver());
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Start Visit'), findsOneWidget);
  });

  testWidgets('renders the patient, service selector, and continue action',
      (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientsJson(42), 200)));
    await _pump(tester, user: _caregiver());
    await tester.pumpAndSettle();

    expect(find.text('Mary Johnson'), findsWidgets);
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(find.text('Continue to Check-In'), findsOneWidget);
  });

  testWidgets('warns when continuing without a service type', (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientsJson(42), 200)));
    await _pump(tester, user: _caregiver());
    await tester.pumpAndSettle();

    final continueBtn = find.text('Continue to Check-In');
    await tester.ensureVisible(continueBtn);
    await tester.tap(continueBtn);
    await tester.pump();

    expect(find.text('Please select a service type'), findsOneWidget);
  });

  testWidgets('selecting a service and continuing navigates to check-in',
      (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientsJson(42), 200)));
    await _pump(tester, user: _caregiver());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personal Care').last);
    await tester.pumpAndSettle();

    final continueBtn = find.text('Continue to Check-In');
    await tester.ensureVisible(continueBtn);
    await tester.tap(continueBtn);
    await tester.pumpAndSettle();

    expect(find.text('CHECK-IN'), findsOneWidget);
  });

  testWidgets('shows an error with Try Again when the API returns 500',
      (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response('server error', 500)));
    await _pump(tester, user: _caregiver());
    await tester.pumpAndSettle();
    expect(find.text('Try Again'), findsOneWidget);
  });

  testWidgets('shows an error state when the patient id is not in the list',
      (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientsJson(7), 200)));
    await _pump(tester, user: _caregiver());
    await tester.pumpAndSettle();
    expect(find.text('Try Again'), findsOneWidget);
  });

  testWidgets('shows an error when there is no authenticated user',
      (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientsJson(42), 200)));
    await _pump(tester); // no user
    await tester.pumpAndSettle();
    expect(find.text('Try Again'), findsOneWidget);
  });
}
