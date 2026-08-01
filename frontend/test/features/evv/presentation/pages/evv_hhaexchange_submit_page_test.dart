// Tests for EvvHhaExchangeSubmitPage — populated / interaction paths.
// (lib/features/evv/presentation/pages/evv_hhaexchange_submit_page.dart)
//
// The prior-cohort flat test (test/features/evv/) only covers the empty/render
// states because its http.runWithClient wiring never reaches the page's
// EvvService. This suite wires EvvService's client via
// ApiServiceOffline.debugOverrideHttpClient so the eligible-records load and
// select-all interaction are exercised.

import 'dart:convert';
import 'dart:io';

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
const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

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
  // Payload download writes a file via the native handler; give it a temp dir.
  m.setMockMethodCallHandler(
      _pathProvider, (call) async => Directory.systemTemp.path);
}

void _teardownStubs() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(_secureStorage, null);
  m.setMockMethodCallHandler(_connectivity, null);
  m.setMockMethodCallHandler(_pathProvider, null);
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

/// Wire the submit path: eligible load, payload fetch, and the submit call.
///
/// The payload fetch is failed on purpose: a successful fetch would invoke the
/// native file handler (real path_provider + file I/O), which bounded pumps
/// can't drain in a headless VM test. Failing it exercises the "could not
/// download payload" warning branch and then proceeds to the submit call —
/// which is the orchestration we actually want to cover.
void _wireSubmit({int submitStatus = 200, String submitBody = '{"submitted":2}'}) {
  ApiServiceOffline.debugOverrideHttpClient(MockClient((req) async {
    final url = req.url.toString();
    if (url.contains('/records/hhaexchange-eligible')) {
      return http.Response(jsonEncode([_rec(1), _rec(2)]), 200);
    }
    if (url.contains('/records/hhaexchange-payload')) {
      return http.Response('unavailable', 503);
    }
    if (url.contains('/records/submit-to-hhaexchange')) {
      return http.Response(submitBody, submitStatus);
    }
    return http.Response('[]', 200);
  }));
}

/// Load, select all eligible records, and pump bounded frames after the submit
/// tap (the FAB shows a spinner while _isSubmitting, so pumpAndSettle stalls).
Future<void> _loadSelectSubmit(WidgetTester tester) async {
  await tester.pumpWidget(_host());
  await tester.pumpAndSettle();
  // Select all, revealing the submit FAB.
  await tester.tap(find.byType(Checkbox).first);
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Visit(s)'));
  // The FAB shows a spinner while submitting, so pumpAndSettle never settles.
  // Pump bounded frames spanning the 3s payload-warning delay plus the submit
  // and eligible-reload calls.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
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

  testWidgets('submits selected visits and clears the selection', (tester) async {
    _wireSubmit();
    await _loadSelectSubmit(tester);
    // On success the page clears _selected and reloads, so the submit FAB
    // (its "Visit(s)" label) disappears and no failure message is shown.
    expect(find.textContaining('Visit(s)'), findsNothing);
    expect(find.textContaining('Submission failed'), findsNothing);
    tester.takeException();
  });

  testWidgets('reports a submission failure', (tester) async {
    _wireSubmit(submitStatus: 500, submitBody: '{"error":"boom"}');
    await _loadSelectSubmit(tester);
    expect(find.textContaining('Submission failed'), findsWidgets);
    tester.takeException();
  });
}
