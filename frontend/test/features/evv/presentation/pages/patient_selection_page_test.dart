// Tests for PatientSelectionPage
// (lib/features/evv/presentation/pages/patient_selection_page.dart)
//
// PatientSelectionPage loads the caregiver's patients (via ApiService,
// injectable http.Client) and lists them for selection; tapping a patient
// starts a visit. These tests cover the load/list/empty/error/unauthenticated
// states and the patient-selection navigation.

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
import 'package:care_connect_app/features/evv/presentation/pages/patient_selection_page.dart';

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const MethodChannel _connectivityChannel =
    MethodChannel('dev.fluttercommunity.plus/connectivity');

void _setupStubs() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_secureStorageChannel, (call) async {
    if (call.method == 'readAll') return <String, String>{};
    return null;
  });
  messenger.setMockMethodCallHandler(_connectivityChannel, (call) async {
    if (call.method == 'check') return ['wifi'];
    return null;
  });
}

void _teardownStubs() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_secureStorageChannel, null);
  messenger.setMockMethodCallHandler(_connectivityChannel, null);
}

UserSession _caregiver() => UserSession(
      id: 1,
      email: 'cg@careconnect.com',
      role: 'CAREGIVER',
      token: 'test-token',
      caregiverId: 1,
      name: 'Test Caregiver',
    );

Map<String, dynamic> _patient(int id, String first, String last) => {
      'id': id,
      'firstName': first,
      'lastName': last,
      'email': '$first@careconnect.com',
      'phone': '555-0100',
      'dob': '1950-01-01',
      'relationship': 'parent',
    };

String _patientsJson() =>
    jsonEncode([_patient(42, 'Mary', 'Johnson'), _patient(43, 'John', 'Doe')]);

Widget _host({UserSession? user}) {
  final provider = UserProvider();
  if (user != null) provider.setUser(user);
  final router = GoRouter(
    initialLocation: '/select-patient',
    routes: [
      GoRoute(
          path: '/select-patient', builder: (_, __) => const PatientSelectionPage()),
      GoRoute(
          path: '/evv/start-visit',
          builder: (_, __) => const Scaffold(body: Text('START VISIT'))),
      GoRoute(
          path: '/add-patient',
          builder: (_, __) => const Scaffold(body: Text('ADD PATIENT'))),
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

  testWidgets('shows a loading indicator while patients load', (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientsJson(), 200)));
    await tester.pumpWidget(_host(user: _caregiver()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('renders the "Select Patient" app bar', (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientsJson(), 200)));
    await tester.pumpWidget(_host(user: _caregiver()));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Select Patient'), findsOneWidget);
  });

  testWidgets('lists the caregiver\'s patients', (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientsJson(), 200)));
    await tester.pumpWidget(_host(user: _caregiver()));
    await tester.pumpAndSettle();
    expect(find.text('Mary Johnson'), findsOneWidget);
    expect(find.text('John Doe'), findsOneWidget);
  });

  testWidgets('tapping a patient navigates to Start Visit', (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientsJson(), 200)));
    await tester.pumpWidget(_host(user: _caregiver()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mary Johnson'));
    await tester.pumpAndSettle();
    expect(find.text('START VISIT'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no patients',
      (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response('[]', 200)));
    await tester.pumpWidget(_host(user: _caregiver()));
    await tester.pumpAndSettle();
    expect(find.text('No Patients Found'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Add Patient'), findsOneWidget);
  });

  testWidgets('shows an error with Try Again when the API returns 500',
      (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response('server error', 500)));
    await tester.pumpWidget(_host(user: _caregiver()));
    await tester.pumpAndSettle();
    expect(find.text('Try Again'), findsOneWidget);
  });

  testWidgets('Try Again reloads the patient list after an error',
      (tester) async {
    var calls = 0;
    ApiService.debugSetHttpClient(MockClient((_) async {
      calls++;
      return calls == 1
          ? http.Response('server error', 500)
          : http.Response(_patientsJson(), 200);
    }));
    await tester.pumpWidget(_host(user: _caregiver()));
    await tester.pumpAndSettle();
    expect(find.text('Try Again'), findsOneWidget);

    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(find.text('Mary Johnson'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('shows an error when there is no authenticated user',
      (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientsJson(), 200)));
    await tester.pumpWidget(_host()); // no user
    await tester.pumpAndSettle();
    expect(find.text('Try Again'), findsOneWidget);
  });
}
