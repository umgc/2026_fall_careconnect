// Page-title tests for VisitInProgressPage (lib/features/evv/presentation/pages/visit_in_progress_page.dart).
// Setup copied from visit_in_progress_page_test.dart; adds the page-title
// checks (WCAG 2.4.2) for this PR's TitledMaterialPageRoute changes.

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
import '../../../../helpers/titled_route_probe.dart';

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
    observers: [probe],
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

TitledRouteProbe probe = TitledRouteProbe();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _setupStubs();
    probe = TitledRouteProbe();
  });

  tearDown(() {
    _teardownStubs();
    ApiService.debugResetHttpClient();
  });

  testWidgets('"File Incident Report" opens a page titled "Report Incident"',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientsJson(42), 200)));
    await tester.pumpWidget(_host(user: _caregiver(), page: _page()));
    await _pumpLoad(tester);
    final button = find.text('File Incident Report');
    await tester.ensureVisible(button);
    await tester.pump();
    expect(await probe.tapAndReadTitle(tester, button), 'Report Incident');
    await _unmount(tester);
  });
}
