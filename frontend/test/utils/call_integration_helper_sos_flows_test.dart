// SOS flow tests for CallIntegrationHelper.sendSOSEmergencyAlert
// (lib/utils/call_integration_helper.dart): location lookup outcomes via a
// fake GeolocatorPlatform, the SOS POST result (success / rejected / network
// error) and the confirmation dialog. HTTP is mocked with http.runWithClient.

import 'dart:convert';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/utils/call_integration_helper.dart';
import 'package:care_connect_app/widgets/hybrid_video_call_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mock_user_provider.dart';

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
  Future<Position> getCurrentPosition(
      {LocationSettings? locationSettings}) async {
    if (throwOnPosition) throw Exception('gps failure');
    return Position(
      longitude: -76.9,
      latitude: 38.98,
      timestamp: DateTime(2026, 10, 1),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

const _patient = {
  'patient': {'id': 7, 'firstName': 'Ana', 'lastName': 'Diaz'},
};

void main() {
  late GeolocatorPlatform original;
  late Map<String, dynamic> lastBody;

  setUpAll(() => original = GeolocatorPlatform.instance);
  tearDownAll(() => GeolocatorPlatform.instance = original);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
  });

  MockClient client(int status) => MockClient((req) async {
        lastBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response('{}', status);
      });

  Future<BuildContext> host(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    late BuildContext ctx;
    await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(builder: (c) {
            ctx = c;
            return const SizedBox();
          }),
        ),
      ),
    ));
    return ctx;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('success sends GPS location and shows the confirmation',
      (tester) async {
    GeolocatorPlatform.instance = _FakeGeolocator();
    await http.runWithClient(() async {
      final ctx = await host(tester);
      final done = CallIntegrationHelper.sendSOSEmergencyAlert(
        context: ctx,
        currentUser: _patient,
        additionalInfo: 'Fell in kitchen',
      );
      await settle(tester);
      await done;
      await settle(tester);
    }, () => client(201));
    expect(lastBody['location'], contains('Lat: 38.98'));
    expect(lastBody['additionalInfo'], 'Fell in kitchen');
    expect(find.text('SOS Alert Sent'), findsOneWidget);
    expect(find.text('Info: Fell in kitchen'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('SOS Alert Sent'), findsNothing);
  });

  testWidgets('confirmation can start a video call', (tester) async {
    GeolocatorPlatform.instance =
        _FakeGeolocator(permission: LocationPermission.deniedForever);
    await http.runWithClient(() async {
      final ctx = await host(tester);
      final done = CallIntegrationHelper.sendSOSEmergencyAlert(
          context: ctx, currentUser: {'id': 3, 'name': 'Ben'});
      await settle(tester);
      await done;
      await settle(tester);
    }, () => client(200));
    expect(lastBody['location'], 'Location permission permanently denied');
    expect(lastBody['additionalInfo'],
        'Emergency situation - needs urgent response');
    await tester.tap(find.text('Start Video Call'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(HybridVideoCallWidget), findsOneWidget);
  });

  testWidgets('rejected alert and location fallbacks', (tester) async {
    for (final fake in [
      _FakeGeolocator(serviceEnabled: false),
      _FakeGeolocator(
          permission: LocationPermission.denied,
          requested: LocationPermission.denied),
      _FakeGeolocator(throwOnPosition: true),
    ]) {
      GeolocatorPlatform.instance = fake;
      await http.runWithClient(() async {
        final ctx = await host(tester);
        final done = CallIntegrationHelper.sendSOSEmergencyAlert(
            context: ctx, currentUser: null);
        await settle(tester);
        await done;
        await settle(tester);
      }, () => client(500));
      expect(find.textContaining('Failed to send SOS alert (500)'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
    expect(lastBody['location'], contains('Location unavailable'));
  });

  testWidgets('network error reports it', (tester) async {
    GeolocatorPlatform.instance = _FakeGeolocator();
    await http.runWithClient(() async {
      final ctx = await host(tester);
      final done = CallIntegrationHelper.sendSOSEmergencyAlert(
          context: ctx, currentUser: _patient);
      await settle(tester);
      await done;
      await settle(tester);
    }, () => MockClient((_) async => throw Exception('offline')));
    expect(find.textContaining('Network error sending SOS alert'),
        findsOneWidget);
  });
}
