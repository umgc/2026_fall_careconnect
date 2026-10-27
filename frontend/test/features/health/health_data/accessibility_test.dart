// Accessibility checks for the Unified Health Data screens (NFR-ACC-01…09,
// WCAG 2.1 AA) that the per-screen tests don't already cover:
//   - Flutter's guideline checkers: tap target size (SC 2.5.5 guidance /
//     Material 48dp), labelled tap targets (SC 4.1.2) and text contrast
//     (SC 1.4.3), in the light and dark themes
//   - 200% text (SC 1.4.4) and a 320px-wide screen (SC 1.4.10) lay out
//     without overflow
//   - screen-reader names, roles and announcements (SC 4.1.2, 4.1.3)
//   - keyboard operation (SC 2.1.1)
// These complement, not replace, the manual TalkBack / VoiceOver
// walkthroughs NFR-ACC asks for.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/features/health/health_data/models/health_record.dart';
import 'package:care_connect_app/features/health/health_data/pages/athena_connect_page.dart';
import 'package:care_connect_app/features/health/health_data/pages/athena_resource_detail_page.dart';
import 'package:care_connect_app/features/health/health_data/pages/health_data_screen.dart';
import 'package:care_connect_app/features/health/health_data/pages/health_event_details_screen.dart';
import 'package:care_connect_app/features/health/health_data/services/athena_connect_service.dart';
import 'package:care_connect_app/features/health/health_data/services/athena_data_service.dart';
import 'package:care_connect_app/features/health/health_data/widgets/athena_connect_tile.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/services/api_client.dart';

import 'health_data_test_support.dart';

const _themes = {'light': _Theme.light, 'dark': _Theme.dark};

enum _Theme { light, dark }

ThemeData _theme(_Theme t) =>
    t == _Theme.light ? AppTheme.lightTheme : AppTheme.darkTheme;

/// Epic, athenahealth and Medicare records, with one record the providers
/// disagree on (so the review popup opens) when [conflict] is true.
RouteAdapter _sources({bool conflict = false, Completer<void>? gate}) =>
    RouteAdapter({
      '/v1/api/medicare/visits': envelope(fixtureResources('eob-bundle.json')),
      '/v1/api/medicare/coverage':
          envelope(fixtureResources('coverage-bundle.json')),
      '/api/ehr/resources': '[{"resourceType":"Condition",'
          '"resourceId":"epic-1","source":"EPIC","category":"Conditions",'
          '"title":"Type 2 diabetes","status":"active",'
          '"occurredAt":"2026-07-01T00:00:00Z",'
          '"lastSyncedAt":"2026-10-14T12:00:00Z"},'
          '{"resourceType":"Encounter","resourceId":"epic-2","source":"EPIC",'
          '"category":"Care Context","title":"Annual physical",'
          '"occurredAt":"2026-05-02T00:00:00Z"}]',
      '/api/ehr/patient':
          '{"name":"Test Patient","birthDate":"1980-05-14","gender":"female"}',
      '/api/athena/resources': '{"items":[{"resourceType":"Condition",'
          '"resourceId":"ath-1","category":"Conditions",'
          '"title":"Type 2 diabetes","status":"${conflict ? 'resolved' : 'active'}",'
          '"occurredAt":"2026-07-01T00:00:00Z",'
          '"lastSyncedAt":"2026-10-13T12:00:00Z",'
          '"source":"ATHENAHEALTH"}],"page":0,"size":100,"hasNext":false}',
    }, gate: gate);

/// Runs [body] with the app's text at [scale] and the screen [width] wide.
Widget _sized(Widget child, {double scale = 1, double? width}) => Builder(
      builder: (context) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(scale),
            size: width == null ? mq.size : Size(width, mq.size.height),
          ),
          child: child,
        );
      },
    );

