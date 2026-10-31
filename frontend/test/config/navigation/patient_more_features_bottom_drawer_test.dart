// Tests for PatientMoreFeaturesBottomDrawerWidget
// (lib/config/navigation/patient_more_features_bottom_drawer.dart).
//
// Each item closes the drawer and opens its page in a TitledMaterialPageRoute,
// which gives the browser tab a page name (WCAG 2.4.2). The destination pages
// need real services, so the probe reads the pushed route's title without
// building them.
import 'package:care_connect_app/config/navigation/patient_more_features_bottom_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/titled_route_probe.dart';

void main() {
  late TitledRouteProbe probe;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  Future<void> openDrawer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navKey = GlobalKey<NavigatorState>();
    probe = TitledRouteProbe();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      navigatorObservers: [probe],
      home: const Scaffold(body: Text('Home')),
    ));
    navKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(
          body: SingleChildScrollView(
              child: PatientMoreFeaturesBottomDrawerWidget())),
    ));
    await tester.pumpAndSettle();
  }

  const items = {
    'SOS': 'Emergency Assistance',
    'Medication Tracker': 'Medication Tracker',
    'Calendar Assistant': 'Calendar',
    'Informed Delivery': 'Informed Delivery',
    'Virtual Check-In': 'Virtual Check-In',
  };

  for (final entry in items.entries) {
    testWidgets('"${entry.key}" opens a page titled "${entry.value}"',
        (tester) async {
      await openDrawer(tester);
      expect(await probe.tapAndReadTitle(tester, find.text(entry.key).first),
          entry.value);
    });
  }
}
