// The patient's Medicare sharing screen (WBS 6.2.59, #323): one switch per
// linked caregiver, saved straight away, put back with an error on failure.
// Test Plan §3.30: TC-MCR-SHR-010…022 are the PR's; 030…041 are the Testing
// Lead's (038 and 039 run the app's route table, the real service and HTTP in
// process).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/config/router/app_router.dart';
import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/features/health/health_data/pages/medicare_connect_page.dart';
import 'package:care_connect_app/features/health/health_data/pages/medicare_sharing_page.dart';
import 'package:care_connect_app/features/health/health_data/services/medicare_connect_service.dart';
import 'package:care_connect_app/features/health/health_data/services/medicare_sharing_service.dart';
import 'package:care_connect_app/services/user_role_storage_service.dart';

import '../health_data_test_support.dart';

class _FakeSharing extends MedicareSharingService {
  _FakeSharing(
      {this.caregivers = const [], this.loadError, this.saveOk = true});

  List<SharingCaregiver> caregivers;
  MedicareSharingError? loadError;
  bool saveOk;
  Completer<void>? saveGate;
  Completer<void>? loadGate;
  int loads = 0;
  final List<(int, bool)> saves = [];

  @override
  Future<List<SharingCaregiver>> load() async {
    loads++;
    if (loadGate != null) await loadGate!.future;
    if (loadError != null) throw MedicareSharingException(loadError!);
    return caregivers;
  }

  @override
  Future<bool> setShared(int caregiverUserId, bool shared) async {
    saves.add((caregiverUserId, shared));
    if (saveGate != null) await saveGate!.future;
    return saveOk;
  }
}

class _FakeConnect extends MedicareConnectService {
  @override
  Future<MedicareStatus?> status() async =>
      const MedicareStatus(connected: true);
}

const _ann = SharingCaregiver(
    userId: 22, name: 'Ann Lee', email: 'ann@example.test', shared: true);
const _zoe = SharingCaregiver(userId: 21, name: 'Zoe Park', shared: false);

Future<_FakeSharing> _pump(WidgetTester t, _FakeSharing fake,
    {ThemeData? theme}) async {
  final previous = MedicareSharingService.instance;
  MedicareSharingService.instance = fake;
  addTearDown(() => MedicareSharingService.instance = previous);
  await t
      .pumpWidget(MaterialApp(theme: theme, home: const MedicareSharingPage()));
  await t.pumpAndSettle();
  return fake;
}

Finder _switchFor(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(SwitchListTile));

bool _value(WidgetTester t, String name) =>
    t.widget<SwitchListTile>(_switchFor(name)).value;

