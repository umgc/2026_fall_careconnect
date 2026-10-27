// Page-title tests for MedicationManagementScreen (lib/features/integrations/presentation/pages/medication_management.dart).
// Setup copied from medication_management_test.dart; adds the page-title
// checks (WCAG 2.4.2) for this PR's TitledMaterialPageRoute changes.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/features/integrations/presentation/pages/medication_management.dart';
import '../../../../helpers/titled_route_probe.dart';

/// Wraps [child] with a UserProvider (needed by the embedded CommonDrawer).
Widget _wrap(Widget child) {
  final provider = UserProvider();
  provider.setUser(UserSession(
    id: 1,
    email: 'cg@example.com',
    role: 'CAREGIVER',
    token: 'tok',
  ));
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp(navigatorObservers: [probe], home: child),
  );
}

TitledRouteProbe probe = TitledRouteProbe();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    probe = TitledRouteProbe();
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    // permission_handler: camera (1) -> granted (1).
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (call) async {
        if (call.method == 'requestPermissions') return {1: 1};
        if (call.method == 'checkPermissionStatus') return 1;
        return null;
      },
    );
  });

  testWidgets(
      'with camera permission, scanning opens a page titled '
      '"Barcode Scanner"', (tester) async {
    await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
    await tester.pumpAndSettle();
    expect(
        await probe.tapAndReadTitle(
            tester, find.text('Scan Medication Barcode').first),
        'Barcode Scanner');
  });
}
