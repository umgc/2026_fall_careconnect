// Tests for CaregiverMoreFeaturesBottomDrawerWidget
// (lib/config/navigation/caregiver_more_features_bottom_drawer.dart).
//
// Each item closes the drawer and opens its page in a TitledMaterialPageRoute,
// which gives the browser tab a page name (WCAG 2.4.2). The destination pages
// need real services, so the probe reads the pushed route's title without
// building them.
import 'package:care_connect_app/config/navigation/caregiver_more_features_bottom_drawer.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/titled_route_probe.dart';

import '../../mock_user_provider.dart';

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

  Future<void> openDrawer(WidgetTester tester, String role) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navKey = GlobalKey<NavigatorState>();
    probe = TitledRouteProbe();
    await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(
          mockUser: MockUser(id: 1, role: role, caregiverId: 42)),
      child: MaterialApp(
        navigatorKey: navKey,
        navigatorObservers: [probe],
        home: const Scaffold(body: Text('Home')),
      ),
    ));
    navKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(
          body: SingleChildScrollView(
              child: CaregiverMoreFeaturesBottomDrawerWidget())),
    ));
    await tester.pumpAndSettle();
  }

  const items = {
    'Calendar Assistant': 'Calendar',
    'Invoice Assistant': 'Invoice Dashboard',
    'Medical Notetaker': 'Notetaker Search',
    'AI review queue': 'AI Review Queue',
    'Settings': 'Settings',
  };

  for (final entry in items.entries) {
    testWidgets('"${entry.key}" opens a page titled "${entry.value}"',
        (tester) async {
      await openDrawer(tester, 'ADMIN');
      expect(await probe.tapAndReadTitle(tester, find.text(entry.key).first),
          entry.value);
    });
  }

  testWidgets('the AI review queue shows for a caregiver (REVIEW_AI_HOLDS)',
      (tester) async {
    await openDrawer(tester, 'CAREGIVER');
    expect(find.text('AI review queue'), findsOneWidget);
  });

  testWidgets(
      'the AI review queue is hidden from a role without '
      'REVIEW_AI_HOLDS (patient)', (tester) async {
    await openDrawer(tester, 'PATIENT');
    expect(find.text('AI review queue'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });
}