void main() {
  testWidgets(
      'TC-MCR-SHR-010: each linked caregiver has a switch, and the words '
      '"Sharing" / "Not sharing" show its state', (t) async {
    await _pump(t, _FakeSharing(caregivers: [_ann, _zoe]));

    expect(find.byType(SwitchListTile), findsNWidgets(2));
    expect(_value(t, 'Ann Lee'), isTrue);
    expect(_value(t, 'Zoe Park'), isFalse);
    expect(find.text('Sharing · ann@example.test'), findsOneWidget);
    expect(find.text('Not sharing'), findsOneWidget);
    expect(find.textContaining('coverage and visits'), findsOneWidget);
    expect(find.textContaining('turn sharing off at any time'), findsOneWidget);
  });

  testWidgets(
      'TC-MCR-SHR-011: turning a switch on saves it straight away and '
      'confirms who can now see the information', (t) async {
    final fake = await _pump(t, _FakeSharing(caregivers: [_ann, _zoe]));

    await t.tap(_switchFor('Zoe Park'));
    await t.pumpAndSettle();

    expect(fake.saves, [(21, true)]);
    expect(_value(t, 'Zoe Park'), isTrue);
    expect(find.text('Zoe Park can now see your Medicare coverage and visits.'),
        findsOneWidget);
  });

  testWidgets(
      'TC-MCR-SHR-012: turning a switch off saves it and confirms access ended',
      (t) async {
    final fake = await _pump(t, _FakeSharing(caregivers: [_ann]));

    await t.tap(_switchFor('Ann Lee'));
    await t.pumpAndSettle();

    expect(fake.saves, [(22, false)]);
    expect(_value(t, 'Ann Lee'), isFalse);
    expect(find.text('Ann Lee can no longer see your Medicare information.'),
        findsOneWidget);
  });

  testWidgets(
      'TC-MCR-SHR-013: when a save fails the switch goes back and an error '
      'shows the last confirmed state', (t) async {
    await _pump(t, _FakeSharing(caregivers: [_zoe], saveOk: false));

    await t.tap(_switchFor('Zoe Park'));
    await t.pumpAndSettle();

    expect(_value(t, 'Zoe Park'), isFalse);
    expect(
        find.text('Couldn\'t confirm sharing with Zoe Park. The switch shows '
            'the last confirmed state. Please try again.'),
        findsOneWidget);
  });

  testWidgets(
      'TC-MCR-SHR-014: a failed stop reports that the outcome is unconfirmed',
      (t) async {
    await _pump(t, _FakeSharing(caregivers: [_ann], saveOk: false));

    await t.tap(_switchFor('Ann Lee'));
    await t.pumpAndSettle();

    expect(_value(t, 'Ann Lee'), isTrue);
    expect(
        find.textContaining(
            'Couldn\'t confirm that sharing stopped for Ann Lee.'),
        findsOneWidget);
  });

  testWidgets(
      'TC-MCR-SHR-015: while a change saves, that switch is disabled and says '
      '"Saving…", so it can\'t be sent twice', (t) async {
    final fake = _FakeSharing(caregivers: [_zoe])..saveGate = Completer<void>();
    await _pump(t, fake);

    await t.tap(_switchFor('Zoe Park'));
    await t.pump();
    expect(t.widget<SwitchListTile>(_switchFor('Zoe Park')).onChanged, isNull);
    expect(find.text('Saving…'), findsOneWidget);

    await t.tap(_switchFor('Zoe Park'));
    await t.pump();
    expect(fake.saves, hasLength(1));

    fake.saveGate!.complete();
    await t.pumpAndSettle();
    expect(
        t.widget<SwitchListTile>(_switchFor('Zoe Park')).onChanged, isNotNull);
  });

  testWidgets(
      'TC-MCR-SHR-016: with no linked caregivers it explains what will '
      'appear here', (t) async {
    await _pump(t, _FakeSharing());
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.textContaining('You don\'t have any linked caregivers yet.'),
        findsOneWidget);
  });

  testWidgets(
      'TC-MCR-SHR-017: a load failure shows an error with Try again, '
      'which reloads', (t) async {
    final fake =
        await _pump(t, _FakeSharing(loadError: MedicareSharingError.network));
    expect(find.textContaining('Couldn\'t reach CareConnect.'), findsOneWidget);

    fake
      ..loadError = null
      ..caregivers = [_zoe];
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();

    expect(fake.loads, 2);
    expect(find.text('Zoe Park'), findsOneWidget);
  });

  testWidgets('TC-MCR-SHR-018: a non-patient sees why and gets no retry',
      (t) async {
    await _pump(t, _FakeSharing(loadError: MedicareSharingError.notPatient));
    expect(
        find.text('Only the patient can choose who sees their Medicare '
            'information.'),
        findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets(
      'TC-MCR-SHR-019: each switch is one focus stop that reads the '
      'caregiver\'s name and its on/off state, with a 48 dp target '
      '(WCAG 2.1 SC 4.1.2, 2.5.5)', (t) async {
    final handle = t.ensureSemantics();
    await _pump(t, _FakeSharing(caregivers: [_ann, _zoe]));

    expect(
      t.getSemantics(_switchFor('Ann Lee')),
      isSemantics(
        label: 'Ann Lee\nSharing · ann@example.test',
        hasToggledState: true,
        isToggled: true,
      ),
    );

    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('TC-MCR-SHR-020: a successful change is announced (live region)',
      (t) async {
    final handle = t.ensureSemantics();
    await _pump(t, _FakeSharing(caregivers: [_zoe]));
    await t.tap(_switchFor('Zoe Park'));
    await t.pumpAndSettle();

    final banner = find.ancestor(
        of: find.textContaining('can now see'),
        matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true));
    expect(banner, findsOneWidget);
    handle.dispose();
  });

  for (final theme in {
    'light': AppTheme.lightTheme,
    'dark': AppTheme.darkTheme,
  }.entries) {
    testWidgets(
        'TC-MCR-SHR-021: every text on the sharing screen has at least '
        '4.5:1 contrast in the ${theme.key} theme (WCAG 2.1 SC 1.4.3)',
        (t) async {
      await _pump(t, _FakeSharing(caregivers: [_ann, _zoe]),
          theme: theme.value);
      // Include a banner so its colours are checked too.
      await t.tap(_switchFor('Zoe Park'));
      await t.pumpAndSettle();
      final low = lowContrastText(t, find.byType(Scaffold)).toSet();
      expect(low, isEmpty, reason: low.join('\n'));
    });
  }

  testWidgets(
      'TC-MCR-SHR-022: Connect Medicare has a "Share with caregivers" button '
      'that opens the sharing screen', (t) async {
    final previousConnect = MedicareConnectService.instance;
    final previousSharing = MedicareSharingService.instance;
    MedicareConnectService.instance = _FakeConnect();
    MedicareSharingService.instance = _FakeSharing(caregivers: [_zoe]);
    addTearDown(() {
      MedicareConnectService.instance = previousConnect;
      MedicareSharingService.instance = previousSharing;
    });
    final router = GoRouter(initialLocation: '/medicare-connect', routes: [
      GoRoute(
          path: '/medicare-connect',
          builder: (_, __) => const MedicareConnectPage()),
      GoRoute(
          path: '/medicare-sharing',
          builder: (_, __) => const MedicareSharingPage()),
    ]);
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.pumpAndSettle();

    await t.tap(find.text('Share with caregivers'));
    await t.pumpAndSettle();

    expect(find.text('Share Medicare'), findsOneWidget);
    expect(find.text('Zoe Park'), findsOneWidget);
  });

  // ---- Testing Lead (Test Plan §3.30) ----

  testWidgets(
      'TC-MCR-SHR-030: while the list loads, a labelled progress indicator '
      'shows and no switch is offered', (t) async {
    final handle = t.ensureSemantics();
    final fake = _FakeSharing(caregivers: [_zoe])..loadGate = Completer<void>();
    MedicareSharingService.instance = fake;
    addTearDown(() => MedicareSharingService.instance = MedicareSharingService());
    await t.pumpWidget(const MaterialApp(home: MedicareSharingPage()));
    await t.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('Loading your caregivers'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);

    fake.loadGate!.complete();
    await t.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(SwitchListTile), findsOneWidget);
    handle.dispose();
  });

  testWidgets(
      'TC-MCR-SHR-031: an expired sign-in says to sign in again with no retry; '
      'a server failure says the list could not load and offers Try again',
      (t) async {
    await _pump(t, _FakeSharing(loadError: MedicareSharingError.signedOut));
    expect(find.text('Your sign-in has expired. Please sign in again.'),
        findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);

    await t.pumpWidget(const SizedBox());
    await _pump(t, _FakeSharing(loadError: MedicareSharingError.server));
    expect(find.text('Couldn\'t load your caregivers. Please try again.'),
        findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets(
      'TC-MCR-SHR-032: Back returns to Connect Medicare: it pops when the '
      'screen was pushed, and goes there when opened directly', (t) async {
    MedicareConnectService.instance = _FakeConnect();
    MedicareSharingService.instance = _FakeSharing(caregivers: [_zoe]);
    addTearDown(() {
      MedicareConnectService.instance = MedicareConnectService();
      MedicareSharingService.instance = MedicareSharingService();
    });
    for (final start in ['/medicare-connect', '/medicare-sharing']) {
      final router = GoRouter(initialLocation: start, routes: [
        GoRoute(
            path: '/medicare-connect',
            builder: (_, __) => const MedicareConnectPage()),
        GoRoute(
            path: '/medicare-sharing',
            builder: (_, __) => const MedicareSharingPage()),
      ]);
      await t.pumpWidget(MaterialApp.router(
          key: ValueKey(start), routerConfig: router));
      await t.pumpAndSettle();
      if (start == '/medicare-connect') {
        await t.tap(find.text('Share with caregivers'));
        await t.pumpAndSettle();
      }
      expect(find.text('Share Medicare'), findsOneWidget, reason: start);

      await t.tap(find.byTooltip('Back to Connect Medicare'));
      await t.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path,
          '/medicare-connect',
          reason: start);
      expect(find.text('Share with caregivers'), findsOneWidget, reason: start);
    }
  });

  testWidgets(
      'TC-MCR-SHR-033: while one caregiver\'s change saves, another '
      'caregiver\'s switch still works and saves on its own; a new change '
      'clears the previous confirmation', (t) async {
    final fake = _FakeSharing(caregivers: [_ann, _zoe]);
    await _pump(t, fake);
    await t.tap(_switchFor('Ann Lee'));
    await t.pumpAndSettle();
    expect(find.textContaining('can no longer see'), findsOneWidget);

    fake.saveGate = Completer<void>();
    await t.tap(_switchFor('Zoe Park'));
    await t.pump();
    expect(find.textContaining('can no longer see'), findsNothing);
    expect(t.widget<SwitchListTile>(_switchFor('Zoe Park')).onChanged, isNull);
    expect(t.widget<SwitchListTile>(_switchFor('Ann Lee')).onChanged, isNotNull);

    await t.tap(_switchFor('Ann Lee'));
    await t.pump();
    expect(fake.saves, [(22, false), (21, true), (22, true)]);
    expect(find.textContaining('Saving…'), findsNWidgets(2));

    fake.saveGate!.complete();
    await t.pumpAndSettle();
    expect(_value(t, 'Ann Lee'), isTrue);
    expect(_value(t, 'Zoe Park'), isTrue);
    expect(find.text('Saving…'), findsNothing);
  });

  testWidgets(
      'TC-MCR-SHR-034: leaving the screen while a change is still saving '
      'raises no error when the save finishes', (t) async {
    final fake = _FakeSharing(caregivers: [_zoe], saveOk: false)
      ..saveGate = Completer<void>();
    await _pump(t, fake);
    await t.tap(_switchFor('Zoe Park'));
    await t.pump();

    await t.pumpWidget(const MaterialApp(home: Text('elsewhere')));
    fake.saveGate!.complete();
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(fake.saves, [(21, true)]);
  });

  testWidgets(
      'TC-MCR-SHR-035: a load failure and a failed save are each announced '
      'through a live region', (t) async {
    final handle = t.ensureSemantics();
    bool live(Finder text) => find
        .ancestor(
            of: text,
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.liveRegion == true))
        .evaluate()
        .isNotEmpty;

    await _pump(t, _FakeSharing(loadError: MedicareSharingError.network));
    expect(live(find.textContaining('Couldn\'t reach CareConnect.')), isTrue);

    await t.pumpWidget(const SizedBox());
    await _pump(t, _FakeSharing(caregivers: [_zoe], saveOk: false));
    await t.tap(_switchFor('Zoe Park'));
    await t.pumpAndSettle();
    expect(live(find.textContaining('Couldn\'t confirm sharing')), isTrue);
    handle.dispose();
  });

  testWidgets(
      'TC-MCR-SHR-036: at 200% text on a 320 x 640 phone the list, both '
      'banners, the empty state and the error states lay out with no text cut '
      'off, top and bottom '
      '(WCAG 2.1 SC 1.4.4, 1.4.10)', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final problems = <String>[];

    Future<void> check(String state, _FakeSharing fake,
        {String? tap}) async {
      MedicareSharingService.instance = fake;
      await t.pumpWidget(MaterialApp(
        key: UniqueKey(),
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const MedicareSharingPage(),
      ));
      await t.pumpAndSettle();
      if (tap != null) {
        // The test font is wide: at 200% the intro alone fills the screen.
        await t.scrollUntilVisible(find.text(tap), 200,
            scrollable: find.byType(Scrollable).first);
        await t.ensureVisible(_switchFor(tap));
        await t.pumpAndSettle();
        await t.tap(_switchFor(tap));
        await t.pumpAndSettle();
        // A missed tap would leave no banner to measure.
        expect(fake.saves, hasLength(1), reason: state);
        expect(
            find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.liveRegion == true),
            findsOneWidget,
            reason: state);
        await t.drag(find.byType(ListView), const Offset(0, 4000));
        await t.pumpAndSettle();
      }
      void measure(String where) {
        final e = t.takeException();
        if (e != null) problems.add('$state ($where): $e');
        // A paragraph squeezed into a box shorter than its text is cut off
        // with no layout error, so compare each one's needed height with its
        // size.
        for (final el in find.byType(RichText).evaluate()) {
          final para = el.renderObject! as RenderParagraph;
          final needed = para.getMaxIntrinsicHeight(para.size.width);
          if (needed > para.size.height + 0.5) {
            problems.add('$state ($where): "${para.text.toPlainText()}" needs '
                '${needed.toStringAsFixed(0)} px, has '
                '${para.size.height.toStringAsFixed(0)} px');
          }
        }
      }

      measure('top');
      // The list is lazy: rows below the fold exist only once scrolled to.
      await t.drag(find.byType(ListView), const Offset(0, -2000));
      await t.pumpAndSettle();
      measure('bottom');
    }

    addTearDown(() => MedicareSharingService.instance = MedicareSharingService());
    await check('list', _FakeSharing(caregivers: [_ann, _zoe]));
    await check('banner', _FakeSharing(caregivers: [_zoe]), tap: 'Zoe Park');
    await check('error banner', _FakeSharing(caregivers: [_ann], saveOk: false),
        tap: 'Ann Lee');
    await check('empty', _FakeSharing());
    await check(
        'error', _FakeSharing(loadError: MedicareSharingError.network));
    await check('not a patient',
        _FakeSharing(loadError: MedicareSharingError.notPatient));
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  for (final theme in {
    'light': AppTheme.lightTheme,
    'dark': AppTheme.darkTheme,
  }.entries) {
    testWidgets(
        'TC-MCR-SHR-037: Connect Medicare\'s "Share with caregivers" button '
        'is at least 48 dp tall, labelled, and its text is at least 4.5:1 in '
        'the ${theme.key} theme (WCAG 2.1 SC 1.4.3, 2.5.5)', (t) async {
      final handle = t.ensureSemantics();
      MedicareConnectService.instance = _FakeConnect();
      addTearDown(() => MedicareConnectService.instance = MedicareConnectService());
      await t.pumpWidget(
          MaterialApp(theme: theme.value, home: const MedicareConnectPage()));
      await t.pumpAndSettle();

      final button = find.ancestor(
          of: find.text('Share with caregivers'),
          matching: find.byType(OutlinedButton));
      expect(t.getSize(button).height, greaterThanOrEqualTo(48));
      final low = lowContrastText(t, button).toSet();
      expect(low, isEmpty, reason: low.join('\n'));
      expect(
          t.getSemantics(button),
          isSemantics(
              label: 'Share with caregivers',
              isButton: true,
              hasTapAction: true));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  }

  group('in process, with the stored sign-in', () {
    const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final store = <String, String>{};
    final sent = <http.Request>[];
    const jwt = 'eyJhbGciOiJIUzI1NiJ9.synthetic.signature';

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      sent.clear();
      store
        ..clear()
        ..['jwt_token'] = jwt
        ..['token_expiry'] = '4102444800';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secure, (call) async {
        final args = (call.arguments as Map?) ?? const {};
        final key = args['key'] as String?;
        switch (call.method) {
          case 'read':
            return store[key];
          case 'write':
            store[key!] = args['value'] as String;
            return null;
          case 'delete':
            store.remove(key);
            return null;
          case 'readAll':
            return Map<String, String>.of(store);
          case 'containsKey':
            return store.containsKey(key);
        }
        return null;
      });
      MedicareSharingService.instance = MedicareSharingService();
    });
    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secure, null);
      await UserRoleStorageService.instance.clearUserData();
    });

    Future<void> signIn(int id, String role) async {
      store['user_session'] =
          jsonEncode({'id': id, 'email': 'u$id@example.test', 'role': role});
      await UserRoleStorageService.instance.setUserData(role: role, userId: id);
    }

    Future<GoRouter> open(WidgetTester t) async {
      final router = GoRouter(
          initialLocation: '/medicare-sharing',
          routes: appRouter.configuration.routes);
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      for (var i = 0; i < 20; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump(const Duration(milliseconds: 50));
      }
      return router;
    }

    List<String> calls() => [
          for (final r in sent)
            if (!r.url.path.contains('telemetry'))
              '${r.method} ${r.url.path}'
        ];

    testWidgets(
        'TC-MCR-SHR-038: a signed-in patient opens /medicare-sharing through '
        'the app\'s route table; the list, each consent check and a change '
        'all carry the stored sign-in, and the switch shows what was saved',
        (t) async {
      await signIn(41, 'PATIENT');
      var granted = false;
      await http.runWithClient(() async {
        final router = await open(t);
        expect(router.routerDelegate.currentConfiguration.uri.path,
            '/medicare-sharing');
        expect(find.text('Zoe Park'), findsOneWidget);
        expect(_value(t, 'Zoe Park'), isFalse);

        await t.tap(_switchFor('Zoe Park'));
        for (var i = 0; i < 10; i++) {
          await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(_value(t, 'Zoe Park'), isTrue);
        expect(find.text('Zoe Park can now see your Medicare coverage and '
            'visits.'), findsOneWidget);
      }, () => MockClient((req) async {
            sent.add(req);
            if (req.url.path
                .endsWith('/caregiver-patient-links/patients/41/caregivers')) {
              return http.Response(
                  jsonEncode([
                    {
                      'id': 5,
                      'caregiverUserId': 21,
                      'caregiverName': 'Zoe Park',
                      'caregiverEmail': 'zoe@example.test',
                      'patientUserId': 41,
                      'status': 'ACTIVE',
                      'linkType': 'PERMANENT',
                    }
                  ]),
                  200);
            }
            if (req.url.path.endsWith('/v3/consent/medicare-view')) {
              if (req.method == 'POST') {
                granted = true;
                return http.Response('{"status":"ACTIVE"}', 201);
              }
              return http.Response(
                  jsonEncode({
                    'patientUserId': 41,
                    'granteeUserId': 21,
                    'granted': granted,
                    'explicitGrant': granted,
                    'effectiveConsent': granted,
                  }),
                  200);
            }
            return http.Response('{}', 404);
          }));

      expect(calls(), [
        'GET /v1/api/caregiver-patient-links/patients/41/caregivers',
        'GET /v1/api/v3/consent/medicare-view',
        'POST /v1/api/v3/consent/medicare-view',
      ]);
      for (final r in sent.where((r) => !r.url.path.contains('telemetry'))) {
        expect(r.headers['Authorization'], 'Bearer $jwt', reason: r.url.path);
      }
      expect(jsonDecode(sent.last.body),
          {'granteeUserId': 21, 'granteeRole': 'CAREGIVER'});
    });

    // DEF-MCR-31 at the screen: before the fix the caregiver's own id was sent
    // to the links endpoint, which answers 200 [], and the page said "You
    // don't have any linked caregivers yet".
    testWidgets(
        'TC-MCR-SHR-039: a signed-in caregiver who opens /medicare-sharing is '
        'told only the patient can choose, with no switch, no retry and no '
        'request', (t) async {
      await signIn(52, 'CAREGIVER');
      await http.runWithClient(() async {
        await open(t);
        expect(
            find.text('Only the patient can choose who sees their Medicare '
                'information.'),
            findsOneWidget);
        expect(find.textContaining('You don\'t have any linked caregivers'),
            findsNothing);
        expect(find.byType(SwitchListTile), findsNothing);
        expect(find.text('Try again'), findsNothing);
      }, () => MockClient((req) async {
            sent.add(req);
            return http.Response('[]', 200);
          }));
      expect(calls(), isEmpty);
    });
  });

  for (final theme in {
    'light': AppTheme.lightTheme,
    'dark': AppTheme.darkTheme,
  }.entries) {
    testWidgets(
        'TC-MCR-SHR-040: "Not sharing", "Saving…", the error banner and the '
        'load error are each at least 4.5:1 in the ${theme.key} theme (WCAG '
        '2.1 SC 1.4.3)', (t) async {
      final failures = <String>[];
      void scan(String state) => failures.addAll(
          lowContrastText(t, find.byType(Scaffold)).map((f) => '$state: $f'));

      await _pump(t, _FakeSharing(caregivers: [_zoe]), theme: theme.value);
      expect(find.text('Not sharing'), findsOneWidget);
      scan('not sharing');

      await t.pumpWidget(const SizedBox());
      final fake = _FakeSharing(caregivers: [_zoe])..saveGate = Completer<void>();
      await _pump(t, fake, theme: theme.value);
      await t.tap(_switchFor('Zoe Park'));
      await t.pump();
      expect(find.text('Saving…'), findsOneWidget);
      scan('saving');
      fake
        ..saveOk = false
        ..saveGate!.complete();
      await t.pumpAndSettle();
      expect(find.textContaining('Couldn\'t confirm'), findsOneWidget);
      scan('error banner');

      await t.pumpWidget(const SizedBox());
      await _pump(t, _FakeSharing(loadError: MedicareSharingError.server),
          theme: theme.value);
      scan('load error');
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  }

  // DEF-MCR-32: the row is disabled while it saves, which takes keyboard focus
  // away; before the fix it never came back, so the next Tab started at Back.
  testWidgets(
      'TC-MCR-SHR-041: after a change made from the keyboard, focus is back on '
      'that caregiver\'s switch, and Space changes it again', (t) async {
    final fake = _FakeSharing(caregivers: [_ann, _zoe]);
    await _pump(t, fake);

    bool focusedOn(String name) {
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx == null) return false;
      final target = _switchFor(name).evaluate().single;
      var inside = identical(ctx, target);
      ctx.visitAncestorElements((a) {
        if (identical(a, target)) inside = true;
        return !inside;
      });
      return inside;
    }

    for (var i = 0; i < 10 && !focusedOn('Zoe Park'); i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
    }
    expect(focusedOn('Zoe Park'), isTrue, reason: 'Tab reaches the row');

    for (final (ok, expected) in [(true, true), (false, true), (true, false)]) {
      fake
        ..saveOk = ok
        ..saveGate = Completer<void>();
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      expect(find.textContaining('Saving…'), findsOneWidget);
      fake.saveGate!.complete();
      await t.pumpAndSettle();
      expect(_value(t, 'Zoe Park'), expected, reason: 'save ok=$ok');
      expect(focusedOn('Zoe Park'), isTrue, reason: 'focus after save ok=$ok');
    }
    expect(fake.saves, [(21, true), (21, false), (21, false)]);
  });
}
