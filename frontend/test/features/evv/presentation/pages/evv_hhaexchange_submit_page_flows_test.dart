// Interaction tests for EvvHhaExchangeSubmitPage
// (lib/features/evv/presentation/pages/evv_hhaexchange_submit_page.dart):
// record selection, payload download attempt and submission outcomes.

import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/features/evv/presentation/pages/evv_hhaexchange_submit_page.dart';
import 'package:care_connect_app/services/api_service_offline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

late Future<http.Response> Function(http.Request) _handler;
final _client = MockClient((r) => _handler(r));

Map<String, dynamic> _record(int id, {bool withPatient = true}) => {
      'id': id,
      if (withPatient)
        'patient': {'id': 10 + id, 'firstName': 'Pat$id', 'lastName': 'Doe'},
      'serviceType': 'Personal Care',
      'individualName': 'Individual $id',
      'caregiverId': 3,
      'dateOfService': '2026-03-0${id}T00:00:00',
      'timeIn': '2026-03-0${id}T08:05:00',
      'timeOut': '2026-03-0${id}T09:10:00',
      'status': 'APPROVED',
      'stateCode': 'VA',
      'createdAt': '2026-03-01T00:00:00',
      'updatedAt': '2026-03-01T00:00:00',
    };

void _routes({
  http.Response Function()? eligible,
  Future<http.Response> Function()? payload,
  http.Response Function()? submit,
  List<String>? log,
}) {
  _handler = (r) async {
    log?.add(r.url.path);
    final p = r.url.path;
    if (p.endsWith('/hhaexchange-eligible')) {
      return eligible?.call() ??
          http.Response(
            jsonEncode([_record(1), _record(2, withPatient: false)]),
            200,
          );
    }
    if (p.endsWith('/hhaexchange-payload')) {
      return payload != null
          ? await payload()
          : http.Response('{"visits":[1]}', 200);
    }
    if (p.endsWith('/submit-to-hhaexchange')) {
      return submit?.call() ?? http.Response('{"submitted":2}', 200);
    }
    return http.Response('[]', 200);
  };
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: const EvvHhaExchangeSubmitPage(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tapSubmit(WidgetTester tester) async {
  // Let the FAB entrance animation finish before tapping it.
  await tester.pumpAndSettle();
  await tester.tap(find.byType(FloatingActionButton));
}

void main() {
  setUpAll(() => ApiServiceOffline.debugOverrideHttpClient(_client));
  tearDownAll(() => ApiServiceOffline.debugOverrideHttpClient(null));

  setUp(() {
    _routes();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  testWidgets('lists eligible records with patient or individual names',
      (tester) async {
    await _pump(tester);
    expect(find.text('Pat1 Doe'), findsOneWidget);
    expect(find.text('Individual 2'), findsOneWidget);
    expect(find.text('Personal Care  •  2026-03-01'), findsOneWidget);
    expect(
      find.text('Check-in: 08:05  →  Check-out: 09:10  |  State: VA'),
      findsNWidgets(2),
    );
    expect(find.text('Select all (2)'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('load failure shows error snackbar', (tester) async {
    _routes(eligible: () => http.Response('nope', 500));
    await _pump(tester);
    expect(find.textContaining('Error loading records:'), findsOneWidget);
    expect(find.text('No eligible visits'), findsOneWidget);
  });

  testWidgets('select all, toggle one and deselect all', (tester) async {
    await _pump(tester);
    // Header checkbox: unchecked -> selects every record.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.text('Deselect all'), findsOneWidget);
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.text('Submit 2 Visit(s)'), findsOneWidget);

    // Unchecking then re-checking one record tile.
    await tester.tap(find.text('Pat1 Doe'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Select all (2)'), findsOneWidget);
    await tester.tap(find.text('Pat1 Doe'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    // Header checkbox: all selected -> clears the selection.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.text('Select all (2)'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('successful submit fetches payload, submits and reloads',
      (tester) async {
    final log = <String>[];
    final payload = Completer<http.Response>();
    _routes(log: log, payload: () => payload.future);
    await _pump(tester);
    await tester.tap(find.text('Pat1 Doe'));
    await tester.pump();
    await _tapSubmit(tester);
    await tester.pump();

    // While the payload is being fetched a success-styled banner is shown
    // and the FAB shows its progress state.
    expect(find.text('Fetching payload for download...'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('Submitting\u2026'), findsOneWidget);

    payload.complete(http.Response('{"visits":[1]}', 200));
    await _settle(tester);

    expect(log.where((p) => p.endsWith('/submit-to-hhaexchange')),
        hasLength(1));
    // The list is reloaded after a successful submission, which clears the
    // banner and the selection.
    expect(
      log.where((p) => p.endsWith('/hhaexchange-eligible')).length,
      greaterThanOrEqualTo(2),
    );
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('payload failure warns and then reports submit failure',
      (tester) async {
    _routes(
      payload: () async => http.Response('bad', 500),
      submit: () => http.Response(jsonEncode({'error': 'Upstream down'}), 502),
    );
    await _pump(tester);
    await tester.tap(find.text('Individual 2'));
    await tester.pump();
    await _tapSubmit(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('Warning: Could not download payload'),
        findsOneWidget);
    expect(find.byIcon(Icons.error), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await _settle(tester);
    expect(find.text('Submission failed: Exception: Upstream down'),
        findsOneWidget);
    expect(find.text('Submit 1 Visit(s)'), findsOneWidget);
  });
}
