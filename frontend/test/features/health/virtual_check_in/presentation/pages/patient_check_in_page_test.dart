// PatientVirtualCheckIn's Unified Health Data entry point (#263): the card on
// the Virtual Check-In page is how a patient reaches Health Data.
//
// The page's check-in behaviour itself is covered by
// test/features/health/virtual_check_in/patient_check_in_page_test.dart; this
// file covers the Health Data card, using the same logged-out provider and
// camera stub so nothing reaches the network or a device.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:care_connect_app/features/health/virtual_check_in/presentation/pages/patient_check_in_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../../../mock_user_provider.dart';

class _LoggedOutUserProvider extends MockUserProvider {
  @override
  UserSession? get user => null;
}

const _camera = MethodChannel('plugins.flutter.io/camera');

Future<GoRouter> _pump(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: '/virtual-checkin',
    routes: [
      GoRoute(path: '/virtual-checkin', builder: (_, __) => const PatientVirtualCheckIn()),
      GoRoute(
        path: '/health-data',
        builder: (_, __) => const Scaffold(body: Text('health data screen')),
      ),
    ],
  );
  await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
    value: _LoggedOutUserProvider(),
    child: MaterialApp.router(routerConfig: router),
  ));
  // Bounded pumps: the page has animations that never settle.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return router;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_camera, (call) async {
      if (call.method == 'availableCameras') return <dynamic>[];
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_camera, null);
  });

  testWidgets('the Unified Health Data card is on the page, with its description', (tester) async {
    await _pump(tester);

    final card = find.text('Unified Health Data');
    await tester.scrollUntilVisible(card, 200, scrollable: find.byType(Scrollable).first);

    expect(card, findsOneWidget);
    expect(find.text('View health records from connected sources'), findsOneWidget);
  });

  testWidgets('tapping the card opens Health Data', (tester) async {
    await _pump(tester);
    final card = find.text('Unified Health Data');
    await tester.scrollUntilVisible(card, 200, scrollable: find.byType(Scrollable).first);

    await tester.tap(card);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('health data screen'), findsOneWidget);
  });
}
