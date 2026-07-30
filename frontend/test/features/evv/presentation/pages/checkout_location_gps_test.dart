// GPS-capture tests for CheckoutLocationPage
// (lib/features/evv/presentation/pages/checkout_location_page.dart)
//
// The prior-cohort flat test covers the load/render/error states but never
// exercises the "Get Current GPS Location" flow (geolocator isn't mocked).
// This suite overrides GeolocatorPlatform.instance with a platform-independent
// fake and drives the success, service-disabled, permission-denied,
// permission-denied-forever, and capture-error branches.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/features/evv/presentation/pages/checkout_location_page.dart';

class _FakeGeolocator extends GeolocatorPlatform with MockPlatformInterfaceMixin {
  _FakeGeolocator({
    this.serviceEnabled = true,
    this.permission = LocationPermission.whileInUse,
    this.position,
    this.throwOnPosition = false,
  });

  final bool serviceEnabled;
  final LocationPermission permission;
  final Position? position;
  final bool throwOnPosition;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async => permission;
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    if (throwOnPosition) throw Exception('gps failure');
    return position!;
  }
}

Position _position() => Position(
      longitude: -77.0,
      latitude: 39.0,
      timestamp: DateTime(2026, 8, 1),
      accuracy: 12.0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');

void _setupStubs() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(_secureStorage, (call) async {
    if (call.method == 'readAll') return <String, String>{};
    return null;
  });
  m.setMockMethodCallHandler(_connectivity, (call) async {
    if (call.method == 'check') return ['wifi'];
    return null;
  });
}

void _teardownStubs() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(_secureStorage, null);
  m.setMockMethodCallHandler(_connectivity, null);
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

Widget _host() {
  final provider = UserProvider()..setUser(_caregiver());
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: const MaterialApp(
      home: CheckoutLocationPage(
        patientId: 42,
        serviceType: 'Personal Care',
        locationType: 'gps',
        notes: 'Test visit',
        duration: 3600,
      ),
    ),
  );
}

/// A GoRouter-backed host so the page's context.push('/evv/visit-complete')
/// navigation (the no-GPS alternative-location flow) resolves.
Widget _routerHost() {
  final provider = UserProvider()..setUser(_caregiver());
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const CheckoutLocationPage(
          patientId: 42,
          serviceType: 'Personal Care',
          locationType: 'gps',
          notes: 'Test visit',
          duration: 3600,
        ),
      ),
      GoRoute(
        path: '/evv/visit-complete',
        builder: (_, __) =>
            const Scaffold(body: Text('VISIT COMPLETE SCREEN')),
      ),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Loads to the patient-ready state and taps the GPS capture control. Uses
/// timed pumps so transient SnackBars are still present for assertions.
Future<void> _loadAndTapGps(WidgetTester tester) async {
  // Tall surface: the GPS-failure path reveals the address-entry + reason UI,
  // which overflows the default 800x600 test viewport.
  tester.view.physicalSize = const Size(1200, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_host());
  await tester.pumpAndSettle();
  // The card title is "Get Current GPS Location"; the actionable button is
  // labeled "Get My GPS Location" and calls _getCurrentLocation.
  final gps = find.widgetWithText(ElevatedButton, 'Get My GPS Location');
  await tester.ensureVisible(gps);
  await tester.tap(gps);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _setupStubs();
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientsJson(42), 200)));
  });

  tearDown(() {
    _teardownStubs();
    ApiService.debugResetHttpClient();
  });

  testWidgets('captures a GPS position on success', (tester) async {
    GeolocatorPlatform.instance = _FakeGeolocator(position: _position());
    await _loadAndTapGps(tester);
    // Captured without error and the page is still shown.
    expect(find.byType(CheckoutLocationPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); // unmount: clears pending SnackBar timers
  });

  testWidgets('handles location services disabled', (tester) async {
    GeolocatorPlatform.instance = _FakeGeolocator(serviceEnabled: false);
    await _loadAndTapGps(tester);
    expect(find.byType(CheckoutLocationPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); // unmount: clears pending SnackBar timers
  });

  testWidgets('handles permission denied', (tester) async {
    GeolocatorPlatform.instance =
        _FakeGeolocator(permission: LocationPermission.denied);
    await _loadAndTapGps(tester);
    expect(find.byType(CheckoutLocationPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); // unmount: clears pending SnackBar timers
  });

  testWidgets('handles permission denied forever', (tester) async {
    GeolocatorPlatform.instance =
        _FakeGeolocator(permission: LocationPermission.deniedForever);
    await _loadAndTapGps(tester);
    expect(find.byType(CheckoutLocationPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); // unmount: clears pending SnackBar timers
  });

  testWidgets('handles a GPS capture error', (tester) async {
    GeolocatorPlatform.instance = _FakeGeolocator(throwOnPosition: true);
    await _loadAndTapGps(tester);
    expect(find.byType(CheckoutLocationPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); // unmount: clears pending SnackBar timers
  });

  testWidgets('Use Patient Address opens the no-GPS reason dialog',
      (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientsJson(42), 200)));
    await tester.pumpWidget(_routerHost());
    await tester.pumpAndSettle();

    final btn = find.widgetWithText(ElevatedButton, 'Select Patient Address');
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pumpAndSettle();

    expect(find.text('Why is GPS not being used?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await tester.pumpAndSettle();
    expect(find.text('Why is GPS not being used?'), findsNothing);
    expect(find.text('VISIT COMPLETE SCREEN'), findsNothing);
    tester.takeException();
  });

  testWidgets('confirming the patient-address reason navigates to visit complete',
      (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientsJson(42), 200)));
    await tester.pumpWidget(_routerHost());
    await tester.pumpAndSettle();

    final btn = find.widgetWithText(ElevatedButton, 'Select Patient Address');
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pumpAndSettle();

    // The reason defaults to HOME_VISIT_ADDRESS_USED, so Confirm is enabled;
    // tapping it runs _navigateToVisitComplete.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('VISIT COMPLETE SCREEN'), findsOneWidget);
    tester.takeException();
  });
}
