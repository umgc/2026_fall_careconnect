// HealthDataScreen states: loading, loaded (synthetic), backend failure,
// empty, and the sample records it renders alongside Medicare.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/features/health/health_data/pages/health_data_screen.dart';
import 'package:care_connect_app/services/api_client.dart';

import '../health_data_test_support.dart';

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
      'each Medicare record, and the details screen says where it came from',
      (t) async {
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
      await t.scrollUntilVisible(find.text(title), 200,
          scrollable: find
              .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
              .first);
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Duplicate Submission Clinic', skipOffstage: false),
        findsNothing);
    // Source is de-emphasized on the cards (M2 feedback) and shown on the
    // details screen instead (#263 review, replaces the "From Medicare" badge).
    final details = find.text('View details', skipOffstage: false);
    expect(details, findsWidgets);
    await t.scrollUntilVisible(details.first, 200,
          scrollable: find
              .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
              .first);
    await t.tap(details.first);
    await t.pumpAndSettle();
    expect(find.text('Where this came from'), findsOneWidget);
    expect(find.text('Medicare'), findsOneWidget);
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

  testWidgets('TC-HDATA-013: no built-in sample records are shown as the '
      'patient\'s own (#256 removed them; #263 review)', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await pump(t, fixtures());
    await settle(t);
    for (final title in [
      'Lisinopril 10 mg',
      'Primary Care Follow-Up',
      'Annual Wellness Visit',
    ]) {
      expect(find.text(title, skipOffstage: false), findsNothing,
          reason: '$title is a sample record');
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

  for (final theme in {
    'light': AppTheme.lightTheme,
    'dark': AppTheme.darkTheme,
  }.entries) {
    testWidgets('TC-HDATA-015: every text on the loaded screen has at least '
        '4.5:1 contrast against what is behind it, in the app\'s ${theme.key} '
        'theme (WCAG 2.1 SC 1.4.3)', (t) async {
      await t.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      ApiClient.instance.debugSetHttpClientAdapter(RouteAdapter({
        '/v1/api/medicare/visits': envelope(fixtureResources('eob-bundle.json')),
      }, status: {
        '/v1/api/medicare/coverage': 503
      }));
      await t.pumpWidget(
          MaterialApp(theme: theme.value, home: const HealthDataScreen()));
      await settle(t);
      final low = lowContrastText(t, find.byType(ListView)).toSet();
      expect(low, isEmpty, reason: low.join('\n'));
    });
  }

  // ---- PR #263 re-review, 2026-10-06 ----

  testWidgets('TC-HDATA-020: when Medicare rejects the stored link (409 '
      'ERR-MCR-05) the screen says so and offers to connect again, not '
      'ERR-MCR-03 (FR-MCR-09, AC-MCR-09-1)', (t) async {
    const body = '{"error":"ERR-MCR-05","message":"Your Medicare connection '
        'has expired. Connect again to see current records.","connected":false}';
    await pump(
        t,
        RouteAdapter(const {}, status: {
          '/v1/api/medicare/visits': 409,
          '/v1/api/medicare/coverage': 409,
        }, statusBodies: {
          '/v1/api/medicare/visits': body,
          '/v1/api/medicare/coverage': body,
        }));
    await settle(t);
    expect(
        find.textContaining('Your Medicare connection has expired. Connect '
            'again to see current records.'),
        findsOneWidget);
    expect(find.text(_errMcr03), findsNothing);
    expect(find.text('Connect Medicare Account'), findsOneWidget);
  });

  testWidgets('TC-HDATA-021: a patient with no Medicare link (404) is offered '
      'Connect Medicare Account, not told Medicare could not be reached '
      '(AC-MCR-11-2)', (t) async {
    await pump(
        t,
        RouteAdapter(const {}, status: {
          '/v1/api/medicare/visits': 404,
          '/v1/api/medicare/coverage': 404,
        }, statusBodies: {
          '/v1/api/medicare/visits': '{}',
          '/v1/api/medicare/coverage': '{}',
        }));
    await settle(t);
    expect(find.text(_errMcr03), findsNothing);
    expect(find.text('Connect Medicare Account'), findsOneWidget);
  });

  testWidgets('TC-HDATA-023: when the other providers cannot be read the '
      'screen says so and still shows Medicare', (t) async {
    await pump(
        t,
        RouteAdapter({
          '/v1/api/medicare/visits':
              envelope(fixtureResources('eob-bundle.json')),
          '/v1/api/medicare/coverage': envelope(const []),
        }, status: {
          '/api/ehr/resources': 404,
          '/api/ehr/patient': 404,
        }));
    await settle(t);
    expect(
        find.textContaining(RegExp('couldn.t .*(other providers|health records)',
            caseSensitive: false)),
        findsOneWidget);
    expect(
        find.text('Simple pneumonia and pleurisy with CC', skipOffstage: false),
        findsOneWidget);
  });

  testWidgets('TC-HDATA-024: View details shows the claim type, title, '
      'status, date, source and every detail', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await pump(t, fixtures());
    await settle(t);
    final card = find
        .ancestor(
            of: find.text('Simple pneumonia and pleurisy with CC'),
            matching: find.byType(Card))
        .first;
    await t.tap(find.descendant(of: card, matching: find.text('View details')));
    await t.pumpAndSettle();
    expect(find.text('Health Event Details'), findsOneWidget);
    for (final text in [
      'CLAIM / SERVICE',
      'Simple pneumonia and pleurisy with CC',
      'Paid',
      'April 18, 2026',
      'Where this came from',
      'Medicare',
      'Saint Agnes Hospital',
      'Pneumonia, unspecified organism',
      r'$14320.55',
      r'$9861.13',
    ]) {
      expect(find.text(text), findsWidgets, reason: text);
    }
  });

  for (final theme in {
    'light': AppTheme.lightTheme,
    'dark': AppTheme.darkTheme,
  }.entries) {
    testWidgets('TC-HDATA-025: every text on the details screen has at least '
        '4.5:1 contrast, in the app\'s ${theme.key} theme (WCAG 2.1 SC 1.4.3)',
        (t) async {
      await t.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      ApiClient.instance.debugSetHttpClientAdapter(fixtures());
      await t.pumpWidget(
          MaterialApp(theme: theme.value, home: const HealthDataScreen()));
      await settle(t);
      await t.tap(find.text('View details').first);
      await t.pumpAndSettle();
      final low = lowContrastText(
              t,
              find.ancestor(
                  of: find.text('Where this came from'),
                  matching: find.byType(Scaffold)))
          .toSet();
      expect(low, isEmpty, reason: low.join('\n'));
    });
  }

  testWidgets('TC-HDATA-026: search narrows the history to matching records, '
      'and Clear filters restores it and empties the field', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await pump(t, fixtures());
    await settle(t);
    expect(find.text('5 events'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'pneumonia');
    await t.pumpAndSettle();
    expect(find.text('1 events'), findsOneWidget);
    expect(find.text('Simple pneumonia and pleurisy with CC'), findsOneWidget);
    expect(find.text('Medicare Part A (Hospital Insurance)'), findsNothing);
    await t.tap(find.text('Clear filters'));
    await t.pumpAndSettle();
    expect(find.text('5 events'), findsOneWidget);
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    await t.enterText(find.byType(TextField), 'no such record');
    await t.pumpAndSettle();
    expect(find.text('No health records found'), findsOneWidget);
  });

  testWidgets('TC-HDATA-027: the Claims filter shows only claims, and All '
      'brings back every record', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await pump(t, fixtures());
    await settle(t);
    await t.tap(find.widgetWithText(FilterChip, 'Claims'));
    await t.pumpAndSettle();
    expect(find.text('2 events'), findsOneWidget);
    expect(find.text('Medicare Part A (Hospital Insurance)'), findsNothing);
    await t.tap(find.widgetWithText(FilterChip, 'All'));
    await t.pumpAndSettle();
    expect(find.text('5 events'), findsOneWidget);
  });

  testWidgets('TC-HDATA-029: records and patient details from the other '
      'providers show beside Medicare', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await pump(
        t,
        RouteAdapter({
          '/v1/api/medicare/visits': envelope(const []),
          '/v1/api/medicare/coverage':
              envelope(fixtureResources('coverage-bundle.json')),
          '/api/ehr/resources':
              '[{"resourceId":"epic-1","source":"EPIC","category":"Medications",'
                  '"title":"Lisinopril 10 mg","occurredAt":"2026-09-01T00:00:00Z",'
                  '"status":"active"}]',
          '/api/ehr/patient':
              '{"name":"Test Patient","birthDate":"1980-05-14","gender":"female"}',
        }));
    await settle(t);
    expect(find.text('Lisinopril 10 mg'), findsOneWidget);
    expect(find.text('Medicare Part A (Hospital Insurance)'), findsOneWidget);
    expect(find.text('Patient Information'), findsOneWidget);
    expect(find.text('Test Patient'), findsOneWidget);
    expect(find.text('May 14, 1980'), findsOneWidget);
    expect(find.text('Female'), findsOneWidget);
  });
}
