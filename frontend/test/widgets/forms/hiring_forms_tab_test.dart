// Tests for HiringFormsTab (lib/widgets/forms/hiring_forms_tab.dart).
//
// The tab loads the bundled form definitions (assets/forms/*.form.json).
// Opening a form shows its details page, and "Fill out" opens the fill-in
// page; both are titled pages (WCAG 2.4.2).
import 'dart:convert';
import 'dart:typed_data';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/widgets/forms/hiring_forms_tab.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../../helpers/titled_route_probe.dart';

class _FakeFilePicker extends Fake
    with MockPlatformInterfaceMixin
    implements FilePicker {
  FilePickerResult? result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    dynamic Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      result;
}

void main() {
  late TitledRouteProbe probe;

  Future<void> pumpTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    probe = TitledRouteProbe();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorObservers: [probe],
      home: const Scaffold(body: HiringFormsTab(patientId: 12)),
    ));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
  }

  testWidgets('lists the bundled hiring forms', (tester) async {
    await pumpTab(tester);
    expect(find.byIcon(Icons.chevron_right), findsWidgets);
  });

  testWidgets('opening a form pushes a page titled "Hiring Form Details"',
      (tester) async {
    await pumpTab(tester);
    expect(
        await probe.tapAndReadTitle(
            tester, find.byIcon(Icons.chevron_right).first),
        'Hiring Form Details');
  });

  testWidgets('"Fill out" pushes a page titled "Complete Hiring Form"',
      (tester) async {
    await pumpTab(tester);
    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pumpAndSettle();
    expect(
        await probe.tapAndReadTitle(tester, find.byType(FloatingActionButton)),
        'Complete Hiring Form');
  });

  group('uploading a completed copy', () {
    const secureStorage =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    late _FakeFilePicker picker;

    setUp(() {
      FilePicker.platform = picker = _FakeFilePicker();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorage, (call) async => null);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorage, null);
    });

    Future<void> openFirstForm(WidgetTester tester) async {
      await pumpTab(tester);
      await tester.tap(find.byIcon(Icons.chevron_right).first);
      await tester.pumpAndSettle();
    }

    testWidgets('a picked file is filed and the page closes', (tester) async {
      picker.result = FilePickerResult([
        PlatformFile(name: 'w4.pdf', size: 3, bytes: Uint8List(3)),
      ]);
      await http.runWithClient(() async {
        await openFirstForm(tester);
        await tester.tap(find.byIcon(Icons.upload_file));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.upload_file), findsNothing);
      },
          () => MockClient((_) async {
                return http.Response(
                  jsonEncode({'fileId': 1, 'fileName': 'w4.pdf'}),
                  200,
                );
              }));
    });

    testWidgets('a failed upload is reported and cancel does nothing',
        (tester) async {
      await http.runWithClient(() async {
        await openFirstForm(tester);
        picker.result = null;
        await tester.tap(find.byIcon(Icons.upload_file));
        await tester.pump();
        expect(find.byType(SnackBar), findsNothing);

        picker.result = FilePickerResult([
          PlatformFile(name: 'w4.pdf', size: 3, bytes: Uint8List(3)),
        ]);
        await tester.tap(find.byIcon(Icons.upload_file));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.byIcon(Icons.upload_file), findsOneWidget);
      }, () => MockClient((_) async => http.Response('{"error":"x"}', 500)));
    });
  });
}
