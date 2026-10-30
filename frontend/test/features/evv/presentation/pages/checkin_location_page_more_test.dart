// More happy-path tests for CheckinLocationPage
// (lib/features/evv/presentation/pages/checkin_location_page.dart): the
// patient-address reason dialog, the manual address checks, the error and
// not-found states, and GPS refusals that the GPS tests do not reach.
import 'dart:convert';

import 'package:care_connect_app/features/evv/presentation/pages/checkin_location_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';

class _Geo extends GeolocatorPlatform with MockPlatformInterfaceMixin {
  _Geo(this.permission, {this.throwOnCheck = false});
  final LocationPermission permission;
  final bool throwOnCheck;

  @override
  Future<bool> isLocationServiceEnabled() async {
    if (throwOnCheck) throw Exception('no gps');
    return true;
  }

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => permission;
}

void main() {
  late http.Response Function(http.Request) handler;
  late GeolocatorPlatform originalGeo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    originalGeo = GeolocatorPlatform.instance;
    handler = (_) => http.Response(
        jsonEncode([
          {
            'patient': {
              'id': 7,
              'firstName': 'Ada',
              'lastName': 'Byron',
              'address': {'line1': '1 Main St', 'city': 'Town', 'zip': '1'},
            },
          },
          {'id': 8, 'firstName': 'Flat', 'lastName': 'Row'},
          {'patient': 'odd', 'id': 9, 'firstName': 'Odd', 'lastName': 'One'},
        ]),
        200);
    ApiService.debugSetHttpClient(
        MockClient((request) async => handler(request)));
  });

  tearDown(() {
    ApiService.debugResetHttpClient();
    GeolocatorPlatform.instance = originalGeo;
  });

  Future<void> pumpPage(WidgetTester tester, int patientId) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/checkin',
      routes: [
        GoRoute(
          path: '/checkin',
          builder: (_, __) => CheckinLocationPage(
              patientId: patientId,
              serviceType: 'Personal Care',
              scheduledVisitId: 4),
        ),
        GoRoute(
          path: '/evv/visit-progress',
          builder: (_, s) => Scaffold(body: Text('progress ${s.uri.query}')),
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
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  testWidgets('the patient address asks for a reason, then continues',
      (tester) async {
    await pumpPage(tester, 7);
    expect(find.text('Ada Byron'), findsWidgets);
    await tapText(tester, 'Select Patient Address');
    expect(find.text('Location Reason Required'), findsOneWidget);
    // The default reason is preselected; pick another one anyway.
    await tester.tap(find.text('Home visit – patient address used').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Indoors – no GPS signal').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('locationType=PATIENT_ADDRESS'), findsOneWidget);
    expect(find.textContaining('noGpsReason=INDOOR_LOCATION'), findsOneWidget);
    expect(find.textContaining('scheduledVisitId=4'), findsOneWidget);
  });

  testWidgets('the reason dialog can be cancelled', (tester) async {
    await pumpPage(tester, 8);
    expect(find.text('Address not available'), findsWidgets);
    await tapText(tester, 'Select Patient Address');
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(find.text('Location Reason Required'), findsNothing);
  });

  testWidgets('a manual address needs an address and a reason',
      (tester) async {
    await pumpPage(tester, 9);
    await tapText(tester, 'Use Manual Address');
    expect(find.text('Please enter an address before continuing.'),
        findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(CheckinLocationPage)))
        .clearSnackBars();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '9 Side Rd');
    await tapText(tester, 'Use Manual Address');
    expect(find.text('Please select a reason for manual location entry.'),
        findsOneWidget);

    await tester.ensureVisible(find.text('Reason GPS Not Used'));
    await tester.tap(find.text('Reason GPS Not Used'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Community or facility visit').last);
    await tester.pumpAndSettle();
    await tapText(tester, 'Use Manual Address');
    expect(find.textContaining('locationType=MANUAL'), findsOneWidget);
    expect(find.textContaining('manualAddress=9%20Side%20Rd'), findsOneWidget);
  });

  testWidgets('permanently denied GPS falls back to the reason dialog',
      (tester) async {
    GeolocatorPlatform.instance = _Geo(LocationPermission.deniedForever);
    await pumpPage(tester, 7);
    await tapText(tester, 'Get My GPS Location');
    expect(find.textContaining('permanently denied'), findsOneWidget);
    await tapText(tester, 'Select Patient Address');
    // After a failed GPS attempt no reason is preselected.
    final continueButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Continue'));
    expect(continueButton.onPressed, isNull);
  });

  testWidgets('a GPS error is reported', (tester) async {
    GeolocatorPlatform.instance =
        _Geo(LocationPermission.always, throwOnCheck: true);
    await pumpPage(tester, 7);
    await tapText(tester, 'Get My GPS Location');
    expect(find.textContaining('Failed to get current location'),
        findsOneWidget);
  });

  testWidgets('an unknown patient shows the error state and Try Again reloads',
      (tester) async {
    await pumpPage(tester, 99);
    expect(find.textContaining('Patient not found'), findsOneWidget);
    handler = (_) => http.Response('[]', 503);
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Failed to load patient details: 503'),
        findsOneWidget);
  });

  testWidgets('Cancel goes to the caregiver dashboard', (tester) async {
    await pumpPage(tester, 7);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('dashboard'), findsOneWidget);
  });
}
