// Coverage tests for QrScreen (lib/features/emergency_qr/qr_screen.dart):
// launcher errors while viewing / printing the PDF, a successful PDF
// download saved to the documents directory, and a download that throws.

import 'dart:io';

import 'package:care_connect_app/features/emergency_qr/qr_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _launcherChannels = [
  MethodChannel('plugins.flutter.io/url_launcher'),
  MethodChannel('plugins.flutter.io/url_launcher_android'),
];
const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

late Directory _tmp;

void _launcherThrows() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final c in _launcherChannels) {
    m.setMockMethodCallHandler(
        c, (call) async => throw PlatformException(code: 'launch_failed'));
  }
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
    home: QrScreen(payload: 'DATA', emergencyId: 'emg-9', patientId: 7),
  ));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() => _tmp = Directory.systemTemp.createTempSync('qr_cov_'));
  tearDownAll(() {
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  tearDown(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final c in [..._launcherChannels, _pathProvider]) {
      m.setMockMethodCallHandler(c, null);
    }
  });

  testWidgets('a launcher error while viewing is reported', (tester) async {
    _launcherThrows();
    await _pump(tester);
    await tester.tap(find.text('View Emergency PDF'));
    await _settle(tester);
    expect(find.textContaining('Error viewing PDF'), findsOneWidget);
  });

  testWidgets('a launcher error while printing is reported', (tester) async {
    _launcherThrows();
    await _pump(tester);
    await tester.tap(find.text('Print Emergency PDF'));
    await _settle(tester);
    expect(find.textContaining('Error printing PDF'), findsOneWidget);
  });

  testWidgets('a successful download is saved and announced',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, (call) async => _tmp.path);
    await http.runWithClient(() async {
      await _pump(tester);
      await tester.tap(find.text('Download Emergency PDF'));
      await tester.pump();
      expect(find.text('Downloading PDF...'), findsOneWidget);
      final done = find.textContaining('PDF downloaded to:');
      for (var i = 0; i < 100 && done.evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await _settle(tester);
    }, () => MockClient((req) async => http.Response('%PDF-1.4', 200)));

    expect(File('${_tmp.path}/emergency_emg-9.pdf').existsSync(), isTrue);
    expect(find.textContaining('PDF downloaded to:'), findsOneWidget);
    expect(find.text('Downloading PDF...'), findsNothing);
  });

  testWidgets('a download that throws closes the dialog with an error',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      await tester.tap(find.text('Download Emergency PDF'));
      await _settle(tester);
    }, () => MockClient((req) async => throw http.ClientException('offline')));
    expect(find.textContaining('Error downloading PDF'), findsOneWidget);
    expect(find.text('Downloading PDF...'), findsNothing);
  });
}