Future<void> _settle(WidgetTester t) async {
  for (var i = 0;
      i < 40 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      i++) {
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pumpAndSettle();
}

/// Every guideline this suite holds each screen to.
Future<void> _meetsGuidelines(WidgetTester t) async {
  await expectLater(t, meetsGuideline(androidTapTargetGuideline));
  await expectLater(t, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(t, meetsGuideline(textContrastGuideline));
}

/// Presses Tab until [target] holds keyboard focus; fails if it never does.
Future<void> _tabTo(WidgetTester t, Finder target) async {
  for (var i = 0; i < 60; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        find
            .descendant(of: target, matching: find.byWidget(focused.widget))
            .evaluate()
            .isNotEmpty) {
      return;
    }
  }
  fail('Tab never reached $target');
}

class _FakeAthena extends AthenaConnectService {
  _FakeAthena(this.statusResult, {this.connectResult});
  AthenaStatus? statusResult;
  AthenaStatus? connectResult;
  int connects = 0;

  @override
  Future<AthenaStatus?> status() async => statusResult;

  @override
  Future<AthenaStatus> connect() async {
    connects++;
    return connectResult!;
  }

  @override
  Future<bool> disconnect() async => true;
}

class _FakeAthenaData extends AthenaDataService {
  @override
  Future<Map<String, dynamic>?> fetchResource(String type, String id) async => {
        'resourceType': type,
        'resourceId': id,
        'category': 'Conditions',
        'title': 'Type 2 diabetes',
        'status': 'active',
        'occurredAt': '2026-07-01T00:00:00Z',
        'lastSyncedAt': '2026-10-14T12:00:00Z',
        'resource': {'resourceType': type, 'id': id},
      };
}

const _notConnected = AthenaStatus(
    connected: false, reason: AthenaNotConnectedReason.notConsented);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpClientAdapter original;
  late AthenaConnectService originalAthena;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    original = ApiClient.instance.debugHttpClientAdapter;
    originalAthena = AthenaConnectService.instance;
  });
  tearDown(() {
    ApiClient.instance.debugSetHttpClientAdapter(original);
    AthenaConnectService.instance = originalAthena;
  });

  Future<void> pumpScreen(
    WidgetTester t, {
    _Theme theme = _Theme.light,
    bool conflict = false,
    double scale = 1,
    double? width,
    Size surface = const Size(800, 3000),
  }) async {
    await t.binding.setSurfaceSize(surface);
    addTearDown(() => t.binding.setSurfaceSize(null));

    ApiClient.instance.debugSetHttpClientAdapter(
      _sources(conflict: conflict),
    );

    await t.pumpWidget(
      MaterialApp(
        theme: _theme(theme),
        builder: (_, child) => _sized(child!, scale: scale, width: width),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HealthDataScreen(),
      ),
    );

    await _settle(t);
  }

  // ---------------------------------------------------------------------
  group('Health Data screen', () {
    for (final e in _themes.entries) {
      testWidgets(
          'meets the tap-target, label and contrast guidelines '
          '(${e.key} theme)', (t) async {
        final h = t.ensureSemantics();
        await pumpScreen(t, theme: e.value);
        await _meetsGuidelines(t);
        h.dispose();
      });
    }

    testWidgets('lays out at 200% text without overflow (SC 1.4.4)', (t) async {
      await pumpScreen(t, scale: 2);
      expect(t.takeException(), isNull);
      expect(find.text('Type 2 diabetes'), findsOneWidget);
    });

    testWidgets('reflows on a 320px-wide screen at 200% text (SC 1.4.10)',
        (t) async {
      await pumpScreen(t, scale: 2, width: 320, surface: const Size(320, 6000));
      expect(t.takeException(), isNull);
      expect(find.text('Health Data'), findsOneWidget);
    });

    testWidgets('notices are announced to screen readers (SC 4.1.3)',
        (t) async {
      await pumpScreen(t);
      final banner = find.ancestor(
          of: find.textContaining('possible duplicate'),
          matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.liveRegion == true));
      expect(banner, findsOneWidget);
    });

    testWidgets(
        'the loading state has a text alternative, not just a '
        'spinner (SC 1.1.1)', (t) async {
      final gate = Completer<void>();
      ApiClient.instance.debugSetHttpClientAdapter(_sources(gate: gate));
      await t.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HealthDataScreen(),
        ),
      );
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading your health data…'), findsOneWidget);
      gate.complete();
      await _settle(t);
    });

    testWidgets(
        'the banner\'s Review button works from the keyboard '
        '(SC 2.1.1)', (t) async {
      await pumpScreen(t);
      await _tabTo(t, find.widgetWithText(TextButton, 'Review'));
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(find.text('Is this the same record?'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------
  group('athenahealth "not connected" banner', () {
    Future<_FakeAthena> pumpBanner(WidgetTester t,
        {_Theme theme = _Theme.light, double scale = 1}) async {
      final athena = _FakeAthena(_notConnected,
          connectResult: const AthenaStatus(connected: true));
      AthenaConnectService.instance = athena;
      await t.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      ApiClient.instance.debugSetHttpClientAdapter(RouteAdapter({
        '/v1/api/medicare/visits': envelope(const []),
        '/v1/api/medicare/coverage': envelope(const []),
        '/api/ehr/resources': '[]',
      }, status: {
        '/api/athena/resources': 409,
      }, statusBodies: {
        '/api/athena/resources': '{"code":"NOT_CONNECTED"}',
      }));
      await t.pumpWidget(
        MaterialApp(
          theme: _theme(theme),
          builder: (_, child) => _sized(child!, scale: scale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HealthDataScreen(),
        ),
      );
      await _settle(t);
      return athena;
    }

    for (final e in _themes.entries) {
      testWidgets(
          'the banner and its consent dialog meet the guidelines '
          '(${e.key} theme)', (t) async {
        final h = t.ensureSemantics();
        await pumpBanner(t, theme: e.value);
        expect(find.text('Connect athenahealth'), findsOneWidget);
        await _meetsGuidelines(t);
        await t.tap(find.text('Connect athenahealth'));
        await t.pumpAndSettle();
        await _meetsGuidelines(t);
        h.dispose();
      });
    }

    testWidgets('the banner and dialog lay out at 200% text', (t) async {
      await pumpBanner(t, scale: 2);
      expect(t.takeException(), isNull);
      await t.tap(find.text('Connect athenahealth'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('consent and connect work from the keyboard alone', (t) async {
      final athena = await pumpBanner(t);
      await _tabTo(t, find.widgetWithText(TextButton, 'Connect athenahealth'));
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      await _tabTo(t, find.byType(CheckboxListTile));
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      await _tabTo(
          t,
          find.descendant(
              of: find.byType(AlertDialog),
              matching: find.widgetWithText(FilledButton, 'Connect')));
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(athena.connects, 1);
    });
  });

  // ---------------------------------------------------------------------
  group('Duplicate review popup', () {
    for (final e in _themes.entries) {
      testWidgets('meets the guidelines and 4.5:1 contrast (${e.key} theme)',
          (t) async {
        final h = t.ensureSemantics();
        await pumpScreen(t, theme: e.value, conflict: true);
        expect(find.text('Which is correct?'), findsOneWidget);
        await _meetsGuidelines(t);
        final low = lowContrastText(t, find.byType(AlertDialog)).toSet();
        expect(low, isEmpty, reason: low.join('\n'));
        h.dispose();
      });
    }

    testWidgets(
        'a changed field is named "Different", not shown by colour '
        'alone (SC 1.4.1)', (t) async {
      final h = t.ensureSemantics();
      await pumpScreen(t, conflict: true);
      expect(find.bySemanticsLabel('Different'), findsWidgets);
      h.dispose();
    });

    testWidgets('lays out at 200% text without overflow', (t) async {
      await pumpScreen(t, conflict: true, scale: 2);
      expect(t.takeException(), isNull);
      expect(find.text('Use version 2'), findsOneWidget);
    });

    testWidgets('a version can be chosen from the keyboard', (t) async {
      await pumpScreen(t, conflict: true);
      await _tabTo(t, find.widgetWithText(ElevatedButton, 'Use version 2'));
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(t);
      expect(find.text('Which is correct?'), findsNothing);
      expect(find.text('resolved'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------
  group('Record details screen', () {
    final record = HealthRecord.single(
      id: 'ath-1',
      source: RecordSource.athena,
      type: RecordType.condition,
      title: 'Type 2 diabetes',
      date: DateTime(2026, 7, 1),
      status: 'active',
      resourceType: 'Condition',
      details: const [
        RecordDetail('Category', 'Conditions'),
        RecordDetail('Retrieved', 'Oct 14, 2026'),
      ],
    );

    Future<void> pumpDetails(WidgetTester t,
        {_Theme theme = _Theme.light, double scale = 1}) async {
      await t.pumpWidget(MaterialApp(
        theme: _theme(theme),
        builder: (_, child) => _sized(child!, scale: scale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HealthEventDetailsScreen(record: record),
      ));
      await t.pumpAndSettle();
    }

    for (final e in _themes.entries) {
      testWidgets('meets the guidelines (${e.key} theme)', (t) async {
        final h = t.ensureSemantics();
        await pumpDetails(t, theme: e.value);
        await _meetsGuidelines(t);
        h.dispose();
      });
    }

    testWidgets('lays out at 200% text without overflow', (t) async {
      await pumpDetails(t, scale: 2);
      expect(t.takeException(), isNull);
      expect(find.text('View full record'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------
  group('Full athenahealth record page', () {
    for (final e in _themes.entries) {
      testWidgets('meets the guidelines (${e.key} theme)', (t) async {
        final h = t.ensureSemantics();
        await t.pumpWidget(MaterialApp(
          theme: _theme(e.value),
          home: AthenaResourceDetailPage(
              resourceType: 'Condition',
              resourceId: 'ath-1',
              service: _FakeAthenaData()),
        ));
        await t.pumpAndSettle();
        expect(find.text('FHIR resource'), findsOneWidget);
        await _meetsGuidelines(t);
        h.dispose();
      });
    }

    testWidgets('lays out at 200% text without overflow', (t) async {
      await t.pumpWidget(MaterialApp(
        builder: (_, child) => _sized(child!, scale: 2),
        home: AthenaResourceDetailPage(
            resourceType: 'Condition',
            resourceId: 'ath-1',
            service: _FakeAthenaData()),
      ));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------
  group('athenahealth connect page and tile', () {
    Future<void> pumpPage(WidgetTester t,
        {_Theme theme = _Theme.light, double scale = 1}) async {
      AthenaConnectService.instance = _FakeAthena(_notConnected);
      await t.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
        theme: _theme(theme),
        builder: (_, child) => _sized(child!, scale: scale),
        home: const AthenaConnectPage(),
      ));
      await t.pumpAndSettle();
    }

    for (final e in _themes.entries) {
      testWidgets(
          '/athena-connect meets the guidelines and 4.5:1 contrast '
          '(${e.key} theme)', (t) async {
        final h = t.ensureSemantics();
        await pumpPage(t, theme: e.value);
        await _meetsGuidelines(t);
        final low = lowContrastText(t, find.byType(AthenaConnectTile)).toSet();
        expect(low, isEmpty, reason: low.join('\n'));
        h.dispose();
      });
    }

    testWidgets('/athena-connect lays out at 200% text without overflow',
        (t) async {
      await pumpPage(t, scale: 2);
      expect(t.takeException(), isNull);
      expect(find.text(AthenaConnectTile.consentText), findsOneWidget);
    });

    testWidgets('the back button has a name for screen readers', (t) async {
      final h = t.ensureSemantics();
      await pumpPage(t);
      expect(find.byTooltip('Back to Health Data'), findsOneWidget);
      h.dispose();
    });

    testWidgets('consent and Connect work from the keyboard alone', (t) async {
      final athena = _FakeAthena(_notConnected,
          connectResult: const AthenaStatus(connected: true));
      AthenaConnectService.instance = athena;
      await t.pumpWidget(const MaterialApp(home: AthenaConnectPage()));
      await t.pumpAndSettle();
      await _tabTo(t, find.byType(CheckboxListTile));
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      await _tabTo(
          t, find.widgetWithText(ElevatedButton, 'Connect athenahealth'));
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(athena.connects, 1);
    });

    testWidgets('a result message is announced to screen readers', (t) async {
      await t.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      AthenaConnectService.instance = _FakeAthena(_notConnected,
          connectResult: const AthenaStatus(
              connected: false, reason: AthenaNotConnectedReason.notMatched));
      await t.pumpWidget(const MaterialApp(home: AthenaConnectPage()));
      await t.pumpAndSettle();
      await t.tap(find.byType(Checkbox));
      await t.pump();
      await t.tap(find.widgetWithText(ElevatedButton, 'Connect athenahealth'));
      await t.pumpAndSettle();
      expect(
          find.ancestor(
              of: find.textContaining('couldn\'t find an athenahealth chart'),
              matching: find.byWidgetPredicate(
                  (w) => w is Semantics && w.properties.liveRegion == true)),
          findsOneWidget);
    });

    testWidgets('the busy state is announced as "Please wait"', (t) async {
      await t.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final gate = Completer<AthenaStatus>();
      AthenaConnectService.instance = _GatedAthena(gate);
      await t.pumpWidget(const MaterialApp(home: AthenaConnectPage()));
      await t.pumpAndSettle();
      await t.tap(find.byType(Checkbox));
      await t.pump();
      await t.tap(find.widgetWithText(ElevatedButton, 'Connect athenahealth'));
      await t.pump();
      expect(find.bySemanticsLabel('Please wait'), findsOneWidget);
      gate.complete(const AthenaStatus(connected: true));
      await t.pumpAndSettle();
    });
  });

  // ---------------------------------------------------------------------
  group('athenahealth Settings row', () {
    Future<void> pumpRow(WidgetTester t, AthenaConnectService s,
        {_Theme theme = _Theme.light, double scale = 1}) async {
      await t.pumpWidget(MaterialApp(
        theme: _theme(theme),
        builder: (_, child) => _sized(child!, scale: scale),
        home: Scaffold(
          body: ListView(
              children: [AthenaConnectTile(service: s, compact: true)]),
        ),
      ));
      await t.pumpAndSettle();
    }

    for (final e in _themes.entries) {
      testWidgets('meets the guidelines, connected or not (${e.key} theme)',
          (t) async {
        final h = t.ensureSemantics();
        await pumpRow(t, _FakeAthena(_notConnected), theme: e.value);
        await _meetsGuidelines(t);
        await pumpRow(t, _FakeAthena(const AthenaStatus(connected: true)),
            theme: e.value);
        await _meetsGuidelines(t);
        h.dispose();
      });
    }

    testWidgets('the consent dialog meets the guidelines', (t) async {
      final h = t.ensureSemantics();
      await pumpRow(t, _FakeAthena(_notConnected));
      await t.tap(find.widgetWithText(FilledButton, 'Connect'));
      await t.pumpAndSettle();
      await _meetsGuidelines(t);
      h.dispose();
    });

    testWidgets('lays out at 200% text without overflow', (t) async {
      await pumpRow(t, _FakeAthena(_notConnected), scale: 2);
      expect(t.takeException(), isNull);
      await t.tap(find.widgetWithText(FilledButton, 'Connect'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('the busy state is announced as "Please wait"', (t) async {
      final gate = Completer<AthenaStatus>();
      await pumpRow(t, _GatedAthena(gate));
      await t.tap(find.widgetWithText(FilledButton, 'Connect'));
      await t.pumpAndSettle();
      await t.tap(find.byType(Checkbox));
      await t.pump();
      await t.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Connect')));
      // The spinner never settles: let the dialog close, then look.
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.bySemanticsLabel('Please wait'), findsOneWidget);
      gate.complete(const AthenaStatus(connected: true));
      await t.pumpAndSettle();
    });

    testWidgets('Connect, consent and the dialog work from the keyboard',
        (t) async {
      final athena = _FakeAthena(_notConnected,
          connectResult: const AthenaStatus(connected: true));
      await pumpRow(t, athena);
      await _tabTo(t, find.widgetWithText(FilledButton, 'Connect'));
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      await _tabTo(t, find.byType(CheckboxListTile));
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      await _tabTo(
          t,
          find.descendant(
              of: find.byType(AlertDialog),
              matching: find.widgetWithText(FilledButton, 'Connect')));
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(athena.connects, 1);
    });
  });
}

class _GatedAthena extends AthenaConnectService {
  _GatedAthena(this.gate);
  final Completer<AthenaStatus> gate;

  @override
  Future<AthenaStatus?> status() async => _notConnected;

  @override
  Future<AthenaStatus> connect() => gate.future;
}
