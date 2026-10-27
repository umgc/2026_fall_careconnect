// HealthDataScreen states: loading, loaded (synthetic), backend failure,
// empty, and the sample records it renders alongside Medicare.

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/features/health/health_data/pages/health_data_screen.dart';
import 'package:care_connect_app/features/health/health_data/services/athena_connect_service.dart';
import 'package:care_connect_app/features/health/health_data/services/identity_conflict_service.dart';
import 'package:care_connect_app/features/health/health_data/widgets/athena_connect_tile.dart';
import 'package:care_connect_app/providers/user_provider.dart';
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
        '/v1/api/medicare/visits':
            envelope(fixtureResources('eob-bundle.json')),
        '/v1/api/medicare/coverage':
            envelope(fixtureResources('coverage-bundle.json')),
      }, gate: gate);

  Future<void> pump(
    WidgetTester t,
    HttpClientAdapter a, {
    int? patientId,
  }) async {
    ApiClient.instance.debugSetHttpClientAdapter(a);
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HealthDataScreen(patientId: patientId),
      ),
    );
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

  testWidgets(
      'TC-HDATA-009: a loading state shows until Medicare answers '
      '(FR-MCR-27)', (t) async {
    final gate = Completer<void>();
    await pump(t, fixtures(gate: gate));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading your health data…'), findsOneWidget);
    gate.complete();
    await settle(t);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
      'TC-HDATA-010: loaded mock data shows the demo-data banner and '
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
              .descendant(
                  of: find.byType(ListView), matching: find.byType(Scrollable))
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
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await t.tap(details.first);
    await t.pumpAndSettle();
    expect(find.text('Where this came from'), findsOneWidget);
    expect(find.text('Medicare'), findsOneWidget);
  });

  testWidgets(
      'TC-HDATA-011: when Medicare cannot be reached the screen says '
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

  testWidgets(
      'TC-HDATA-012: a linked account with no Medicare records shows '
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

  testWidgets(
      'TC-HDATA-013: no built-in sample records are shown as the '
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

  testWidgets(
      'TC-HDATA-014: leaving the screen before Medicare answers '
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
    testWidgets(
        'TC-HDATA-015: every text on the loaded screen has at least '
        '4.5:1 contrast against what is behind it, in the app\'s ${theme.key} '
        'theme (WCAG 2.1 SC 1.4.3)', (t) async {
      await t.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      ApiClient.instance.debugSetHttpClientAdapter(RouteAdapter({
        '/v1/api/medicare/visits':
            envelope(fixtureResources('eob-bundle.json')),
      }, status: {
        '/v1/api/medicare/coverage': 503
      }));
      await t.pumpWidget(MaterialApp(
        theme: theme.value,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HealthDataScreen(),
      ));
      await settle(t);
      final low = lowContrastText(t, find.byType(ListView)).toSet();
      expect(low, isEmpty, reason: low.join('\n'));
    });
  }

  // ---- PR #263 re-review, 2026-10-06 ----

  testWidgets(
      'TC-HDATA-020: when Medicare rejects the stored link (409 '
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

  testWidgets(
      'TC-HDATA-021: a patient with no Medicare link (404) is offered '
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

  testWidgets(
      'TC-HDATA-023: when the other providers cannot be read the '
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
        find.textContaining(
            RegExp('couldn.t .*Oracle Health', caseSensitive: false)),
        findsOneWidget);
    expect(
        find.text('Simple pneumonia and pleurisy with CC', skipOffstage: false),
        findsOneWidget);
  });

  testWidgets(
      'TC-HDATA-024: View details shows the claim type, title, '
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
    testWidgets(
        'TC-HDATA-025: every text on the details screen has at least '
        '4.5:1 contrast, in the app\'s ${theme.key} theme (WCAG 2.1 SC 1.4.3)',
        (t) async {
      await t.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      ApiClient.instance.debugSetHttpClientAdapter(fixtures());
      await t.pumpWidget(MaterialApp(
        theme: theme.value,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HealthDataScreen(),
      ));
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

  testWidgets(
      'TC-HDATA-026: search narrows the history to matching records, '
      'and Clear filters restores it and empties the field', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await pump(t, fixtures());
    await settle(t);
    expect(find.text('5 events'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'pneumonia');
    await t.pumpAndSettle();
    expect(find.text('1 event'), findsOneWidget);
    expect(find.text('Simple pneumonia and pleurisy with CC'), findsOneWidget);
    expect(find.text('Medicare Part A (Hospital Insurance)'), findsNothing);
    await t.tap(find.text('Clear filters'));
    await t.pumpAndSettle();
    expect(find.text('5 events'), findsOneWidget);
    expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    await t.enterText(find.byType(TextField), 'no such record');
    await t.pumpAndSettle();
    expect(find.text('No health records found'), findsOneWidget);
  });

  testWidgets(
      'TC-HDATA-027: the Claims filter shows only claims, and All '
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

  testWidgets(
      'TC-HDATA-029: records and patient details from the other '
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

  testWidgets('athenahealth records show beside Epic and Medicare', (t) async {
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
                  '"title":"Lisinopril 10 mg","occurredAt":"2026-09-01T00:00:00Z"}]',
          '/api/athena/resources': '{"items":[{"resourceType":"Condition",'
              '"resourceId":"ath-1","category":"Conditions",'
              '"title":"Type 2 diabetes","status":"active",'
              '"occurredAt":"2026-07-01T00:00:00Z",'
              '"lastSyncedAt":"2026-10-14T12:00:00Z",'
              '"source":"ATHENAHEALTH"}],"page":0,"size":100,"hasNext":false}',
        }));
    await settle(t);
    expect(find.text('Lisinopril 10 mg'), findsOneWidget);
    expect(find.text('Type 2 diabetes'), findsOneWidget);
    expect(find.text('Medicare Part A (Hospital Insurance)'), findsOneWidget);
    expect(find.textContaining('athenahealth isn'), findsNothing);
  });

  RouteAdapter athenaNotConnected() => RouteAdapter({
        '/v1/api/medicare/visits': envelope(const []),
        '/v1/api/medicare/coverage': envelope(const []),
        '/api/ehr/resources': '[]',
      }, status: {
        '/api/athena/resources': 409,
      }, statusBodies: {
        '/api/athena/resources': '{"code":"NOT_CONNECTED"}',
      });

  testWidgets(
      'when athenahealth is not connected the screen offers to '
      'connect it', (t) async {
    await pump(t, athenaNotConnected());
    await settle(t);
    expect(find.text('athenahealth isn\'t connected yet.'), findsOneWidget);
    expect(find.text('Connect athenahealth'), findsOneWidget);
  });

  group('connecting athenahealth from the banner', () {
    late AthenaConnectService original;
    setUp(() => original = AthenaConnectService.instance);
    tearDown(() => AthenaConnectService.instance = original);

    Future<RouteAdapter> openConsent(
        WidgetTester t, _BannerAthena athena) async {
      AthenaConnectService.instance = athena;
      final adapter = athenaNotConnected();
      await pump(t, adapter);
      await settle(t);
      await t.tap(find.text('Connect athenahealth'));
      await t.pumpAndSettle();
      return adapter;
    }

    Finder dialogConnect() => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Connect'));

    testWidgets('asks for consent in place, with the same text as Settings',
        (t) async {
      final athena = _BannerAthena();
      await openConsent(t, athena);
      expect(find.text(AthenaConnectTile.consentText), findsOneWidget);
      expect(t.widget<FilledButton>(dialogConnect()).onPressed, isNull);
      // Still on Health Data: nothing navigated away.
      expect(find.text('Health Data'), findsOneWidget);

      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(athena.connects, 0);
      expect(find.text('athenahealth isn\'t connected yet.'), findsOneWidget);
    });

    testWidgets(
        'agreeing connects, says so in a snackbar and reloads the '
        'records', (t) async {
      final athena = _BannerAthena(
          result: AthenaStatus(
              connected: true,
              sync: AthenaSyncResult(completed: true, types: const [
                AthenaTypeResult(
                    resourceType: 'Condition',
                    outcome: AthenaTypeOutcome.stored,
                    count: 2),
              ])));
      final adapter = await openConsent(t, athena);
      final readsBefore = adapter.paths
          .where((p) => p.endsWith('/api/athena/resources'))
          .length;
      await t.tap(find.byType(Checkbox));
      await t.pump();
      await t.tap(dialogConnect());
      await settle(t);

      expect(athena.connects, 1);
      expect(find.textContaining('2 records are now in Health Data'),
          findsOneWidget);
      // The reload runs on real time (Dio): wait for its athena read.
      int reads() => adapter.paths
          .where((p) => p.endsWith('/api/athena/resources'))
          .length;
      for (var i = 0; i < 40 && reads() <= readsBefore; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(reads(), greaterThan(readsBefore));
    });

    testWidgets('a chart that can\'t be linked says why and the banner stays',
        (t) async {
      final athena = _BannerAthena(
          result: const AthenaStatus(
              connected: false, reason: AthenaNotConnectedReason.notMatched));
      await openConsent(t, athena);
      await t.tap(find.byType(Checkbox));
      await t.pump();
      await t.tap(dialogConnect());
      await settle(t);
      expect(find.textContaining('couldn\'t find an athenahealth chart'),
          findsOneWidget);
      expect(find.text('athenahealth isn\'t connected yet.'), findsOneWidget);
      expect(find.text('Connect athenahealth'), findsOneWidget);
    });
  });

  RouteAdapter athenaOff() => RouteAdapter({
        '/v1/api/medicare/visits': envelope(const []),
        '/v1/api/medicare/coverage': envelope(const []),
        '/api/ehr/resources': '[]',
      }, status: {
        '/api/athena/resources': 404,
      });

  testWidgets(
      'when the server has athenahealth turned off a patient is '
      'still offered Connect, as with Epic', (t) async {
    await pump(t, athenaOff());
    await settle(t);
    expect(find.text('athenahealth isn\'t connected yet.'), findsOneWidget);
    expect(find.text('Connect athenahealth'), findsOneWidget);
  });

  for (final role in ['CAREGIVER', 'ADMIN', 'FAMILY_MEMBER']) {
    testWidgets(
        'athenahealth stays hidden from a $role even when the server '
        'has it turned off', (t) async {
      ApiClient.instance.debugSetHttpClientAdapter(athenaOff());
      await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
        create: (_) => UserProvider()
          ..setUser(UserSession(
              id: 2, email: 'user@example.com', role: role, token: 't')),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HealthDataScreen(),
        ),
      ));
      await settle(t);
      expect(find.textContaining('athenahealth'), findsNothing);
    });
  }

  testWidgets('a signed-in patient sees the banner when athena is off',
      (t) async {
    ApiClient.instance.debugSetHttpClientAdapter(athenaOff());
    await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
      create: (_) => UserProvider()
        ..setUser(UserSession(
            id: 1, email: 'patient@example.com', role: 'PATIENT', token: 't')),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HealthDataScreen(),
      ),
    ));
    await settle(t);
    expect(find.text('Connect athenahealth'), findsOneWidget);
  });

  RouteAdapter duplicates(String athenaStatus) => RouteAdapter({
        '/v1/api/medicare/visits': envelope(const []),
        '/v1/api/medicare/coverage': envelope(const []),
        '/api/ehr/resources': '[{"resourceType":"Condition",'
            '"resourceId":"epic-1","source":"EPIC","category":"Conditions",'
            '"title":"Type 2 diabetes","status":"active",'
            '"occurredAt":"2026-07-01T00:00:00Z",'
            '"lastSyncedAt":"2026-10-14T12:00:00Z"}]',
        '/api/athena/resources': '{"items":[{"resourceType":"Condition",'
            '"resourceId":"ath-1","category":"Conditions",'
            '"title":"Type 2 diabetes","status":"$athenaStatus",'
            '"occurredAt":"2026-07-01T00:00:00Z",'
            '"source":"ATHENAHEALTH"}],"page":0,"size":100,"hasNext":false}',
      });

  testWidgets(
      'the same record from two providers shows once, without a '
      'popup, and is flagged as a possible duplicate (WBS 6.2.41)', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await pump(t, duplicates('active'));
    await settle(t);
    expect(find.text('Type 2 diabetes'), findsOneWidget);
    expect(find.text('Which is correct?'), findsNothing);
    expect(find.textContaining('different details'), findsNothing);
    expect(
        find.text('1 possible duplicate record was combined.'), findsOneWidget);

    await t.tap(find.text('Review'));
    await settle(t);
    expect(find.text('Is this the same record?'), findsOneWidget);
    expect(find.text('From Epic, updated Oct 14, 2026'), findsOneWidget);
    await t.tap(find.text('Same record'));
    await settle(t);
    expect(find.text('Type 2 diabetes'), findsOneWidget);
    expect(find.textContaining('possible duplicate'), findsNothing);
  });

  testWidgets(
      'when providers disagree the patient is asked once, and the '
      'chosen version is shown and remembered', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await pump(t, duplicates('resolved'));
    await settle(t);
    expect(find.text('Which is correct?'), findsOneWidget);
    expect(find.text('Version 1'), findsOneWidget);
    expect(find.text('Version 2'), findsOneWidget);
    // The review is the one place a source is shown, with provenance
    // (WBS 6.2.41).
    expect(find.text('From Epic, updated Oct 14, 2026'), findsOneWidget);
    expect(find.text('From athenahealth'), findsOneWidget);

    await t.tap(find.text('Use version 2'));
    await settle(t);
    expect(find.text('Which is correct?'), findsNothing);
    expect(find.textContaining('different details'), findsNothing);
    expect(find.text('resolved'), findsOneWidget);
    expect(find.text('Type 2 diabetes'), findsOneWidget);

    // Opening the screen again doesn't ask again.
    await t.pumpWidget(const SizedBox());
    await pump(t, duplicates('resolved'));
    await settle(t);
    expect(find.text('Which is correct?'), findsNothing);
    expect(find.text('resolved'), findsOneWidget);
  });

  testWidgets(
      '"Decide later" shows Epic\'s version and leaves a Review '
      'banner', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await pump(t, duplicates('resolved'));
    await settle(t);
    await t.tap(find.text('Decide later'));
    await settle(t);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('1 record has different details from your providers.'),
        findsOneWidget);
    await t.tap(find.text('Review'));
    await settle(t);
    expect(find.text('Which is correct?'), findsOneWidget);
  });

  testWidgets(
      '"Keep both" shows each version as its own record and isn\'t '
      'asked again', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await pump(t, duplicates('resolved'));
    await settle(t);
    await t.tap(find.text('Keep both'));
    await settle(t);
    expect(find.text('Type 2 diabetes'), findsNWidgets(2));
    expect(find.textContaining('different details'), findsNothing);
    // The record cards don't name a source (the details screen does).
    expect(find.textContaining('From Epic'), findsNothing);

    await t.pumpWidget(const SizedBox());
    await pump(t, duplicates('resolved'));
    await settle(t);
    expect(find.text('Which is correct?'), findsNothing);
    expect(find.text('Type 2 diabetes'), findsNWidgets(2));
  });

  testWidgets(
      'FR-EHR-07: a medication the providers disagree on shows both '
      'versions, is never overwritten, and isn\'t flagged', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await pump(
        t,
        RouteAdapter({
          '/v1/api/medicare/visits': envelope(const []),
          '/v1/api/medicare/coverage': envelope(const []),
          '/api/ehr/resources': '[{"resourceType":"MedicationRequest",'
              '"resourceId":"epic-m","source":"EPIC","category":"Medications",'
              '"title":"Lisinopril 10 mg","status":"active"}]',
          '/api/athena/resources': '{"items":[{"resourceType":"MedicationRequest",'
              '"resourceId":"ath-m","category":"Medications",'
              '"title":"Lisinopril 10 mg","status":"stopped",'
              '"source":"ATHENAHEALTH"}],"page":0,"size":100,"hasNext":false}',
        }));
    await settle(t);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Lisinopril 10 mg'), findsNWidgets(2));
    expect(find.textContaining('caregiver'), findsNothing);
    expect(find.text('Review'), findsNothing);
  });

  for (final kind in ['resolved', 'active']) {
    testWidgets('the review dialog meets 4.5:1 contrast (NFR-ACC-07, $kind)',
        (t) async {
      await t.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await pump(t, duplicates(kind));
      await settle(t);
      if (kind == 'active') {
        await t.tap(find.text('Review'));
        await settle(t);
      }
      final low = lowContrastText(t, find.byType(AlertDialog)).toSet();
      expect(low, isEmpty, reason: low.join('\n'));
    });
  }

  group('athenahealth off on a server that answers 500 for the missing route',
      () {
    late AthenaConnectService original;
    setUp(() => original = AthenaConnectService.instance);
    tearDown(() => AthenaConnectService.instance = original);

    RouteAdapter athena500() => RouteAdapter({
          '/v1/api/medicare/visits': envelope(const []),
          '/v1/api/medicare/coverage': envelope(const []),
          '/api/ehr/resources': '[]',
        }, status: {
          '/api/athena/resources': 500,
        }, statusBodies: {
          '/api/athena/resources': '{"error":"An unexpected error occurred"}',
        });

    testWidgets(
        'a patient still gets the banner with Connect, not a '
        '"couldn\'t load" message', (t) async {
      AthenaConnectService.instance = _StatusAthena(null);
      await pump(t, athena500());
      await settle(t);
      expect(find.text('athenahealth isn\'t connected yet.'), findsOneWidget);
      expect(find.text('Connect athenahealth'), findsOneWidget);
      expect(find.textContaining('other providers'), findsNothing);
    });

    testWidgets(
        'a connected patient whose read fails is told it couldn\'t '
        'load, not asked to connect', (t) async {
      AthenaConnectService.instance =
          _StatusAthena(const AthenaStatus(connected: true));
      await pump(t, athena500());
      await settle(t);
      expect(find.textContaining('other providers'), findsOneWidget);
      expect(find.text('athenahealth isn\'t connected yet.'), findsNothing);
    });
  });

  testWidgets(
      'with no Patient Information the records use the full width '
      '(no empty left column)', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await pump(t, fixtures());
    await settle(t);
    expect(find.text('Patient Information'), findsNothing);
    final history = t.getRect(find.text('Your health history'));
    expect(history.left, lessThan(100));
  });

  testWidgets(
      'with Patient Information it sits in its own column beside the '
      'records', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await pump(
        t,
        RouteAdapter({
          '/v1/api/medicare/visits': envelope(const []),
          '/v1/api/medicare/coverage': envelope(const []),
          '/api/ehr/resources': '[]',
          '/api/ehr/patient':
              '{"name":"Test Patient","birthDate":"1980-05-14","gender":"female"}',
        }));
    await settle(t);
    final card = t.getRect(find.text('Patient Information'));
    final history = t.getRect(find.text('Your health history'));
    expect(history.left, greaterThan(card.right));
  });

  testWidgets(
      '"Decide later" on the first of two records stops the review; '
      'both stay flagged', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    String row(String id, String source, String title, String status) =>
        '{"resourceType":"Condition","resourceId":"$id","source":"$source",'
        '"category":"Conditions","title":"$title","status":"$status",'
        '"occurredAt":"2026-07-01T00:00:00Z"}';
    await pump(
        t,
        RouteAdapter({
          '/v1/api/medicare/visits': envelope(const []),
          '/v1/api/medicare/coverage': envelope(const []),
          '/api/ehr/resources': '[${row('e1', 'EPIC', 'Asthma', 'active')},'
              '${row('e2', 'EPIC', 'Type 2 diabetes', 'active')}]',
          '/api/athena/resources': '{"items":['
              '${row('a1', 'ATHENAHEALTH', 'Asthma', 'resolved')},'
              '${row('a2', 'ATHENAHEALTH', 'Type 2 diabetes', 'resolved')}'
              '],"page":0,"size":100,"hasNext":false}',
        }));
    await settle(t);
    expect(find.textContaining('(1 of 2)'), findsOneWidget);
    await t.tap(find.text('Decide later'));
    await settle(t);
    expect(find.textContaining('(2 of 2)'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('2 records have different details from your providers.'),
        findsOneWidget);
  });

  // Failing-first for R381-D04: only records whose details differ pop up by
  // themselves; a possible duplicate and a medication wait in the banner.
  testWidgets('the automatic review asks only about records that differ',
      (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    String row(String id, String source, String type, String category,
            String title, String status) =>
        '{"resourceType":"$type","resourceId":"$id","source":"$source",'
        '"category":"$category","title":"$title","status":"$status",'
        '"occurredAt":"2026-07-01T00:00:00Z"}';
    await pump(
        t,
        RouteAdapter({
          '/v1/api/medicare/visits': envelope(const []),
          '/v1/api/medicare/coverage': envelope(const []),
          '/api/ehr/resources': '['
              '${row('e1', 'EPIC', 'Condition', 'Conditions', 'Type 2 diabetes', 'active')},'
              '${row('e2', 'EPIC', 'MedicationRequest', 'Medications', 'Lisinopril', 'active')},'
              '${row('e3', 'EPIC', 'Condition', 'Conditions', 'Asthma', 'active')}]',
          '/api/athena/resources': '{"items":['
              '${row('a1', 'ATHENAHEALTH', 'Condition', 'Conditions', 'Type 2 diabetes', 'active')},'
              '${row('a2', 'ATHENAHEALTH', 'MedicationRequest', 'Medications', 'Lisinopril', 'stopped')},'
              '${row('a3', 'ATHENAHEALTH', 'Condition', 'Conditions', 'Asthma', 'resolved')}'
              '],"page":0,"size":100,"hasNext":false}',
        }));
    await settle(t);
    expect(find.text('Which is correct?'), findsOneWidget);
    expect(find.textContaining('of 3)'), findsNothing);
    await t.tap(find.text('Use version 2'));
    await settle(t);
    expect(find.byType(AlertDialog), findsNothing);
    // The disagreeing medication shows both versions and isn't flagged.
    expect(
        find.text('1 possible duplicate record was combined.'), findsOneWidget);
    expect(find.text('Lisinopril'), findsNWidgets(2));
    // Review still goes through the one left.
    await t.tap(find.text('Review'));
    await settle(t);
    expect(find.text('Is this the same record?'), findsOneWidget);
  });

  // Failing-first for R381-D05: the same record from Epic and athenahealth has
  // the same detail rows, so a possible duplicate marks nothing as different.
  testWidgets('a possible duplicate marks no field as different', (t) async {
    final semantics = t.ensureSemantics();
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await pump(t, duplicates('active'));
    await settle(t);
    await t.tap(find.text('Review'));
    await settle(t);
    expect(find.text('Is this the same record?'), findsOneWidget);
    expect(find.bySemanticsLabel('Different'), findsNothing);
    semantics.dispose();
  });

  // Failing-first for R381-D03: the version the patient chose must keep its
  // own source first, or its full record can't be opened.
  testWidgets(
      'after choosing the athenahealth version, View details still '
      'offers its full record', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await pump(t, duplicates('resolved'));
    await settle(t);
    await t.tap(find.text('Use version 2'));
    await settle(t);
    expect(find.text('resolved'), findsOneWidget);
    await t.tap(find.text('View details'));
    await t.pumpAndSettle();
    expect(find.text('View full record'), findsOneWidget);
  });

  testWidgets(
      'an athenahealth-only record offers its full record; an Epic '
      'one does not', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await pump(t, duplicates('resolved'));
    await settle(t);
    await t.tap(find.text('Keep both'));
    await settle(t);
    final details = find.text('View details');
    expect(details, findsNWidgets(2));
    await t.tap(details.first);
    await t.pumpAndSettle();
    expect(find.text('active'), findsOneWidget);
    expect(find.text('View full record'), findsNothing);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('View details').last);
    await t.pumpAndSettle();
    expect(find.text('resolved'), findsOneWidget);
    expect(find.text('View full record'), findsOneWidget);
  });

  group('Epic and athenahealth disagree on the date of birth', () {
    setUp(IdentityConflictService.clearFound);

    _DobAdapter dobs() => _DobAdapter(
          epic:
              '{"name":"Test Patient","birthDate":"1980-05-14","gender":"female"}',
          athena:
              '{"name":"Test Patient","birthDate":"1980-05-15","gender":"female"}',
          rest: RouteAdapter({
            '/v1/api/medicare/visits': envelope(const []),
            '/v1/api/medicare/coverage': envelope(const []),
            '/api/ehr/resources': '[]',
          }),
        );

    testWidgets(
        'the screen asks to confirm, keeps the current date until '
        'then, and queues it for the DOB confirmation screen', (t) async {
      await t.binding.setSurfaceSize(const Size(1200, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await pump(t, dobs());
      await settle(t);
      expect(
          find.text('Your providers have different dates of birth for you. '
              'Please confirm which is correct.'),
          findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Confirm'), findsOneWidget);
      expect(find.text('May 14, 1980'), findsOneWidget);
      expect(find.text('Needs your confirmation'), findsOneWidget);

      final pending =
          await IdentityConflictService(useMock: false).fetchPending();
      expect(pending.single.canonicalValueBefore, '05/14/1980');
      expect(pending.single.incomingValue, '05/15/1980');
    });

    testWidgets(
        'once the patient chooses, the card shows that date and '
        'nothing asks again', (t) async {
      await t.binding.setSurfaceSize(const Size(1200, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await pump(t, dobs());
      await settle(t);
      final service = IdentityConflictService(useMock: false);
      final id = (await t.runAsync(service.fetchPending))!.single.id;
      expect(
          await t.runAsync(() => service.resolve(id, accepted: true)), isTrue);

      await t.pumpWidget(const SizedBox());
      await pump(t, dobs());
      await settle(t);
      expect(find.text('May 15, 1980'), findsOneWidget);
      expect(find.text('Needs your confirmation'), findsNothing);
      expect(find.textContaining('different dates of birth'), findsNothing);
    });

    testWidgets('the same date from both sources asks nothing', (t) async {
      await t.binding.setSurfaceSize(const Size(1200, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final same = dobs()..athena = dobs().epic;
      await pump(t, same);
      await settle(t);
      expect(find.text('May 14, 1980'), findsOneWidget);
      expect(find.textContaining('different dates of birth'), findsNothing);
      expect(await IdentityConflictService(useMock: false).fetchPending(),
          isEmpty);
    });
  });

  // Review follow-up: the automatic review used to open only on the first
  // load. Now each conflict pops up by itself once while the screen is open.
  group('the automatic review after a reload', () {
    late AthenaConnectService original;
    setUp(() {
      original = AthenaConnectService.instance;
      IdentityConflictService.clearFound();
    });
    tearDown(() => AthenaConnectService.instance = original);

    String condition(String id, String source, String status) =>
        '{"resourceType":"Condition","resourceId":"$id","source":"$source",'
        '"category":"Conditions","title":"Asthma","status":"$status",'
        '"occurredAt":"2026-07-01T00:00:00Z"}';
    String athenaPage(String status) =>
        '{"items":[${condition('a1', 'ATHENAHEALTH', status)}],'
        '"page":0,"size":100,"hasNext":false}';

    /// Lets the reload, which runs on real time (Dio), finish.
    Future<void> settleReload(WidgetTester t) async {
      for (var i = 0; i < 30; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pumpAndSettle();
    }

    testWidgets(
        'a conflict that appears after connecting athenahealth opens '
        'the review by itself', (t) async {
      await t.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      AthenaConnectService.instance =
          _BannerAthena(result: const AthenaStatus(connected: true));
      final routes = <String, String>{
        '/v1/api/medicare/visits': envelope(const []),
        '/v1/api/medicare/coverage': envelope(const []),
        '/api/ehr/resources': '[${condition('e1', 'EPIC', 'active')}]',
      };
      final status = <String, int>{'/api/athena/resources': 409};
      await pump(
          t,
          RouteAdapter(routes, status: status, statusBodies: const {
            '/api/athena/resources': '{"code":"NOT_CONNECTED"}'
          }));
      await settle(t);
      expect(find.byType(AlertDialog), findsNothing);

      // athenahealth connects and now has a different version of Asthma.
      status.remove('/api/athena/resources');
      routes['/api/athena/resources'] = athenaPage('resolved');
      await t.tap(find.text('Connect athenahealth'));
      await t.pumpAndSettle();
      await t.tap(find.byType(Checkbox));
      await t.pump();
      await t.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Connect')));
      await settleReload(t);
      expect(find.text('Which is correct?'), findsOneWidget);
    });

    testWidgets(
        'after a reload, a new conflict opens the review by itself '
        'but one put off with "Decide later" is not asked again', (t) async {
      await t.binding.setSurfaceSize(const Size(1200, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final routes = <String, String>{
        '/v1/api/medicare/visits': envelope(const []),
        '/v1/api/medicare/coverage': envelope(const []),
        '/api/ehr/resources': '[${condition('e1', 'EPIC', 'active')}]',
        '/api/athena/resources': athenaPage('resolved'),
      };
      ApiClient.instance.debugSetHttpClientAdapter(_DobAdapter(
        epic: '{"name":"Test Patient","birthDate":"1980-05-14"}',
        athena: '{"name":"Test Patient","birthDate":"1980-05-15"}',
        rest: RouteAdapter(routes),
      ));
      final router = GoRouter(initialLocation: '/health-data', routes: [
        GoRoute(
            path: '/health-data', builder: (_, __) => const HealthDataScreen()),
        GoRoute(
            path: '/dob-confirm',
            builder: (context, _) => Scaffold(
                body: TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('Back from DOB confirmation')))),
      ]);
      await t.pumpWidget(
        MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      );
      await settle(t);
      expect(find.text('Which is correct?'), findsOneWidget);
      await t.tap(find.text('Decide later'));
      await t.pumpAndSettle();

      // Meanwhile a second record starts to differ between the providers.
      routes['/api/ehr/resources'] = '[${condition('e1', 'EPIC', 'active')},'
          '${condition('e2', 'EPIC', 'active').replaceAll('Asthma', 'Gout')}]';
      routes['/api/athena/resources'] = '{"items":['
          '${condition('a1', 'ATHENAHEALTH', 'resolved')},'
          '${condition('a2', 'ATHENAHEALTH', 'resolved').replaceAll('Asthma', 'Gout')}'
          '],"page":0,"size":100,"hasNext":false}';

      // Confirming the date of birth reloads the screen.
      await t.tap(find.widgetWithText(TextButton, 'Confirm'));
      await t.pumpAndSettle();
      await t.tap(find.text('Back from DOB confirmation'));
      await settleReload(t);

      // Only the new one asks: one dialog, not "(1 of 2)", and it is Gout.
      expect(find.text('Which is correct?'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.text('Gout')),
          findsWidgets);
      expect(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.text('Asthma')),
          findsNothing);
      await t.tap(find.text('Decide later'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('2 records have different details from your providers.'),
          findsOneWidget);
    });
  });

  testWidgets(
      'TC-HDATA-040: a Cerner allergy appears in the shared history, '
      'uses the Allergies filter, and preserves Cerner provenance', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await pump(
        t,
        RouteAdapter({
          '/v1/api/medicare/visits': envelope(const []),
          '/v1/api/medicare/coverage':
              envelope(fixtureResources('coverage-bundle.json')),
          '/api/ehr/resources':
              '[{"resourceId":"cerner-allergy-1","source":"CERNER",'
                  '"category":"Allergies","title":"Penicillin",'
                  '"occurredAt":"2026-09-10T00:00:00Z","status":"active"},'
                  '{"resourceId":"epic-medication-1","source":"EPIC",'
                  '"category":"Medications","title":"Lisinopril 10 mg",'
                  '"occurredAt":"2026-09-01T00:00:00Z","status":"active"}]',
          '/api/ehr/patient': '{"name":"Test Patient","birthDate":"1980-05-14",'
              '"gender":"female"}',
        }));

    await settle(t);

    // Cerner, Epic, and Medicare use the same health-history list.
    expect(find.text('Penicillin'), findsOneWidget);
    expect(find.text('Lisinopril 10 mg'), findsOneWidget);
    expect(find.text('Medicare Part A (Hospital Insurance)'), findsOneWidget);

    // The shared record-type filter recognizes the Cerner allergy.
    await t.tap(find.widgetWithText(FilterChip, 'Allergies'));
    await t.pumpAndSettle();

    expect(find.text('Penicillin'), findsOneWidget);
    expect(find.text('Lisinopril 10 mg'), findsNothing);
    expect(find.text('Medicare Part A (Hospital Insurance)'), findsNothing);

    // The existing details screen preserves the record's source.
    final details = find.text('View details');
    expect(details, findsOneWidget);
    await t.tap(details);
    await t.pumpAndSettle();

    expect(find.text('Where this came from'), findsOneWidget);
    expect(find.text('Oracle Health'), findsOneWidget);
  });
  testWidgets(
      'TC-HDATA-044: the patient ID loads Cerner backend records into '
      'the unified health history', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final adapter = RouteAdapter({
      '/api/ehr/resources': '[]',
      '/api/ehr/patient': '{}',
      '/v1/api/cerner/patients/7/allergies':
          '{"allergies":[{"source":"ORACLE_HEALTH",'
              '"sourceRecordId":"cerner-allergy-2",'
              '"substanceText":"Penicillin",'
              '"clinicalStatus":"active",'
              '"recordedDate":"2026-09-10"}]}',
      '/v1/api/cerner/patients/7/conditions': '{"conditions":[]}',
      '/v1/api/cerner/patients/7/encounters': '{"encounters":[]}',
      '/v1/api/medicare/visits': envelope(const []),
      '/v1/api/medicare/coverage': envelope(const []),
    });

    await pump(t, adapter, patientId: 7);
    await settle(t);

    expect(
      adapter.paths,
      contains('/v1/api/cerner/patients/7/allergies'),
    );
    expect(find.text('Penicillin'), findsOneWidget);
  });

  // Testing Lead (PR #364 review): the new forbidden problem must not change
  // what a patient sees on their own screen.
  testWidgets(
      'TC-HDATA-039: a 403 on the patient\'s own reads still shows ERR-MCR-03, '
      'as before PR #364 added the forbidden case', (t) async {
    await pump(
        t,
        RouteAdapter(const {}, status: {
          '/v1/api/medicare/visits': 403,
          '/v1/api/medicare/coverage': 403,
        }));
    await settle(t);
    expect(find.text(_errMcr03), findsOneWidget);
    expect(find.text('Medicare isn\'t connected yet.'), findsNothing);
  });
}

class _BannerAthena extends AthenaConnectService {
  _BannerAthena({this.result});
  final AthenaStatus? result;
  int connects = 0;

  @override
  Future<AthenaStatus?> status() async => const AthenaStatus(
      connected: false, reason: AthenaNotConnectedReason.notConsented);

  @override
  Future<AthenaStatus> connect() async {
    connects++;
    return result!;
  }
}

class _StatusAthena extends AthenaConnectService {
  _StatusAthena(this.result);
  final AthenaStatus? result;

  @override
  Future<AthenaStatus?> status() async => result;
}

/// Answers /api/ehr/patient by its ?source=; everything else from [rest].
class _DobAdapter implements HttpClientAdapter {
  _DobAdapter({required this.epic, required this.athena, required this.rest});
  String epic;
  String athena;
  final RouteAdapter rest;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.path.endsWith('/api/ehr/patient')) {
      final body =
          options.queryParameters['source'] == 'ATHENAHEALTH' ? athena : epic;
      return ResponseBody.fromString(body, 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });
    }
    return rest.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}
