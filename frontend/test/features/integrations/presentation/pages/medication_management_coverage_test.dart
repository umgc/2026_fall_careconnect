// Additional coverage for MedicationManagementScreen and BarcodeScannerScreen
// (lib/features/integrations/presentation/pages/medication_management.dart):
// the barcode scan flow (camera permission granted, scanner screen with a
// fake MobileScannerPlatform, FDA lookup success / not found / error /
// duplicate) and the scanner screen's own controls.

import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/features/integrations/presentation/pages/medication_management.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _permissionChannel =
    MethodChannel('flutter.baseflow.com/permissions/methods');

/// In-memory MobileScannerPlatform so the scanner widget can start without
/// a real camera. Barcodes can be pushed through [emit].
class _FakeScannerPlatform extends MobileScannerPlatform {
  final StreamController<BarcodeCapture?> _barcodes =
      StreamController<BarcodeCapture?>.broadcast();
  final List<String> calls = <String>[];

  void emit(String raw) =>
      _barcodes.add(BarcodeCapture(barcodes: [Barcode(rawValue: raw)]));

  @override
  Stream<BarcodeCapture?> get barcodesStream => _barcodes.stream;

  @override
  Stream<TorchState> get torchStateStream => const Stream<TorchState>.empty();

  @override
  Stream<double> get zoomScaleStateStream => const Stream<double>.empty();

  @override
  Widget buildCameraView() => const SizedBox.expand(key: Key('fake-camera'));

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    calls.add('start');
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(640, 480),
      numberOfCameras: 2,
    );
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> toggleTorch() async => calls.add('toggleTorch');

  @override
  Future<void> updateScanWindow(Rect? window) async {}

  @override
  Future<void> resetZoomScale() async {}

  @override
  Future<void> setZoomScale(double zoomScale) async {}

  @override
  Future<Set<CameraLensType>> getSupportedLenses({CameraFacing? facing}) async =>
      {CameraLensType.normal};

  @override
  Future<void> dispose() async => calls.add('dispose');
}

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
    child: MaterialApp(home: child),
  );
}

Map<String, dynamic> _fdaResult() => {
      'results': [
        {
          'brand_name': 'Scanned Brand',
          'generic_name': 'Scanned Generic',
          'dosage_form_name': 'TABLET',
          'labeler_name': 'Acme Pharma',
          'active_ingredients': [
            {'name': 'X', 'strength': '10', 'unit': 'mg'},
          ],
        },
      ],
    };

void _grantCamera({bool granted = true}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_permissionChannel, (call) async {
    if (call.method == 'requestPermissions') {
      final perms = (call.arguments as List).cast<int>();
      return {for (final p in perms) p: granted ? 1 : 0};
    }
    if (call.method == 'checkPermissionStatus') return granted ? 1 : 0;
    return null;
  });
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Opens the add sheet, taps "Scan Barcode", then emits [code] from the
/// fake scanner. [fda] serves the FDA lookup.
Future<void> _scan(
  WidgetTester tester,
  _FakeScannerPlatform scanner,
  String code,
  MockClient fda,
) async {
  await http.runWithClient(() async {
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan Barcode'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.byType(BarcodeScannerScreen), findsOneWidget);

    scanner.emit(code);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }, () => fda);
}

