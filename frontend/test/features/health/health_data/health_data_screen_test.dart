// HealthDataScreen states: loading, loaded (synthetic), backend failure,
// empty, and the sample records it renders alongside Medicare.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/health/health_data/pages/health_data_screen.dart';
import 'package:care_connect_app/services/api_client.dart';

import 'health_data_test_support.dart';

/// SRS 1.4 §8.6, ERR-MCR-03 (FR-MCR-24, AC-MCR-24-2).
const _errMcr03 =
    'Showing your saved records. We couldn\'t check Medicare for updates.';

/// SRS 1.4 AC-MCR-28-1 (FR-MCR-28).
const _noRecords = 'No Medicare records found';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpClientAdapter original;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    original = ApiClient.instance.debugHttpClientAdapter;
  });
  tearDown(() => ApiClient.instance.debugSetHttpClientAdapter(original));

  RouteAdapter fixtures({Completer<void>? gate}) => RouteAdapter({
        '/v1/api/medicare/visits': envelope(fixtureResources('eob-bundle.json')),
        '/v1/api/medicare/coverage':
            envelope(fixtureResources('coverage-bundle.json')),
      }, gate: gate);

  Future<void> pump(WidgetTester t, RouteAdapter a) async {
    ApiClient.instance.debugSetHttpClientAdapter(a);
    await t.pumpWidget(const MaterialApp(home: HealthDataScreen()));
  }

  /// Dio and the ApiClient interceptors run outside the fake clock: give them
  /// real time until the loading state ends (at most ~2 s), then settle.
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

  testWidgets('TC-HDATA-009: a loading state shows until Medicare answers '
      '(FR-MCR-27)', (t) async {
    final gate = Completer<void>();
    await pump(t, fixtures(gate: gate));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading your health data…'), findsOneWidget);
    gate.complete();
    await settle(t);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('TC-HDATA-010: loaded mock data shows the demo-data banner and '
      'each Medicare record with a From Medicare badge', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await pump(t, fixtures());
    await settle(t);
    expect(
        find.text('Demo data: showing synthetic Medicare records, not a live '
            'account.'),
        findsOneWidget);
    for (final title in [
      'Office or other outpatient visit, established patient',
      'Simple pneumonia and pleurisy with CC',
      'Medicare Part A (Hospital Insurance)',
    ]) {
      await t.scrollUntilVisible(find.text(title), 200);
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Duplicate Submission Clinic', skipOffstage: false),
        findsNothing);
    expect(find.text('From Medicare', skipOffstage: false), findsNWidgets(5));
  });

  testWidgets('TC-HDATA-011: when Medicare cannot be reached the screen says '
      'so with ERR-MCR-03 (FR-MCR-24, AC-MCR-24-2)', (t) async {
    await pump(
        t,
        RouteAdapter(const {}, status: {
          '/v1/api/medicare/visits': 503,
          '/v1/api/medicare/coverage': 503,
        }));
    await settle(t);
    expect(find.text(_errMcr03), findsOneWidget);
  });

  testWidgets('TC-HDATA-012: a linked account with no Medicare records shows '
      '"No Medicare records found" (FR-MCR-28, AC-MCR-28-1)', (t) async {
    await pump(
        t,
        RouteAdapter({
          '/v1/api/medicare/visits': envelope(const []),
          '/v1/api/medicare/coverage': envelope(const []),
        }));
    await settle(t);
    expect(find.textContaining(_noRecords), findsOneWidget);
  });

  testWidgets('TC-HDATA-013: records that are not the patient\'s (built-in '
      'samples) are labelled as samples on the card', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await pump(t, fixtures());
    await settle(t);
    for (final title in [
      'Lisinopril 10 mg',
      'Primary Care Follow-Up',
      'Annual Wellness Visit',
    ]) {
      // The card is the nearest Column around the title.
      final card = find
          .ancestor(
              of: find.text(title, skipOffstage: false),
              matching: find.byType(Column))
          .first;
      // Some text in the same card must say it is sample / demo data.
      final disclosed = find.descendant(
          of: card,
          matching: find.textContaining(
              RegExp('sample|demo', caseSensitive: false),
              skipOffstage: false));
      expect(disclosed, findsWidgets, reason: '$title has no sample label');
    }
  });

  testWidgets('TC-HDATA-014: leaving the screen before Medicare answers '
      'raises no error', (t) async {
    final gate = Completer<void>();
    await pump(t, fixtures(gate: gate));
    await t.pump();
    await t.pumpWidget(const MaterialApp(home: Text('elsewhere')));
    gate.complete();
    // The abandoned load finishes on real time; give it that time.
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      for (var i = 0; i < 20; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump(const Duration(milliseconds: 50));
      }
    } finally {
      FlutterError.onError = previous;
    }
    expect(errors.map((e) => e.exceptionAsString()), isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets('TC-HDATA-015: every text on the loaded screen has at least '
      '4.5:1 contrast against what is behind it (WCAG 2.1 SC 1.4.3)',
      (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await pump(t, fixtures());
    await settle(t);
    final low = lowContrastText(t, find.byType(ListView));
    expect(low, isEmpty, reason: low.join('\n'));
  });
}
