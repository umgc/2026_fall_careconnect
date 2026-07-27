// Tests for EvvHhaExchangeSubmitPage — populated / interaction paths.
// (lib/features/evv/presentation/pages/evv_hhaexchange_submit_page.dart)
//
// The prior-cohort flat test (test/features/evv/) only covers the empty/render
// states because its http.runWithClient wiring never reaches the page's
// EvvService. This suite wires EvvService's client via
// ApiServiceOffline.debugOverrideHttpClient so the eligible-records load and
// select-all interaction are exercised.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/services/api_service_offline.dart';
import 'package:care_connect_app/features/evv/presentation/pages/evv_hhaexchange_submit_page.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');

void _setupStubs() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(_secureStorage, (call) async {
    if (call.method == 'readAll') return <String, String>{'jwt_token': 'x'};
    if (call.method == 'read') return 'x';
    if (call.method == 'containsKey') return true;
    return null;
  });
  m.setMockMethodCallHandler(_connectivity, (call) async {
    if (call.method == 'check') return ['wifi'];
    return null;
  });
}

void _teardownStubs() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(_secureStorage, null);
  m.setMockMethodCallHandler(_connectivity, null);
}

Map<String, dynamic> _rec(int id) => {
      'id': id,
      'serviceType': 'Personal Care',
      'individualName': 'Mary Johnson',
      'caregiverId': 1,
      'status': 'APPROVED',
      'stateCode': 'VA',
      'dateOfService': '2026-08-01T09:00:00.000',
      'timeIn': '2026-08-01T09:00:00.000',
      'timeOut': '2026-08-01T10:00:00.000',
      'createdAt': '2026-08-01T10:00:00.000',
      'updatedAt': '2026-08-01T10:00:00.000',
    };

void _wireEligible(String body, {int status = 200}) {
  ApiServiceOffline.debugOverrideHttpClient(MockClient((req) async {
    if (req.url.toString().contains('/records/hhaexchange-eligible')) {
      return http.Response(body, status);
    }
    return http.Response('[]', 200);
  }));
}

Widget _host() => const MaterialApp(home: EvvHhaExchangeSubmitPage());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _setupStubs();
  });

  tearDown(() {
    _teardownStubs();
    ApiServiceOffline.debugOverrideHttpClient(null);
  });

  testWidgets('shows a loading indicator on the first frame', (tester) async {
    _wireEligible('[]');
    await tester.pumpWidget(_host());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('renders eligible records with a select-all control',
      (tester) async {
    _wireEligible(jsonEncode([_rec(1), _rec(2)]));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.textContaining('Select all'), findsOneWidget);
    expect(find.byType(Checkbox), findsWidgets); // per-record + select-all
    expect(find.textContaining('Mary Johnson'), findsWidgets);
  });

  testWidgets('tapping a record checkbox selects it', (tester) async {
    _wireEligible(jsonEncode([_rec(1), _rec(2)]));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    int checked() => tester
        .widgetList<Checkbox>(find.byType(Checkbox))
        .where((c) => c.value == true)
        .length;
    expect(checked(), 0);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(checked(), greaterThan(0));
  });

  testWidgets('handles a load error without crashing', (tester) async {
    _wireEligible('boom', status: 500);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
