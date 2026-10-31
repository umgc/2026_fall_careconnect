// Gap tests for QrScreen (lib/features/emergency_qr/qr_screen.dart): the
// plugin-failure branches, the in-flight download dialog and the saved-file
// path of the PDF download.
//
// url_launcher, path_provider and share_plus are replaced with fakes, and the
// HTTP client is replaced through http.runWithClient, so nothing touches the
// network or the real documents folder.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:care_connect_app/features/emergency_qr/qr_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _FakeLauncher extends UrlLauncherPlatform {
  bool throwOnCanLaunch = false;
  final launched = <String>[];

  @override
  get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async {
    if (throwOnCanLaunch) throw PlatformException(code: 'no-browser');
    return true;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

class _FakePaths extends PathProviderPlatform {
  _FakePaths(this.dir);
  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

void main() {
  late _FakeLauncher launcher;
  late Directory tmp;
  final sharedArgs = <Map<Object?, Object?>>[];

  setUp(() {
    launcher = _FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    tmp = Directory.systemTemp.createTempSync('qr_gap_');
    PathProviderPlatform.instance = _FakePaths(tmp.path);
    sharedArgs.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      (call) async {
        sharedArgs.add(Map<Object?, Object?>.from(call.arguments as Map));
        return 'dev.fluttercommunity.plus/share/success';
      },
    );
  });

  tearDown(() {
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows can still hold the file briefly; the OS temp dir is cleaned up.
    }
  });

  /// Wide surface so the three action buttons fit side by side.
  Future<void> pumpScreen(WidgetTester tester, {String? id = 'emg-9'}) async {
    tester.view.physicalSize = const Size(1800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: QrScreen(payload: 'PAYLOAD-TEXT', emergencyId: id, patientId: 3),
    ));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('without an emergency id there are no PDF action buttons',
      (tester) async {
    await pumpScreen(tester, id: null);
    expect(find.text('Emergency Information'), findsOneWidget);
    expect(find.text('View Emergency PDF'), findsNothing);
    expect(find.text('Share Emergency Info'), findsNothing);
  });

  testWidgets('view opens the inline PDF url', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('View Emergency PDF'));
    await settle(tester);
    expect(launcher.launched.single, endsWith('/v1/api/emergency/emg-9.pdf'));
  });

  testWidgets('view shows an error snackbar when launching throws',
      (tester) async {
    launcher.throwOnCanLaunch = true;
    await pumpScreen(tester);
    await tester.tap(find.text('View Emergency PDF'));
    await settle(tester);
    expect(find.textContaining('Error viewing PDF'), findsOneWidget);
    expect(launcher.launched, isEmpty);
  });

  testWidgets('print shows an error snackbar when launching throws',
      (tester) async {
    launcher.throwOnCanLaunch = true;
    await pumpScreen(tester);
    await tester.tap(find.text('Print Emergency PDF'));
    await settle(tester);
    expect(find.textContaining('Error printing PDF'), findsOneWidget);
  });

  testWidgets('share includes the payload and the PDF link', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Share Emergency Info'));
    await settle(tester);

    expect(sharedArgs, hasLength(1));
    final text = sharedArgs.single['text'] as String;
    expect(text, startsWith('PAYLOAD-TEXT'));
    expect(text, contains('/v1/api/emergency/emg-9.pdf'));
    expect(
        sharedArgs.single['subject'], 'Emergency Medical Information - emg-9');
  });

  testWidgets('download shows a progress dialog while the request is pending',
      (tester) async {
    final gate = Completer<http.Response>();
    Uri? requested;
    await http.runWithClient(() async {
      await pumpScreen(tester);
      await tester.tap(find.text('Download Emergency PDF'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Downloading PDF...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(requested!.path, '/v1/api/emergency/download/emg-9.pdf');

      gate.complete(http.Response('', 500));
      await settle(tester);
      expect(find.text('Downloading PDF...'), findsNothing);
      expect(find.text('Failed to download PDF'), findsOneWidget);
    },
        () => MockClient((req) {
              requested = req.url;
              return gate.future;
            }));
  });

  testWidgets('download closes the dialog and reports a request error',
      (tester) async {
    await http.runWithClient(() async {
      await pumpScreen(tester);
      await tester.tap(find.text('Download Emergency PDF'));
      await settle(tester);
    }, () => MockClient((req) async => throw const SocketException('offline')));

    expect(find.text('Downloading PDF...'), findsNothing);
    expect(find.textContaining('Error downloading PDF'), findsOneWidget);
  });

  testWidgets('download writes the PDF into the documents folder',
      (tester) async {
    await http.runWithClient(() async {
      await pumpScreen(tester);
      await tester.tap(find.text('Download Emergency PDF'));
      // File I/O is real, so give the event loop time between pumps.
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 400)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await settle(tester);
    }, () => MockClient((req) async => http.Response('%PDF-fake', 200)));

    final saved = File('${tmp.path}/emergency_emg-9.pdf');
    expect(saved.existsSync(), isTrue);
    expect(saved.readAsStringSync(), '%PDF-fake');
    expect(find.textContaining('PDF downloaded to:'), findsOneWidget);
    expect(find.text('Downloading PDF...'), findsNothing);
  });
}
