// Tests for CheckinLocationPage
// (lib/features/evv/presentation/pages/checkin_location_page.dart)
//
// CheckinLocationPage loads the target patient (via ApiService, backed by an
// injectable http.Client) using the caregiver from UserProvider, then renders
// the EVV check-in surface. These tests exercise the load/render states —
// loading, patient found, patient not found, unauthenticated, and API error —
// which cover the bulk of the page without invoking the geolocator platform
// channel (the GPS-capture path is triggered only by an explicit button tap).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/features/evv/presentation/pages/checkin_location_page.dart';

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const MethodChannel _connectivityChannel =
    MethodChannel('dev.fluttercommunity.plus/connectivity');

void _setupStubs() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
    if (call.method == 'readAll') return <String, String>{};
    return null;
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_connectivityChannel, (call) async {
    if (call.method == 'check') return ['wifi'];
    return null;
  });
}

void _teardownStubs() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, null);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_connectivityChannel, null);
}

UserSession _caregiver() => UserSession(
      id: 1,
      email: 'cg@careconnect.com',
      role: 'CAREGIVER',
      token: 'test-token',
      caregiverId: 1,
      name: 'Test Caregiver',
    );

String _patientListJson(int id) => jsonEncode([
      {
        'id': id,
        'firstName': 'Mary',
        'lastName': 'Johnson',
        'email': 'mary@careconnect.com',
        'phone': '555-0100',
        'dob': '1950-01-01',
        'relationship': 'parent',
      }
    ]);

Widget _host({UserSession? user}) {
  final provider = UserProvider();
  if (user != null) provider.setUser(user);
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: const MaterialApp(
      home: CheckinLocationPage(patientId: 42, serviceType: 'Personal Care'),
    ),
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
        MockClient((_) async => http.Response(_patientListJson(42), 200)));
    await tester.pumpWidget(_host(user: _caregiver()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('renders the Check-In Location app bar', (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientListJson(42), 200)));
    await tester.pumpWidget(_host(user: _caregiver()));
    await tester.pumpAndSettle();
    expect(find.text('Check-In Location'), findsOneWidget);
  });

  testWidgets('renders the GPS and patient-address options when the patient loads',
      (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientListJson(42), 200)));
    await tester.pumpWidget(_host(user: _caregiver()));
    await tester.pumpAndSettle();

    expect(find.textContaining('GPS'), findsWidgets);
    expect(find.textContaining('Patient Address'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an error state when the patient is not in the list',
      (tester) async {
    // The list contains a different patient id than the page requested (42).
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientListJson(7), 200)));
    await tester.pumpWidget(_host(user: _caregiver()));
    await tester.pumpAndSettle();

    expect(find.text('Try Again'), findsOneWidget);
  });

  testWidgets('shows an error state when the API returns 500', (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response('server error', 500)));
    await tester.pumpWidget(_host(user: _caregiver()));
    await tester.pumpAndSettle();

    expect(find.text('Try Again'), findsOneWidget);
  });

  testWidgets('shows an error state when there is no authenticated user',
      (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientListJson(42), 200)));
    await tester.pumpWidget(_host()); // no user set
    await tester.pumpAndSettle();

    // _loadPatientDetails throws "User not authenticated", surfacing the
    // error UI with its Try Again action.
    expect(find.text('Try Again'), findsOneWidget);
  });

  testWidgets('offers a Cancel action in the app bar', (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientListJson(42), 200)));
    await tester.pumpWidget(_host(user: _caregiver()));
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsOneWidget);
  });
}
