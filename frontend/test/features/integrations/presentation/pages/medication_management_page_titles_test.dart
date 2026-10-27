// Page-title tests for MedicationManagementScreen (lib/features/integrations/presentation/pages/medication_management.dart).
// Setup copied from medication_management_test.dart; adds the page-title
// checks (WCAG 2.4.2) for this PR's TitledMaterialPageRoute changes.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

/// A comprehensive medication fixture that exercises every conditional branch
/// in _buildMedicationList (dosage, timeToTake, takeWith, doNotTakeWith,
/// startDate, endDate) and _formatDateRange / _formatDate.
final _medicationFull = {
  'id': 'med-001',
  'brandName': 'Aspirin',
  'genericName': 'Acetylsalicylic acid',
  'strength': '100mg',
  'dosage': '1 tablet',
  'frequency': 'Daily',
  'timeToTake': 'Morning',
  'takeWith': 'Water',
  'doNotTakeWith': 'Alcohol',
  'startDate': '2024-01-01',
  'endDate': '2024-12-31',
};

/// A minimal medication (no optional fields) to cover the null-fallback branches.
final _medicationMinimal = {
  'id': 'med-002',
  'brandName': 'Ibuprofen',
  'genericName': null,
  'strength': null,
};

/// Medication with only startDate (no endDate) to cover "From X" branch.
final _medicationStartOnly = {
  'id': 'med-003',
  'brandName': 'Tylenol',
  'genericName': 'Acetaminophen',
  'strength': '500mg',
  'dosage': '',
  'frequency': '',
  'timeToTake': '',
  'takeWith': '',
  'doNotTakeWith': '',
  'startDate': '2024-06-01',
  'endDate': null,
};

/// Medication with only endDate (no startDate) to cover "Until X" branch.
final _medicationEndOnly = {
  'id': 'med-004',
  'brandName': 'Metformin',
  'genericName': 'Metformin HCl',
  'strength': '850mg',
  'dosage': '',
  'frequency': '',
  'timeToTake': '',
  'takeWith': '',
  'doNotTakeWith': '',
  'startDate': null,
  'endDate': '2025-03-01',
};

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
