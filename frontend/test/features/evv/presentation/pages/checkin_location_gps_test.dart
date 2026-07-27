// GPS-path tests for CheckinLocationPage
// (lib/features/evv/presentation/pages/checkin_location_page.dart)
//
// Exercises the "Get Current GPS Location" flow by overriding
// GeolocatorPlatform.instance with a fake, which is platform-independent
// (works identically on the Linux CI runner and locally, unlike mocking the
// platform-specific geolocator method channels). Covers the EVV federal
// compliance branches: service-disabled, permission-denied, the Issue #62
// accuracy > 500m guardrail, and a successful high-accuracy capture.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/features/evv/presentation/pages/checkin_location_page.dart';

/// Platform-independent fake for the geolocator plugin.
class _FakeGeolocator extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
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

Position _positionWithAccuracy(double accuracy) => Position(
      longitude: -77.0,
      latitude: 39.0,
      timestamp: DateTime(2026, 7, 21),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

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

Widget _host() {
  final provider = UserProvider()..setUser(_caregiver());
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: const MaterialApp(
      home: CheckinLocationPage(patientId: 42, serviceType: 'Personal Care'),
    ),
  );
}

/// Loads the page to the patient-ready state and taps the GPS capture button.
/// Uses timed pumps (not pumpAndSettle) so the transient error SnackBar is
/// still on screen when the caller asserts; [settle] is true only for the
/// success path, which navigates away.
Future<void> _pumpAndTapGps(WidgetTester tester, {bool settle = false}) async {
  await tester.pumpWidget(_host());
  await tester.pumpAndSettle();

  final gpsButton = find.widgetWithText(ElevatedButton, 'Get My GPS Location');
  await tester.ensureVisible(gpsButton);
  await tester.tap(gpsButton);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(); // start the async GPS flow
    await tester.pump(const Duration(milliseconds: 300)); // surface the SnackBar
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final realGeolocator = GeolocatorPlatform.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _setupStubs();
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response(_patientListJson(42), 200)));
  });

  tearDown(() {
    _teardownStubs();
    ApiService.debugResetHttpClient();
    GeolocatorPlatform.instance = realGeolocator;
  });

  testWidgets('warns and flags failure when location services are disabled',
      (tester) async {
    GeolocatorPlatform.instance = _FakeGeolocator(serviceEnabled: false);
    await _pumpAndTapGps(tester);

    expect(find.textContaining('Location services are disabled'), findsOneWidget);
    // Page stays open so the caregiver can pick an alternative.
    expect(find.byType(CheckinLocationPage), findsOneWidget);
  });

  testWidgets('warns when location permission is denied', (tester) async {
    GeolocatorPlatform.instance =
        _FakeGeolocator(permission: LocationPermission.denied);
    await _pumpAndTapGps(tester);

    expect(find.textContaining('Location permissions are denied'), findsOneWidget);
    expect(find.byType(CheckinLocationPage), findsOneWidget);
  });

  testWidgets('warns when location permission is permanently denied',
      (tester) async {
    GeolocatorPlatform.instance =
        _FakeGeolocator(permission: LocationPermission.deniedForever);
    await _pumpAndTapGps(tester);

    expect(find.textContaining('permanently denied'), findsOneWidget);
    expect(find.byType(CheckinLocationPage), findsOneWidget);
  });

  testWidgets('flags an EVV compliance warning when accuracy exceeds 500m (Issue #62)',
      (tester) async {
    GeolocatorPlatform.instance = _FakeGeolocator(
      permission: LocationPermission.whileInUse,
      position: _positionWithAccuracy(750), // > 500m threshold
    );
    await _pumpAndTapGps(tester);

    expect(find.textContaining('may not meet EVV compliance'), findsOneWidget);
    expect(find.byType(CheckinLocationPage), findsOneWidget);
  });

  testWidgets('surfaces an error when position capture throws', (tester) async {
    GeolocatorPlatform.instance = _FakeGeolocator(
      permission: LocationPermission.whileInUse,
      throwOnPosition: true,
    );
    await _pumpAndTapGps(tester);

    expect(find.textContaining('Failed to get current location'), findsOneWidget);
    expect(find.byType(CheckinLocationPage), findsOneWidget);
  });

  testWidgets('routes to visit-progress on a high-accuracy GPS capture',
      (tester) async {
    GeolocatorPlatform.instance = _FakeGeolocator(
      permission: LocationPermission.whileInUse,
      position: _positionWithAccuracy(10), // well within threshold
    );

    // The success path navigates via GoRouter's context.push, so host the page
    // in a router that declares the visit-progress destination.
    final provider = UserProvider()..setUser(_caregiver());
    final router = GoRouter(
      initialLocation: '/checkin',
      routes: [
        GoRoute(
          path: '/checkin',
          builder: (_, __) => const CheckinLocationPage(
              patientId: 42, serviceType: 'Personal Care'),
        ),
        GoRoute(
          path: '/evv/visit-progress',
          builder: (_, __) => const Scaffold(body: Text('VISIT PROGRESS')),
        ),
      ],
    );
    await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    final gpsButton = find.widgetWithText(ElevatedButton, 'Get My GPS Location');
    await tester.ensureVisible(gpsButton);
    await tester.tap(gpsButton);
    await tester.pumpAndSettle();

    expect(find.text('VISIT PROGRESS'), findsOneWidget);
    expect(find.byType(CheckinLocationPage), findsNothing);
  });
}
