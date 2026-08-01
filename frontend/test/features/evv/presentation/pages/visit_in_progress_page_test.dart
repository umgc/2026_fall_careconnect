// Tests for VisitInProgressPage
// (lib/features/evv/presentation/pages/visit_in_progress_page.dart)
//
// VisitInProgressPage loads the visit's patient (via ApiService, injectable
// http.Client) and runs a 1-second Timer.periodic elapsed-time clock while the
// visit is active. Because a periodic timer never "settles", these tests drive
// the frame loop with explicit pump(Duration) calls instead of pumpAndSettle,
// and unmount at the end so dispose() cancels the timer. They cover the
// load/render states, the ticking clock, both location-format branches, and
// the "Ready to Check Out" navigation.

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
import 'package:care_connect_app/features/evv/presentation/pages/visit_in_progress_page.dart';

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
        'address': {
          'line1': '123 Main St',
          'city': 'Richmond',
          'state': 'VA',
          'zip': '23220',
        },
      }
    ]);

VisitInProgressPage _page({
  int patientId = 42,
  String locationType = 'gps',
  double? latitude = 38.900000,
  double? longitude = -77.000000,
}) =>
    VisitInProgressPage(
      patientId: patientId,
      serviceType: 'Personal Care',
      locationType: locationType,
      latitude: latitude,
      longitude: longitude,
    );

Widget _host({UserSession? user, required VisitInProgressPage page}) {
  final provider = UserProvider();
  if (user != null) provider.setUser(user);
  final router = GoRouter(
    initialLocation: '/visit-in-progress',
    routes: [
      GoRoute(path: '/visit-in-progress', builder: (_, __) => page),
      GoRoute(
          path: '/evv/select-patient',
          builder: (_, __) => const Scaffold(body: Text('SELECT PATIENT'))),
      GoRoute(
          path: '/evv/checkout-location',
          builder: (_, __) => const Scaffold(body: Text('CHECKOUT'))),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Resolves the async patient load without ticking the 1s clock (<1s total).
Future<void> _pumpLoad(WidgetTester tester) async {
  await tester.pump(); // first frame — kicks off the load
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// Unmounts the page so dispose() cancels the periodic timer.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
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

  group('VisitInProgressPage - load states', () {
    testWidgets('shows a loading indicator on the first frame', (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await _pumpLoad(tester);
      await _unmount(tester);
    });

    testWidgets('renders the "Visit in Progress" app bar', (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await _pumpLoad(tester);
      expect(find.widgetWithText(AppBar, 'Visit in Progress'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('renders patient, service, and the check-out action',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await _pumpLoad(tester);
      expect(find.text('Mary Johnson'), findsWidgets);
      expect(find.text('Personal Care'), findsWidgets);
      expect(find.text('Ready to Check Out'), findsOneWidget);
      expect(find.text('00:00:00'), findsOneWidget); // clock starts at zero
      await _unmount(tester);
    });

    testWidgets('shows an error with Try Again when the API returns 500',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response('server error', 500)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await _pumpLoad(tester);
      expect(find.text('Try Again'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('shows an error when the patient id is not in the list',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(7), 200)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await _pumpLoad(tester);
      expect(find.text('Try Again'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('shows an error when there is no authenticated user',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(page: _page())); // no user
      await _pumpLoad(tester);
      expect(find.text('Try Again'), findsOneWidget);
      await _unmount(tester);
    });
  });

  group('VisitInProgressPage - elapsed clock', () {
    testWidgets('ticks the elapsed time forward every second', (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await _pumpLoad(tester);
      expect(find.text('00:00:00'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:00:03'), findsOneWidget);

      await _unmount(tester);
    });
  });

  group('VisitInProgressPage - location formatting', () {
    testWidgets('formats a GPS check-in location with coordinates',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await _pumpLoad(tester);
      expect(find.textContaining('GPS: 38.900000, -77.000000'), findsWidgets);
      await _unmount(tester);
    });

    testWidgets('formats a patient-address check-in location', (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(
        user: _caregiver(),
        page: _page(locationType: 'patient_address'),
      ));
      await _pumpLoad(tester);
      expect(find.textContaining('123 Main St, Richmond, VA, 23220'),
          findsWidgets);
      await _unmount(tester);
    });
  });

  group('VisitInProgressPage - navigation', () {
    testWidgets('Ready to Check Out navigates to the checkout page',
        (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(_patientsJson(42), 200)));
      await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
      await _pumpLoad(tester);

      final btn = find.text('Ready to Check Out');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('CHECKOUT'), findsOneWidget);
      await _unmount(tester);
    });
  });
}
