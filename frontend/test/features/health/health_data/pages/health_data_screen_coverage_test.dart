// Additional HealthDataScreen coverage: Epic / Oracle Health connection
// states in Connected Sources, the Oracle connect failure snackbar, the
// expired Medicare link actions, athena hidden for a non-patient, and the
// record-type chip toggling rules.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/health/health_data/pages/health_data_screen.dart';
import 'package:care_connect_app/features/health/health_data/services/athena_connect_service.dart';
import 'package:care_connect_app/features/health/health_data/widgets/athena_connect_tile.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/services/api_client.dart';

import '../health_data_test_support.dart';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

class _StatusAthena extends AthenaConnectService {
  _StatusAthena(this.result);
  final AthenaStatus? result;

  @override
  Future<AthenaStatus?> status() async => result;
}

/// Answers Epic / Oracle Health status (package:http) requests.
MockClient _httpStatus({bool? epic, bool? oracle, List<String>? seen}) {
  return MockClient((req) async {
    seen?.add(req.url.path);
    final p = req.url.path;
    if (p.endsWith('/api/epic/status') && epic != null) {
      return http.Response(jsonEncode({'connected': epic}), 200);
    }
    if (p.endsWith('/api/oracle-health/status') && oracle != null) {
      return http.Response(jsonEncode({'connected': oracle}), 200);
    }
    return http.Response('{}', 503);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpClientAdapter original;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    original = ApiClient.instance.debugHttpClientAdapter;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async => null);
  });
  tearDown(() {
    ApiClient.instance.debugSetHttpClientAdapter(original);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  RouteAdapter fixtures({Map<String, int> status = const {}}) => RouteAdapter({
        '/v1/api/medicare/visits':
            envelope(fixtureResources('eob-bundle.json')),
        '/v1/api/medicare/coverage':
            envelope(fixtureResources('coverage-bundle.json')),
      }, status: status);

  Future<void> settle(WidgetTester t) async {
    for (var i = 0;
        i < 40 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.pumpAndSettle();
  }

  Future<void> pump(WidgetTester t, HttpClientAdapter a,
      {required http.Client client, Widget? app}) async {
    await t.binding.setSurfaceSize(const Size(1200, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    ApiClient.instance.debugSetHttpClientAdapter(a);
    await http.runWithClient(() async {
      await t.pumpWidget(app ??
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HealthDataScreen(),
          ));
      await settle(t);
    }, () => client);
  }

  Finder providerRow(String name) => find
      .ancestor(of: find.text(name), matching: find.byType(Row))
      .first;

  testWidgets('Epic and Oracle Health connected show as Connected',
      (t) async {
    final seen = <String>[];
    await pump(t, fixtures(),
        client: _httpStatus(epic: true, oracle: true, seen: seen));
    expect(seen.any((p) => p.endsWith('/api/epic/status')), isTrue);
    expect(seen.any((p) => p.endsWith('/api/oracle-health/status')), isTrue);
    expect(
        find.descendant(
            of: providerRow('Epic (MyChart)'), matching: find.text('Connected')),
        findsOneWidget);
    expect(
        find.descendant(
            of: providerRow('Oracle Health'), matching: find.text('Connected')),
        findsOneWidget);
  });

  testWidgets('Oracle Health not connected offers Connect, and a failed '
      'start says so', (t) async {
    final client = _httpStatus(epic: false, oracle: false);
    await pump(t, fixtures(), client: client);
    expect(
        find.descendant(
            of: providerRow('Oracle Health'),
            matching: find.text('Not connected')),
        findsOneWidget);
    final connect = find.descendant(
        of: providerRow('Oracle Health'),
        matching: find.widgetWithText(TextButton, 'Connect'));
    expect(connect, findsOneWidget);

    await http.runWithClient(() async {
      await t.tap(connect);
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
    }, () => client);
    expect(find.text('Unable to start Oracle Health connection.'),
        findsOneWidget);
  });

  testWidgets('an expired Medicare link offers Reconnect and Connect, both '
      'opening the Medicare page', (t) async {
    final router = GoRouter(initialLocation: '/health-data', routes: [
      GoRoute(
          path: '/health-data', builder: (_, __) => const HealthDataScreen()),
      GoRoute(
          path: '/medicare-connect',
          builder: (context, _) => Scaffold(
              body: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Back from Medicare page')))),
    ]);
    await pump(
      t,
      fixtures(status: const {'/v1/api/medicare/visits': 409}),
      client: _httpStatus(),
      app: MaterialApp.router(routerConfig: router),
    );
    expect(find.text('Connection expired'), findsOneWidget);
    expect(
        find.textContaining('Your Medicare connection has expired'),
        findsOneWidget);

    await t.tap(find.widgetWithText(TextButton, 'Reconnect'));
    await t.pumpAndSettle();
    expect(find.text('Back from Medicare page'), findsOneWidget);
    await t.tap(find.text('Back from Medicare page'));
    await t.pumpAndSettle();

    // The banner's own Connect button goes to the same page.
    final bannerConnect = find.descendant(
        of: find
            .ancestor(
                of: find.textContaining('Your Medicare connection has expired'),
                matching: find.byType(Row))
            .first,
        matching: find.byType(TextButton));
    expect(bannerConnect, findsOneWidget);
    await t.tap(bannerConnect);
    await t.pumpAndSettle();
    expect(find.text('Back from Medicare page'), findsOneWidget);
  });

  testWidgets('athenahealth is hidden when status says it is not shown',
      (t) async {
    final originalAthena = AthenaConnectService.instance;
    AthenaConnectService.instance = _StatusAthena(AthenaStatus.notPatient);
    addTearDown(() => AthenaConnectService.instance = originalAthena);
    await pump(t, fixtures(), client: _httpStatus());
    expect(find.byType(AthenaConnectTile), findsNothing);
  });

  testWidgets('a type chip toggles off, and selecting every type resets to '
      'All', (t) async {
    await pump(t, fixtures(), client: _httpStatus());
    FilterChip chip(String label) =>
        t.widget<FilterChip>(find.widgetWithText(FilterChip, label));

    await t.tap(find.widgetWithText(FilterChip, 'Claims'));
    await t.pumpAndSettle();
    expect(chip('Claims').selected, isTrue);
    await t.tap(find.widgetWithText(FilterChip, 'Claims'));
    await t.pumpAndSettle();
    expect(chip('Claims').selected, isFalse);
    expect(chip('All').selected, isTrue);

    for (final label in [
      'Medications',
      'Conditions',
      'Allergies',
      'Visits',
      'Clinical Records',
      'Claims',
    ]) {
      await t.tap(find.widgetWithText(FilterChip, label));
      await t.pumpAndSettle();
    }
    expect(chip('All').selected, isTrue);
    expect(chip('Claims').selected, isFalse);
  });
}
