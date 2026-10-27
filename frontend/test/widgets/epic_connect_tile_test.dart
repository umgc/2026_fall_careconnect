// Tests for EpicConnectTile (lib/widgets/epic_connect_tile.dart).
import 'dart:convert';

import 'package:care_connect_app/widgets/epic_connect_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/titled_route_probe.dart';

void main() {
  late TitledRouteProbe probe;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  MockClient backend({required bool connected}) => MockClient((request) async {
        if (request.url.path.endsWith('/status')) {
          return http.Response(jsonEncode({'connected': connected}), 200);
        }
        if (request.url.path.endsWith('/authorize')) {
          return http.Response(
              jsonEncode({'authUrl': 'https://epic.example/authorize'}), 200);
        }
        return http.Response('{}', 404);
      });

  Future<void> pumpTile(WidgetTester tester) async {
    probe = TitledRouteProbe();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [probe],
      home: const Scaffold(body: EpicConnectTile()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('not connected: offers Connect', (tester) async {
    await http.runWithClient(() async {
      await pumpTile(tester);
      expect(
          find.text('Connect to import your clinical records'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
    }, () => backend(connected: false));
  });

  testWidgets('connected: offers Disconnect', (tester) async {
    await http.runWithClient(() async {
      await pumpTile(tester);
      expect(find.text('Connected — your records help answer Ask AI'),
          findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
    }, () => backend(connected: true));
  });

  testWidgets('Connect opens the in-app sign-in page titled "Connect Epic"',
      (tester) async {
    await http.runWithClient(() async {
      await pumpTile(tester);
      expect(await probe.tapAndReadTitle(tester, find.text('Connect')),
          'Connect Epic');
    }, () => backend(connected: false));
  });
}
