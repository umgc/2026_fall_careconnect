// Flow tests for QrScreen and EmergencyInfo
// (lib/features/emergency_qr/qr_screen.dart): view / download / share /
// print actions with url_launcher, share_plus and http mocked, plus the
// plain-text QR payload.

import 'package:care_connect_app/features/emergency_qr/qr_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

bool _canLaunch = true;
final List<String> _launched = [];
bool _shareThrows = false;

void _channels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in [
    'plugins.flutter.io/url_launcher',
    'plugins.flutter.io/url_launcher_android',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
      if (call.method == 'canLaunch') return _canLaunch;
      if (call.method == 'launch') {
        _launched.add('${(call.arguments as Map)['url']}');
      }
      return true;
    });
  }
  messenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/share'),
    (call) async {
      if (_shareThrows) throw PlatformException(code: 'x');
      return 'dev.fluttercommunity.plus/share/success';
    },
  );
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.toString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
  await tester.pumpWidget(const MaterialApp(
    home: QrScreen(payload: 'DATA', emergencyId: 'emg-1', patientId: 7),
  ));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    _canLaunch = true;
    _launched.clear();
    _shareThrows = false;
    _channels();
  });

  testWidgets('view and print launch the PDF url', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('View Emergency PDF'));
    await _settle(tester);
    await tester.tap(find.text('Print Emergency PDF'));
    await _settle(tester);
    expect(_launched, hasLength(2));
    expect(_launched.first, contains('emg-1'));
  });

  testWidgets('view and print report when no viewer is available',
      (tester) async {
    _canLaunch = false;
    await _pump(tester);
    await tester.tap(find.text('View Emergency PDF'));
    await _settle(tester);
    expect(find.text('Cannot open PDF viewer'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(QrScreen)))
        .removeCurrentSnackBar();
    await _settle(tester);
    await tester.tap(find.text('Print Emergency PDF'));
    await _settle(tester);
    expect(find.text('Cannot open print dialog'), findsOneWidget);
  });

  testWidgets('download reports a failed status', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      await tester.tap(find.text('Download Emergency PDF'));
      await _settle(tester);
    }, () => MockClient((req) async => http.Response('', 404)));
    expect(find.text('Failed to download PDF'), findsOneWidget);
  });

  testWidgets('share sends the emergency info; errors are shown',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Share Emergency Info'));
    await _settle(tester);
    _shareThrows = true;
    await tester.tap(find.text('Share Emergency Info'));
    await _settle(tester);
    expect(find.textContaining('Error sharing'), findsOneWidget);
  });

  test('EmergencyInfo payload lists allergies or none', () {
    final info = EmergencyInfo(
      firstName: 'Ana',
      lastName: 'Diaz',
      bloodType: 'O+',
      dob: DateTime(1950, 2, 3),
      age: 76,
      gender: 'F',
      id: 'p-1',
      allergiesCritical: const ['Penicillin', 'Latex'],
      contacts: const [],
      secureToken: 't',
    );
    final payload = info.qrPayload();
    expect(payload, contains('PATIENT: Ana Diaz'));
    expect(payload, contains('Penicillin - Latex'));
    expect(payload, contains('None'));

    final none = EmergencyInfo(
      firstName: 'B',
      lastName: 'C',
      bloodType: 'A-',
      dob: DateTime(1960),
      age: 66,
      gender: 'M',
      id: 'p-2',
      allergiesCritical: const [],
      contacts: const [],
      secureToken: 't',
    );
    expect(none.qrPayload(), contains('NONE REPORTED'));
  });
}
