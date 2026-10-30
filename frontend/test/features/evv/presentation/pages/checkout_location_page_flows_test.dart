// Interaction tests for CheckoutLocationPage
// (lib/features/evv/presentation/pages/checkout_location_page.dart):
// patient loading states, GPS capture branches (via a fake
// GeolocatorPlatform), patient-address and manual-address checkout.

import 'dart:convert';

import 'package:care_connect_app/features/evv/presentation/pages/checkout_location_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
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

import '../../../../mock_user_provider.dart';

class _FakeGeolocator extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  _FakeGeolocator({
    this.serviceEnabled = true,
    this.permission = LocationPermission.whileInUse,
    this.requested,
    this.throwOnPosition = false,
  });

  final bool serviceEnabled;
  final LocationPermission permission;
  final LocationPermission? requested;
  final bool throwOnPosition;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async =>
      requested ?? permission;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    if (throwOnPosition) throw Exception('gps failure');
    return Position(
      longitude: -76.6,
      latitude: 39.3,
      timestamp: DateTime(2026, 1, 1),
      accuracy: 12.5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

class _NoUserProvider extends MockUserProvider {
  @override
  UserSession? get user => null;
}

late http.Response Function() _patients;

String _patientList() => jsonEncode([
      'not-a-map',
      // Flat patient entry and a non-map "patient" value are both parsed
      // from the top-level object.
      {'id': 8, 'firstName': 'Flat', 'lastName': 'Entry'},
      {'id': 7, 'patient': 'unexpected', 'firstName': 'Odd', 'lastName': 'Row'},
      {
        'patient': {'id': 9, 'firstName': 'Other', 'lastName': 'Person'},
      },
      {
        'patient': {
          'id': 42,
          'firstName': 'Mary',
          'lastName': 'Johnson',
          'address': {
            'line1': '10 Elm St',
            'city': 'Bowie',
            'state': 'MD',
            'zip': '20715',
          },
        },
      },
    ]);

Widget _host({
  UserProvider? provider,
  double? checkinLat,
  String? checkinReason,
  double? checkinAccuracy,
  int? scheduledVisitId,
}) {
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(
        path: '/start',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () => context.push('/checkout'),
            child: const Text('Open Checkout'),
          ),
        ),
      ),
      GoRoute(
        path: '/checkout',
        builder: (_, __) => CheckoutLocationPage(
          patientId: 42,
          serviceType: 'Personal Care',
          locationType: checkinLat != null ? 'GPS' : 'PATIENT_ADDRESS',
          latitude: checkinLat,
          longitude: checkinLat != null ? -76.0 : null,
          notes: 'All good',
          duration: 3600,
          scheduledVisitId: scheduledVisitId,
          checkinNoGpsReason: checkinReason,
          checkinAccuracyM: checkinAccuracy,
        ),
      ),
      GoRoute(
        path: '/evv/visit-complete',
        builder: (_, state) => Scaffold(
          body: Text('complete ${state.uri.query}', key: const Key('done')),
        ),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const Scaffold(body: Text('Dashboard')),
      ),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider ??
        MockUserProvider(
          mockUser: MockUser(id: 1, role: 'CAREGIVER', caregiverId: 5),
        ),
    child: MaterialApp.router(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      routerConfig: router,
    ),
  );
}

Future<void> _open(WidgetTester tester, Widget host) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host);
  await tester.tap(find.text('Open Checkout'));
  await tester.pumpAndSettle();
}

String _completeQuery(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('done'))).data!;

Future<void> _tapButton(WidgetTester tester, String label) async {
  final f = find.text(label);
  await tester.ensureVisible(f);
  await tester.tap(f);
}

