// Page-title test for WearablesScreen (lib/features/integrations/presentation/pages/wearables_screen.dart).
// Setup copied from wearables_screen_test.dart; adds the page-title
// checks (WCAG 2.4.2) for this PR's TitledMaterialPageRoute changes.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/features/integrations/presentation/pages/wearables_screen.dart';
import '../../../../helpers/titled_route_probe.dart';

/// Wraps [child] with a UserProvider (needed by CommonDrawer) and a
/// MaterialApp.
Widget _wrap(Widget child) {
  final provider = UserProvider();
  provider.setUser(UserSession(
    id: 2,
    email: 'cg2@example.com',
    role: 'CAREGIVER',
    token: 'tok2',
  ));
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp(navigatorObservers: [probe], home: child),
  );
}

/// Sets a tall test viewport and registers the teardown to reset it.
Future<void> _setTallViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// Standard setUp for all tests - mocks secure storage and connectivity channels.
void _setUpChannels() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'read') return null;
      if (call.method == 'containsKey') return false;
      if (call.method == 'write') return null;
      if (call.method == 'delete') return null;
      return null;
    },
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async {
      if (call.method == 'check') return ['wifi'];
      return null;
    },
  );
}

TitledRouteProbe probe = TitledRouteProbe();

void main() {
  setUp(() {
    _setUpChannels();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the add button opens a page titled "Add Device"',
      (tester) async {
    await _setTallViewport(tester);
    probe = TitledRouteProbe();
    await tester.pumpWidget(_wrap(const WearablesScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        await probe.tapAndReadTitle(tester, find.byIcon(Icons.add).first),
        'Add Device');
  });
}