void main() {
  late _FakeScannerPlatform scanner;
  late MobileScannerPlatform original;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    original = MobileScannerPlatform.instance;
    scanner = _FakeScannerPlatform();
    MobileScannerPlatform.instance = scanner;
    _grantCamera();
  });

  tearDown(() {
    MobileScannerPlatform.instance = original;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_permissionChannel, null);
  });

  testWidgets('scan -> FDA hit shows details; dates picked and medication added',
      (tester) async {
    _tall(tester);
    final requested = <String>[];
    await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
    await tester.pumpAndSettle();

    await _scan(
      tester,
      scanner,
      ' 12345-678 ',
      MockClient((req) async {
        requested.add(req.url.toString());
        return http.Response(jsonEncode(_fdaResult()), 200);
      }),
    );

    expect(requested.single, contains('12345-678'));
    expect(find.byType(BarcodeScannerScreen), findsNothing);
    expect(find.text('Scanned Brand'), findsOneWidget);
    expect(find.text('Scanned Generic'), findsOneWidget);
    expect(find.text('10 mg'), findsOneWidget);

    // Pick start date, then end date (whose picker is bounded by start).
    await tester.ensureVisible(find.text('Select Start Date (optional)'));
    await tester.tap(find.text('Select Start Date (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Start Date:'), findsOneWidget);

    await tester.ensureVisible(find.text('Select End Date (optional)'));
    await tester.tap(find.text('Select End Date (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.textContaining('End Date:'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Medication'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('medications'), contains('Scanned Brand'));
  });

  testWidgets('scan -> FDA 404 offers manual entry', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
    await tester.pumpAndSettle();

    await _scan(tester, scanner, '000',
        MockClient((req) async => http.Response('not found', 404)));

    expect(find.text('Medication not found. You can add it manually.'),
        findsOneWidget);
    await tester.tap(find.text('Add Manually'));
    await tester.pumpAndSettle();
    expect(find.text('Brand Name *'), findsOneWidget);
  });

  testWidgets('scan -> FDA empty results also reports not found',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
    await tester.pumpAndSettle();

    await _scan(
        tester,
        scanner,
        '111',
        MockClient((req) async =>
            http.Response(jsonEncode({'results': []}), 200)));

    expect(find.text('Medication not found. You can add it manually.'),
        findsOneWidget);
  });

  testWidgets('scan -> FDA server error shows lookup error', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
    await tester.pumpAndSettle();

    await _scan(tester, scanner, '999',
        MockClient((req) async => http.Response('oops', 500)));

    expect(find.text('Error looking up medication. Please try again.'),
        findsOneWidget);
    expect(find.text('Looking up medication...'), findsNothing);
  });

  testWidgets('scan of an existing medication warns about duplicates',
      (tester) async {
    _tall(tester);
    SharedPreferences.setMockInitialValues({
      'medications': jsonEncode([
        {
          'id': 'm1',
          'brandName': 'Scanned Brand',
          'genericName': 'Other',
          'strength': '5mg',
        },
      ]),
    });
    await tester.pumpWidget(_wrap(const MedicationManagementScreen()));
    await tester.pumpAndSettle();

    await _scan(tester, scanner, '12345',
        MockClient((req) async => http.Response(jsonEncode(_fdaResult()), 200)));

    expect(find.text('Duplicate Medication Warning'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Duplicate Medication Warning'), findsNothing);

    await _scan(tester, scanner, '12345',
        MockClient((req) async => http.Response(jsonEncode(_fdaResult()), 200)));
    await tester.tap(find.text('Add Anyway'));
    await tester.pumpAndSettle();
    expect(find.text('Duplicate Medication Warning'), findsNothing);
    expect(find.text('Scanned Generic'), findsOneWidget);
  });

  testWidgets('scanner screen controls toggle torch, pause/resume and cancel',
      (tester) async {
    _tall(tester);
    final scanned = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      BarcodeScannerScreen(onCodeScanned: scanned.add),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Scan Medication Barcode'), findsOneWidget);
    expect(find.text('Scanning for QR codes and barcodes'), findsOneWidget);
    expect(scanner.calls, contains('start'));

    // Torch toggle flips the icon.
    expect(find.byIcon(Icons.flash_off), findsOneWidget);
    await tester.tap(find.byIcon(Icons.flash_off));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.flash_on), findsOneWidget);

    // Pause -> play icon; scans are ignored while paused.
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(scanner.calls, contains('stop'));

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.pause), findsOneWidget);

    // Switch camera button.
    await tester.tap(find.byIcon(Icons.flip_camera_ios));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(BarcodeScannerScreen), findsNothing);
    expect(scanned, isEmpty);
  });
}
