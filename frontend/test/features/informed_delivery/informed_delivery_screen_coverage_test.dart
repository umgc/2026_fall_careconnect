// Additional coverage for InformedDeliveryScreen: loading real (mocked HTTP)
// digest data, search filtering, refresh, image viewer and response parsing.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/informed_delivery/informed_delivery_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../mock_user_provider.dart';

// 1x1 transparent PNG.
const _pngB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

String _apiBody() => jsonEncode({
      'digestDate': '2025-01-10T09:00:00.000',
      'mailpieces': [
        {
          'id': 'real-1',
          'sender': 'Zebra Insurance',
          'summary': 'Policy renewal',
          'imageDataUrl': 'data:image/png;base64,$_pngB64',
          'dateIso': '2025-01-10T09:00:00.000',
          'actions': {'track': 'https://t'},
        },
        {
          'id': 'real-2',
          'sender': 'Broken Image Co',
          'summary': 'Corrupt',
          'imageDataUrl': 'data:image/png;base64,@@@not-base64@@@',
          'dateIso': '2025-01-10T10:00:00.000',
          'actions': null,
        },
      ],
      'packages': [
        {
          'trackingNumber': '9400100000000000000000',
          'expectedDateIso': '2025-01-11T00:00:00.000',
          'actions': {'track': 'https://track'},
        },
      ],
    });

Widget _wrap() {
  return MaterialApp(
    home: ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(),
      child: const InformedDeliveryScreen(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  void bigSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(2600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final orig = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) return;
      orig?.call(details);
    };
    addTearDown(() => FlutterError.onError = orig);
  }

  Future<void> pumpWith(WidgetTester tester, http.Client client) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_wrap());
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }, () => client);
  }

  testWidgets('loads API digest merged with mock data, searches, clears',
      (tester) async {
    bigSurface(tester);
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      expect(req.url.path, endsWith('/v1/api/usps/mail'));
      return http.Response(_apiBody(), 200);
    });

    await pumpWith(tester, client);
    expect(calls, 1);
    // Mock digest has several mailpieces plus the 2 real ones.
    expect(find.textContaining('Informed Delivery ('), findsOneWidget);
    expect(find.textContaining('Total: '), findsOneWidget);

    // Search for the real sender.
    await http.runWithClient(() async {
      await tester.enterText(find.byType(TextField), 'zebra');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
    }, () => client);
    expect(find.text('Search results: 1'), findsOneWidget);
    expect(find.text("for 'zebra'"), findsOneWidget);

    // Search for something that matches nothing -> empty state.
    await tester.enterText(find.byType(TextField), 'no-such-sender-xyz');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.text('Search results: 0'), findsOneWidget);
    expect(find.text('No mail for this expected date'), findsOneWidget);

    // Clear button resets the search.
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.textContaining('Total: '), findsOneWidget);
    expect(find.byIcon(Icons.clear), findsNothing);
  });

  testWidgets('refresh success shows snackbar and dropdown selection works',
      (tester) async {
    bigSurface(tester);
    final client =
        MockClient((req) async => http.Response(_apiBody(), 200));
    await pumpWith(tester, client);

    await http.runWithClient(() async {
      await tester.tap(find.text('Refresh'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }, () => client);
    expect(find.text('Mail data refreshed (API + mock).'), findsOneWidget);

    // Open the date dropdown and pick the last entry.
    await tester.tap(find.byType(DropdownButtonFormField<DateTime>));
    await tester.pumpAndSettle();
    final items = find.byType(DropdownMenuItem<DateTime>);
    expect(items, findsWidgets);
    await tester.tap(items.last, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(InformedDeliveryScreen), findsOneWidget);
  });

  testWidgets('API failure falls back to mock data; tapping a tile opens viewer',
      (tester) async {
    bigSurface(tester);
    final client = MockClient((req) async => http.Response('nope', 500));
    await pumpWith(tester, client);
    expect(find.textContaining('Total: '), findsOneWidget);

    final tiles = find.byType(InkWell);
    expect(tiles, findsWidgets);
    // Tap a tile image inside the grid (first InkWell inside a Card).
    final cardInk = find.descendant(
        of: find.byType(Card).first, matching: find.byType(InkWell));
    await tester.tap(cardInk.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await tester.tap(find.byType(InteractiveViewer), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('parseUspsDigestResponse handles strings, loose JSON and errors',
      (tester) async {
    bigSurface(tester);
    final client = MockClient((req) async => http.Response('', 401));
    await pumpWith(tester, client);

    final dynamic state = tester.state(find.byType(InformedDeliveryScreen));

    final UspsDigest fromJson = state.parseUspsDigestResponse(jsonEncode({
      'digestDate': '2025-02-01T00:00:00.000',
      'mailpieces': 'not-a-list',
      'packages': 'not-a-list',
    }));
    expect(fromJson.digestDate, DateTime(2025, 2, 1));
    expect(fromJson.mailpieces, isEmpty);
    expect(fromJson.packages, isEmpty);

    final UspsDigest loose = state.parseUspsDigestResponse(
        "{digestDate: '2025-03-04T00:00:00.000', mailpieces: [], "
        "packages: [{trackingNumber: '123', expectedDateIso: "
        "'2025-03-05T00:00:00.000'}]}");
    expect(loose.digestDate.month, 3);
    expect(loose.packages.single.trackingNumber, '123');
    expect(loose.packages.single.actions.track, isNull);

    expect(() => state.parseUspsDigestResponse(42), throwsArgumentError);
    expect(() => state.parseUspsDigestResponse('[1, 2]'),
        throwsFormatException);
    expect(
        () => state.parseUspsDigestResponse(<String, dynamic>{
              'digestDate': 5,
            }),
        throwsFormatException);
  });
}