void main() {
  final realGeolocator = GeolocatorPlatform.instance;

  setUp(() {
    _patients = () => http.Response(_patientList(), 200);
    ApiService.debugSetHttpClient(MockClient((_) async => _patients()));
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  tearDown(() => GeolocatorPlatform.instance = realGeolocator);

  group('loading states', () {
    testWidgets('missing user shows error and Try Again retries',
        (tester) async {
      await _open(tester, _host(provider: _NoUserProvider()));
      expect(find.text('Error Loading Patient'), findsOneWidget);
      expect(find.textContaining('User not authenticated'), findsOneWidget);
      await _tapButton(tester, 'Try Again');
      await tester.pumpAndSettle();
      expect(find.text('Error Loading Patient'), findsOneWidget);
    });

    testWidgets('non-200 response shows status error', (tester) async {
      _patients = () => http.Response('x', 503);
      await _open(tester, _host());
      expect(find.textContaining('Failed to load patient details: 503'),
          findsOneWidget);
    });

    testWidgets('patient missing from list shows not-found error',
        (tester) async {
      _patients = () => http.Response(jsonEncode([]), 200);
      await _open(tester, _host());
      expect(find.textContaining('Patient not found'), findsOneWidget);
    });

    testWidgets('loads nested patient and shows address', (tester) async {
      await _open(tester, _host());
      expect(find.text('Mary Johnson'), findsWidgets);
      expect(find.textContaining('10 Elm St'), findsWidgets);
    });
  });

  group('app bar navigation', () {
    testWidgets('cancel goes to the caregiver dashboard', (tester) async {
      await _open(tester, _host());
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('back arrow pops the page', (tester) async {
      await _open(tester, _host());
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Open Checkout'), findsOneWidget);
    });
  });

  group('GPS checkout', () {
    Future<void> tapGps(WidgetTester tester) async {
      await _tapButton(tester, 'Get My GPS Location');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('success navigates with coordinates and check-in data',
        (tester) async {
      GeolocatorPlatform.instance = _FakeGeolocator();
      await _open(
        tester,
        _host(
          checkinLat: 39.0,
          checkinReason: 'INDOOR_LOCATION',
          checkinAccuracy: 30.0,
          scheduledVisitId: 77,
        ),
      );
      await tapGps(tester);
      await tester.pumpAndSettle();
      final q = Uri.splitQueryString(
          _completeQuery(tester).substring('complete '.length));
      expect(q['checkoutLocationType'], 'GPS');
      expect(q['checkoutLatitude'], '39.3');
      expect(q['checkoutLongitude'], '-76.6');
      expect(q['checkoutAccuracyM'], '12.5');
      expect(q['checkinLatitude'], '39.0');
      expect(q['checkinLongitude'], '-76.0');
      expect(q['checkinAccuracyM'], '30.0');
      expect(q['checkinNoGpsReason'], 'INDOOR_LOCATION');
      expect(q['scheduledVisitId'], '77');
      expect(q['duration'], '3600');
    });

    testWidgets('disabled location service shows error', (tester) async {
      GeolocatorPlatform.instance = _FakeGeolocator(serviceEnabled: false);
      await _open(tester, _host());
      await tapGps(tester);
      expect(find.textContaining('Location services are disabled'),
          findsOneWidget);
    });

    testWidgets('denied permission shows error', (tester) async {
      GeolocatorPlatform.instance =
          _FakeGeolocator(permission: LocationPermission.denied);
      await _open(tester, _host());
      await tapGps(tester);
      expect(find.textContaining('Location permissions are denied'),
          findsOneWidget);
    });

    testWidgets('permission granted on request continues to capture',
        (tester) async {
      GeolocatorPlatform.instance = _FakeGeolocator(
        permission: LocationPermission.denied,
        requested: LocationPermission.whileInUse,
      );
      await _open(tester, _host());
      await tapGps(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('done')), findsOneWidget);
    });

    testWidgets('permanently denied permission shows error', (tester) async {
      GeolocatorPlatform.instance =
          _FakeGeolocator(permission: LocationPermission.deniedForever);
      await _open(tester, _host());
      await tapGps(tester);
      expect(find.textContaining('permanently denied'), findsOneWidget);
    });

    testWidgets('position failure shows error then address needs a reason',
        (tester) async {
      GeolocatorPlatform.instance = _FakeGeolocator(throwOnPosition: true);
      await _open(tester, _host());
      await tapGps(tester);
      expect(find.textContaining('Failed to get current location'),
          findsOneWidget);

      // After a failed GPS attempt the reason is not pre-selected.
      await _tapButton(tester, 'Select Patient Address');
      await tester.pumpAndSettle();
      expect(find.text('Why is GPS not being used?'), findsOneWidget);
      final confirm = find.widgetWithText(ElevatedButton, 'Confirm');
      expect(tester.widget<ElevatedButton>(confirm).onPressed, isNull);

      await tester.tap(find.text('Select reason'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GPS signal timeout').last);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      final q = Uri.splitQueryString(
          _completeQuery(tester).substring('complete '.length));
      expect(q['checkoutLocationType'], 'PATIENT_ADDRESS');
      expect(q['checkoutNoGpsReason'], 'GPS_TIMEOUT');
    });
  });

  group('address checkout', () {
    testWidgets('patient address defaults to home visit reason',
        (tester) async {
      await _open(tester, _host());
      await _tapButton(tester, 'Select Patient Address');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
      await tester.pumpAndSettle();
      final q = Uri.splitQueryString(
          _completeQuery(tester).substring('complete '.length));
      expect(q['checkoutNoGpsReason'], 'HOME_VISIT_ADDRESS_USED');
    });

    testWidgets('cancelling the reason dialog stays on the page',
        (tester) async {
      await _open(tester, _host());
      await _tapButton(tester, 'Select Patient Address');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(find.byType(CheckoutLocationPage), findsOneWidget);
    });

    testWidgets('manual address validates address and reason',
        (tester) async {
      await _open(tester, _host());
      await _tapButton(tester, 'Use Manual Address');
      await tester.pump();
      expect(find.text('Please enter the visit address.'), findsOneWidget);
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .clearSnackBars();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Visit Address'),
        '5 Oak Ave',
      );
      await _tapButton(tester, 'Use Manual Address');
      await tester.pump();
      expect(find.text('Please select a reason for not using GPS.'),
          findsOneWidget);
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .clearSnackBars();
      await tester.pumpAndSettle();

      final reason = find.text('Reason GPS Not Used');
      await tester.ensureVisible(reason);
      await tester.tap(reason);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Community visit location').last);
      await tester.pumpAndSettle();
      await _tapButton(tester, 'Use Manual Address');
      await tester.pumpAndSettle();
      final q = Uri.splitQueryString(
          _completeQuery(tester).substring('complete '.length));
      expect(q['checkoutLocationType'], 'MANUAL');
      expect(q['checkoutManualAddress'], '5 Oak Ave');
      expect(q['checkoutNoGpsReason'], 'COMMUNITY_VISIT');
    });
  });
}
