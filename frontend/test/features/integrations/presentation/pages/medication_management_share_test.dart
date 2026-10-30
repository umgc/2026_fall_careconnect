// MedicationManagementScreen
// (lib/features/integrations/presentation/pages/medication_management.dart):
// sharing the medication list as a PDF and the camera-permission refusal
// before barcode scanning.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/integrations/presentation/pages/medication_management.dart';
import 'package:care_connect_app/providers/user_provider.dart';

const _share = MethodChannel('dev.fluttercommunity.plus/share');
const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');
const _permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
const _connectivityStatus =
    MethodChannel('dev.fluttercommunity.plus/connectivity_status');

final _meds = [
  {
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
  },
  {
    'id': 'med-002',
    'brandName': 'Ibuprofen',
    'genericName': 'Not specified',
    'strength': 'Not specified',
    'startDate': null,
    'endDate': '2024-12-31',
  },
];

Widget _wrap() => ChangeNotifierProvider<UserProvider>.value(
      value: UserProvider()
        ..setUser(UserSession(
          id: 1,
          email: 'cg@example.com',
          role: 'CAREGIVER',
          token: 'tok',
        )),
      child: const MaterialApp(home: MedicationManagementScreen()),
    );

void main() {
  late Directory tmp;
  late List<MethodCall> shared;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('med_share_');
    shared = <MethodCall>[];
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_share, (call) async {
      shared.add(call);
      return 'dev.fluttercommunity.plus/share/success';
    });
    m.setMockMethodCallHandler(_pathProvider, (call) async => tmp.path);
    m.setMockMethodCallHandler(_permissions, (call) async {
      if (call.method == 'requestPermissions') {
        final list = (call.arguments as List).cast<int>();
        return {for (final p in list) p: 0}; // denied
      }
      return 0;
    });
    m.setMockMethodCallHandler(_secureStorage, (call) async => null);
    m.setMockMethodCallHandler(
        _connectivity, (call) async => call.method == 'check' ? ['wifi'] : null);
    m.setMockMethodCallHandler(_connectivityStatus, (call) async => null);
  });

  tearDown(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final c in [
      _share,
      _pathProvider,
      _permissions,
      _secureStorage,
      _connectivity,
      _connectivityStatus,
    ]) {
      m.setMockMethodCallHandler(c, null);
    }
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('share builds a PDF of the list and hands it to the share sheet',
      (tester) async {
    SharedPreferences.setMockInitialValues({'medications': jsonEncode(_meds)});
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();
    expect(find.text('Aspirin'), findsWidgets);

    await tester.tap(find.byIcon(Icons.share).first);
    for (var i = 0; i < 20 && shared.isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(shared, isNotEmpty);
    expect(File('${tmp.path}/medications_list.pdf').existsSync(), isTrue);
  });

  testWidgets('share failure shows the PDF error snackbar', (tester) async {
    SharedPreferences.setMockInitialValues({'medications': jsonEncode(_meds)});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, (call) async => null);
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.share).first);
    for (var i = 0;
        i < 20 && find.byType(SnackBar).evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('Error generating PDF. Please try again.'),
        findsOneWidget);
  });

  testWidgets('scanning without camera permission explains why',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan Medication Barcode'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Camera permission is required to scan barcodes'),
        findsOneWidget);
  });
}
