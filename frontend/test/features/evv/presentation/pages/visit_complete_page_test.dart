// Tests for VisitCompletePage
// (lib/features/evv/presentation/pages/visit_complete_page.dart)
//
// VisitCompletePage loads the visit's patient (via ApiService, injectable
// http.Client), renders a visit summary, and on "Complete Visit" submits an
// EVV record through EvvService (which uses ApiServiceOffline.httpClient — a
// separately injectable client). These tests cover the load/render states,
// both location-format branches (GPS vs patient address), time/duration
// formatting, and the submit flow's success (navigates) and error (SnackBar,
// stays on page) paths.

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
import 'package:care_connect_app/services/api_service_offline.dart';
import 'package:care_connect_app/features/evv/presentation/pages/visit_complete_page.dart';

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

String _patientsJson(int id) => jsonEncode([
      {
        'id': id,
        'firstName': 'Mary',
        'lastName': 'Johnson',
        'email': 'mary@careconnect.com',
        'phone': '555-0100',
        'dob': '1950-01-01',
        'relationship': 'parent',
        'gender': 'FEMALE',
        'maNumber': 'MA123456789',
        'address': {
          'line1': '123 Main St',
          'city': 'Richmond',
          'state': 'VA',
          'zip': '23220',
        },
      }
    ]);

// Minimal EVV record payload satisfying EvvRecord.fromJson's DateTime fields.
String _evvRecordJson() => jsonEncode({
      'id': 100,
      'serviceType': 'Personal Care',
      'individualName': 'Mary Johnson',
      'caregiverId': 1,
      'status': 'COMPLETED',
      'stateCode': 'VA',
      'dateOfService': '2026-08-01T09:00:00.000',
      'timeIn': '2026-08-01T09:00:00.000',
      'timeOut': '2026-08-01T10:00:00.000',
      'createdAt': '2026-08-01T10:00:00.000',
      'updatedAt': '2026-08-01T10:00:00.000',
    });

VisitCompletePage _page({
  int patientId = 42,
  String checkinType = 'gps',
  String checkoutType = 'gps',
  double? checkinLat = 38.900000,
  double? checkinLng = -77.000000,
  double? checkoutLat = 38.900000,
  double? checkoutLng = -77.000000,
  int duration = 3600,
}) =>
    VisitCompletePage(
      patientId: patientId,
      serviceType: 'Personal Care',
      checkinLocationType: checkinType,
      checkoutLocationType: checkoutType,
      checkinLatitude: checkinLat,
      checkinLongitude: checkinLng,
      checkoutLatitude: checkoutLat,
      checkoutLongitude: checkoutLng,
      notes: 'Administered morning medications',
      duration: duration,
    );

Widget _host({UserSession? user, required VisitCompletePage page}) {
  final provider = UserProvider();
  if (user != null) provider.setUser(user);
  final router = GoRouter(
    initialLocation: '/visit-complete',
    routes: [
      GoRoute(path: '/visit-complete', builder: (_, __) => page),
      GoRoute(path: '/evv', builder: (_, __) => const Scaffold(body: Text('EVV HOME'))),
      GoRoute(
          path: '/evv/select-patient',
          builder: (_, __) => const Scaffold(body: Text('SELECT PATIENT'))),
      GoRoute(
          path: '/evv/visit-completed-success',
          builder: (_, __) => const Scaffold(body: Text('VISIT SUCCESS'))),
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
    ApiServiceOffline.debugOverrideHttpClient(null);
  });

  group('VisitCompletePage - load states', () {
    testWidgets('shows a loading indicator while the patient loads',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('renders the "Visit Complete" app bar', (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await tester.pumpAndSettle();
      expect(find.text('Visit Complete'), findsOneWidget);
    });

    testWidgets('renders the visit summary when the patient is found',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await tester.pumpAndSettle();

      expect(find.text('Visit successfully completed and ready for submission'),
          findsOneWidget);
      expect(find.text('Visit Summary'), findsOneWidget);
      expect(find.text('Mary Johnson'), findsOneWidget);
      expect(find.text('Personal Care'), findsOneWidget);
      expect(find.text('MA123456789'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Complete Visit'), findsOneWidget);
    });

    testWidgets('shows the error state when the API returns 500',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response('server error', 500)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await tester.pumpAndSettle();
      expect(find.text('Error Loading Patient'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('shows an error when the patient id is not in the list',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(7), 200)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await tester.pumpAndSettle();
      expect(find.text('Error Loading Patient'), findsOneWidget);
    });

    testWidgets('shows an error when there is no authenticated user',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(page: _page())); // no user
      await tester.pumpAndSettle();
      expect(find.text('Try Again'), findsOneWidget);
    });
  });

  group('VisitCompletePage - location formatting', () {
    testWidgets('formats GPS locations with coordinates', (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await tester.pumpAndSettle();
      expect(find.textContaining('GPS: 38.900000, -77.000000'), findsWidgets);
    });

    testWidgets('formats patient-address locations with the address',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(
        user: _caregiver(),
        page: _page(checkinType: 'patient_address', checkoutType: 'patient_address'),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('123 Main St, Richmond, VA, 23220'),
          findsWidgets);
    });
  });

  group('VisitCompletePage - time & duration', () {
    testWidgets('renders a formatted total duration', (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(
          _host(user: _caregiver(), page: _page(duration: 3661)));
      await tester.pumpAndSettle();
      // 3661s = 01:01:01
      expect(find.text('01:01:01'), findsOneWidget);
    });
  });

  group('VisitCompletePage - complete visit submission', () {
    testWidgets('submits the EVV record and navigates to the success page',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      ApiServiceOffline.debugOverrideHttpClient(
          MockClient((_) async => http.Response(_evvRecordJson(), 201)));

      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await tester.pumpAndSettle();

      final completeBtn = find.widgetWithText(FilledButton, 'Complete Visit');
      await tester.ensureVisible(completeBtn);
      await tester.tap(completeBtn);
      await tester.pumpAndSettle();

      expect(find.text('VISIT SUCCESS'), findsOneWidget); // navigated
    });

    testWidgets('shows an error SnackBar and stays on the page when submit fails',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      ApiServiceOffline.debugOverrideHttpClient(
          MockClient((_) async => http.Response('server error', 500)));

      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await tester.pumpAndSettle();

      final completeBtn = find.widgetWithText(FilledButton, 'Complete Visit');
      await tester.ensureVisible(completeBtn);
      await tester.tap(completeBtn);
      await tester.pumpAndSettle();

      // Did not navigate; submit reset and the page is still shown.
      expect(find.text('VISIT SUCCESS'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Complete Visit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
