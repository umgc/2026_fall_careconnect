// CC-12 Increment 2: the public scan page (design screens 3 and 4) and its
// route. Test Plan §3.26: TC-EMG-214…222 (the pull request's), 237…250
// (Testing Lead: states, the app's own router, accessibility).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/config/router/app_router.dart';
import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/features/emergency_passport/models/public_passport.dart';
import 'package:care_connect_app/features/emergency_passport/pages/passport_scan_page.dart';
import 'package:care_connect_app/features/emergency_passport/services/passport_scan_service.dart';
import 'package:care_connect_app/services/user_role_storage_service.dart';

import '../passport_test_support.dart';

class _FakeScan extends PassportScanService {
  _FakeScan(this.results);
  final List<ScanResult> results;
  int calls = 0;

  @override
  Future<ScanResult> scan(String token) async {
    final r = results[calls < results.length ? calls : results.length - 1];
    calls++;
    return r;
  }
}

/// Answers only when the test completes the code's [Completer].
class _HeldScan extends PassportScanService {
  final pending = <String, Completer<ScanResult>>{};
  final asked = <String>[];

  @override
  Future<ScanResult> scan(String token) {
    asked.add(token);
    return (pending[token] = Completer<ScanResult>()).future;
  }
}

final _full = ScanShown(PublicPassport.fromJson(fullPassport));
const _nameOnly =
    ScanShown(PublicPassport(name: 'Jordan Miller', age: 41));

Future<List<Uri>> _open(WidgetTester t, PassportScanService service,
    {ThemeData? theme,
    Future<bool> Function(Uri uri)? launcher,
    bool settle = true}) async {
  final launched = <Uri>[];
  await t.binding.setSurfaceSize(const Size(420, 2400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(
    theme: theme,
    // A new key each time: the same page type re-pumped in one test would
    // otherwise keep its State, and with it the first service and result.
    home: PassportScanPage(
      key: UniqueKey(),
      token: 'abc123',
      service: service,
      launcher: launcher ??
          (uri) async {
            launched.add(uri);
            return true;
          },
    ),
  ));
  if (settle) await t.pumpAndSettle();
  return launched;
}

Color? _headerColor(WidgetTester t) => t
    .widget<Container>(find
        .ancestor(
            of: find.text('EMERGENCY MEDICAL INFORMATION'),
            matching: find.byType(Container))
        .first)
    .color;

/// Every state the page can show, as one result list each.
final _states = <String, List<ScanResult>>{
  'screen 3': [_full],
  'nothing shared': [_nameOnly],
  'screen 4': [const ScanNotActive()],
  'too many tries': [const ScanRateLimited()],
  "couldn't load": [const ScanFailed()],
};

const _secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  testWidgets('TC-EMG-214: screen 3: an active code shows only what was shared',
      (t) async {
    final launched = await _open(t, _FakeScan([_full]));

    expect(find.text('EMERGENCY MEDICAL INFORMATION'), findsOneWidget);
    expect(find.text('Jordan Miller'), findsOneWidget);
    expect(find.text('Age 41'), findsOneWidget);
    expect(find.text('O+'), findsOneWidget);
    expect(find.bySemanticsLabel('Blood type O positive'), findsOneWidget);
    expect(find.text('ALLERGIES'), findsOneWidget);
    expect(find.text('Penicillin'), findsOneWidget);
    expect(find.text('Life-threatening'), findsOneWidget);
    expect(find.text('Moderate'), findsOneWidget);
    expect(find.text('Latex'), findsOneWidget);
    expect(find.text('Lisinopril 10 mg'), findsOneWidget);
    expect(find.text('Once daily'), findsOneWidget);
    expect(find.text('Type 2 diabetes'), findsOneWidget);
    expect(find.text('Taylor Miller'), findsOneWidget);
    expect(find.text('Last updated Oct 13, 2026'), findsOneWidget);
    expect(find.text('Call 911'), findsNothing);
    expect(find.text('No information shared'), findsNothing);

    await t.tap(find.text('Call (415) 555-0184'));
    expect(launched, [Uri(scheme: 'tel', path: '4155550184')]);
  });

  testWidgets('TC-EMG-215: screen 3: hidden sections are not shown', (t) async {
    await _open(
        t,
        _FakeScan([
          ScanShown(PublicPassport.fromJson(
              {'name': 'Jordan Miller', 'age': 41, 'bloodType': 'A_NEGATIVE'}))
        ]));
    expect(find.text('A−'), findsOneWidget);
    expect(find.text('ALLERGIES'), findsNothing);
    expect(find.text('CURRENT MEDICATIONS'), findsNothing);
    expect(find.text('CHRONIC CONDITIONS'), findsNothing);
    expect(find.text('EMERGENCY CONTACT'), findsNothing);
  });

  testWidgets(
      'TC-EMG-216: nothing shared: name and age, "No information shared", Call 911',
      (t) async {
    final launched = await _open(t, _FakeScan([_nameOnly]));
    expect(find.text('Jordan Miller'), findsOneWidget);
    expect(find.text('No information shared'), findsOneWidget);
    expect(find.textContaining('Last updated'), findsNothing);
    await t.tap(find.text('Call 911'));
    expect(launched, [Uri(scheme: 'tel', path: '911')]);
  });

  testWidgets('TC-EMG-217: screen 4: a code that is not active shows no information',
      (t) async {
    final launched = await _open(t, _FakeScan([const ScanNotActive()]));
    expect(find.text('This code isn\'t active'), findsOneWidget);
    expect(find.text('Jordan Miller'), findsNothing);
    await t.tap(find.text('Call 911'));
    expect(launched, [Uri(scheme: 'tel', path: '911')]);
  });

  testWidgets('TC-EMG-218: too many tries: Try again loads once more', (t) async {
    final service = _FakeScan([const ScanRateLimited(), _full]);
    await _open(t, service);
    expect(find.text('Too many tries'), findsOneWidget);
    expect(find.text('Call 911'), findsOneWidget);
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(service.calls, 2);
    expect(find.text('Jordan Miller'), findsOneWidget);
  });

  testWidgets('TC-EMG-219: no answer: a message, Try again and Call 911', (t) async {
    await _open(t, _FakeScan([const ScanFailed()]));
    expect(find.text('We couldn\'t load this information'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Call 911'), findsOneWidget);
  });

  testWidgets('TC-EMG-220: the page loads once and never refreshes by itself',
      (t) async {
    final service = _FakeScan([_full]);
    await _open(t, service);
    await t.pump(const Duration(minutes: 2));
    expect(service.calls, 1);
  });

  testWidgets('TC-EMG-221: opening a new code on the same page loads that code',
      (t) async {
    final service = _FakeScan([const ScanNotActive(), _full]);
    await t.pumpWidget(MaterialApp(
        home: PassportScanPage(token: 'old', service: service)));
    await t.pumpAndSettle();
    expect(find.text('This code isn\'t active'), findsOneWidget);

    await t.pumpWidget(MaterialApp(
        home: PassportScanPage(token: 'new', service: service)));
    await t.pumpAndSettle();
    expect(service.calls, 2);
    expect(find.text('Jordan Miller'), findsOneWidget);
    expect(find.text('This code isn\'t active'), findsNothing);
  });

  group('route', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secure, (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secure, null);
    });

    testWidgets('TC-EMG-222: /passport/:token opens the scan page without signing in',
        (t) async {
      await UserRoleStorageService.instance.clearUserData();
      final router = GoRouter(
        initialLocation: '/passport/abc123',
        routes: appRouter.configuration.routes,
      );
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      for (var i = 0; i < 20; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(router.routerDelegate.currentConfiguration.uri.path,
          '/passport/abc123');
      final page = t.widget<PassportScanPage>(find.byType(PassportScanPage));
      expect(page.token, 'abc123');
    });
  });

  // ---------- Testing Lead: states the pull request's tests skip ----------

  testWidgets(
      'TC-EMG-237: while the scan is loading: a spinner announced as "Loading '
      'emergency information", the neutral (not red) header, and no '
      'information or buttons yet', (t) async {
    final handle = t.ensureSemantics();
    final service = _HeldScan();
    await _open(t, service, settle: false);
    await t.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
        t.getSemantics(find.bySemanticsLabel('Loading emergency information')),
        isSemantics(label: 'Loading emergency information', isLiveRegion: true));
    expect(_headerColor(t), const Color(0xFF1F2937));
    expect(find.text('Jordan Miller'), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.text('Try again'), findsNothing);

    service.pending['abc123']!.complete(_full);
    await t.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_headerColor(t), const Color(0xFFB91C1C));
    handle.dispose();
  });

  testWidgets(
      'TC-EMG-238: "couldn\'t load", then Try again: the page shows loading '
      'again and then the shared information', (t) async {
    final service = _HeldScan();
    await _open(t, service, settle: false);
    service.pending['abc123']!.complete(const ScanFailed());
    await t.pumpAndSettle();
    expect(find.text('We couldn\'t load this information'), findsOneWidget);

    await t.tap(find.text('Try again'));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(service.asked, ['abc123', 'abc123']);

    service.pending['abc123']!.complete(_full);
    await t.pumpAndSettle();
    expect(find.text('Jordan Miller'), findsOneWidget);
    expect(find.text('We couldn\'t load this information'), findsNothing);
  });

  testWidgets(
      'TC-EMG-239: when the code changes while the old one is still loading, '
      'the old code\'s late answer is ignored and the new code\'s is shown',
      (t) async {
    final service = _HeldScan();
    await t.pumpWidget(MaterialApp(
        home: PassportScanPage(token: 'old', service: service)));
    await t.pumpWidget(MaterialApp(
        home: PassportScanPage(token: 'new', service: service)));
    expect(service.asked, ['old', 'new']);

    service.pending['new']!.complete(const ScanNotActive());
    await t.pumpAndSettle();
    expect(find.text('This code isn\'t active'), findsOneWidget);

    service.pending['old']!.complete(_full);
    await t.pumpAndSettle();
    expect(find.text('Jordan Miller'), findsNothing);
    expect(find.text('This code isn\'t active'), findsOneWidget);
  });

  testWidgets(
      'TC-EMG-240: an emergency contact with no phone has no Call button; one '
      'with a phone but no name is announced as "Call emergency contact at …"',
      (t) async {
    final handle = t.ensureSemantics();
    await _open(
        t,
        _FakeScan([
          ScanShown(PublicPassport.fromJson({
            'name': 'Jordan Miller',
            'emergencyContact': {'name': 'Taylor Miller', 'relationship': 'Spouse'},
          }))
        ]));
    expect(find.text('EMERGENCY CONTACT'), findsOneWidget);
    expect(find.text('Taylor Miller'), findsOneWidget);
    expect(find.text('Spouse'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);

    await _open(
        t,
        _FakeScan([
          ScanShown(PublicPassport.fromJson({
            'name': 'Jordan Miller',
            'emergencyContact': {'phone': '415-555-0100'},
          }))
        ]));
    expect(find.bySemanticsLabel('Call emergency contact at 415-555-0100'),
        findsOneWidget);
    handle.dispose();
  });

  testWidgets(
      'TC-EMG-241: a contact phone with no digits starts no call, and a phone '
      'app that fails to open (a desktop browser) leaves the page on screen',
      (t) async {
    var launches = 0;
    await _open(
        t,
        _FakeScan([
          ScanShown(PublicPassport.fromJson({
            'name': 'Jordan Miller',
            'emergencyContact': {'name': 'Taylor Miller', 'phone': 'ask the desk'},
          }))
        ]),
        launcher: (_) async {
          launches++;
          return true;
        });
    await t.tap(find.text('Call ask the desk'));
    await t.pump();
    expect(launches, 0);

    await _open(t, _FakeScan([const ScanNotActive()]),
        launcher: (_) async => throw PlatformException(code: 'no_phone_app'));
    await t.tap(find.text('Call 911'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('This code isn\'t active'), findsOneWidget);
  });

  testWidgets(
      'TC-EMG-252: with no test launcher (as in the app), Call 911 asks the '
      'phone to open tel:911', (t) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final opened = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') {
        opened.add((call.arguments as Map)['url'] as String);
      }
      return true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await t.pumpWidget(MaterialApp(
        home: PassportScanPage(
            token: 'abc123', service: _FakeScan([const ScanNotActive()]))));
    await t.pumpAndSettle();
    await t.tap(find.text('Call 911'));
    await t.pumpAndSettle();
    expect(opened, ['tel:911']);
  });

  testWidgets(
      'TC-EMG-253: a passport that shares only one section (blood type alone, '
      'or a contact alone) is screen 3, never "No information shared"',
      (t) async {
    for (final shared in <Map<String, Object>>[
      {'bloodType': 'B_POSITIVE'},
      {'chronicConditions': 'Asthma'},
      {'emergencyContact': {'name': 'Taylor Miller'}},
      {'allergies': [{'allergen': 'Latex'}]},
      {'medications': [{'name': 'Metformin'}]},
    ]) {
      final p = PublicPassport.fromJson({'name': 'Jordan Miller', ...shared});
      expect(p.sharesNothing, isFalse, reason: '$shared');
      await _open(t, _FakeScan([ScanShown(p)]));
      expect(find.text('No information shared'), findsNothing, reason: '$shared');
      expect(find.text('Call 911'), findsNothing, reason: '$shared');
    }
  });

  testWidgets(
      'TC-EMG-242: optional details are left out cleanly: a medication with '
      'no dosage or frequency shows its name only, an allergy with no '
      'severity has no badge, and a reaction reads "Reaction: …"', (t) async {
    await _open(
        t,
        _FakeScan([
          ScanShown(PublicPassport.fromJson({
            'name': 'Jordan Miller',
            'allergies': [
              {'allergen': 'Penicillin', 'severity': null, 'reaction': 'Anaphylaxis'},
            ],
            'medications': [
              {'name': 'Metformin'},
            ],
          }))
        ]));
    expect(find.text('Metformin'), findsOneWidget);
    expect(find.text('Reaction: Anaphylaxis'), findsOneWidget);
    for (final badge in ['Mild', 'Moderate', 'Severe', 'Life-threatening']) {
      expect(find.text(badge), findsNothing);
    }
  });

  testWidgets(
      'TC-EMG-243: the red emergency header is shown only with shared '
      'information; nothing shared, screen 4 and the problem states keep the '
      'neutral header', (t) async {
    final expected = {
      'screen 3': const Color(0xFFB91C1C),
      'nothing shared': const Color(0xFFB91C1C),
      'screen 4': const Color(0xFF1F2937),
      'too many tries': const Color(0xFF1F2937),
      "couldn't load": const Color(0xFF1F2937),
    };
    for (final e in _states.entries) {
      await _open(t, _FakeScan(e.value));
      expect(_headerColor(t), expected[e.key], reason: e.key);
    }
  });

  // ---------- Testing Lead: the app's own router, end to end in process ----------

  group('the app router, the real service and HTTP', () {
    late List<http.Request> sent;

    setUp(() {
      sent = [];
      SharedPreferences.setMockInitialValues({'telemetry_opted_out': true});
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secure, null);
    });

    Future<void> openThroughAppRouter(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await http.runWithClient(() async {
        appRouter.go('/passport/abc123');
        await t.pumpWidget(MaterialApp.router(routerConfig: appRouter));
        for (var i = 0; i < 20; i++) {
          await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await t.pump(const Duration(milliseconds: 50));
        }
      }, () => MockClient((req) async {
            sent.add(req);
            if (req.url.path.startsWith('/v1/api/passport/scan/')) {
              return http.Response(jsonEncode(fullPassport), 200,
                  headers: {'content-type': 'application/json'});
            }
            return http.Response('{}', 404);
          }));
    }

    testWidgets(
        'TC-EMG-244: signed out, the app\'s own router opens /passport/abc123 '
        'on the scan page, and the page shows what the real service read from '
        'the scan response', (t) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secure, (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      });
      await openThroughAppRouter(t);

      expect(appRouter.state.uri.path, '/passport/abc123');
      expect(find.byType(PassportScanPage), findsOneWidget);
      expect(find.text('Jordan Miller'), findsOneWidget);
      expect(find.text('Lisinopril 10 mg'), findsOneWidget);
      expect(
          sent.where((r) => r.url.path == '/v1/api/passport/scan/abc123'),
          hasLength(1));
      appRouter.go('/');
    });

    testWidgets(
        'TC-EMG-245: signed in on the same phone, the link still opens the '
        'scan page (no redirect), and the scan request carries none of the '
        'stored credentials', (t) async {
      const jwt = 'eyJhbGciOiJIUzI1NiJ9.synthetic.signature';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secure, (call) async {
        final args = (call.arguments as Map?) ?? const {};
        switch (call.method) {
          case 'readAll':
            return <String, String>{'jwt_token': jwt, 'auth_token': jwt};
          case 'containsKey':
            return true;
          case 'read':
            return args['key'] == 'jwt_token' || args['key'] == 'auth_token'
                ? jwt
                : null;
        }
        return null;
      });
      await t.runAsync(() => UserRoleStorageService.instance
          .setUserData(role: 'PATIENT', userId: 7, patientId: 7));
      expect(await t.runAsync(UserRoleStorageService.instance.isLoggedIn),
          isTrue);
      addTearDown(() => t.runAsync(UserRoleStorageService.instance.clearUserData));
      await openThroughAppRouter(t);

      expect(appRouter.state.uri.path, '/passport/abc123');
      expect(find.text('Jordan Miller'), findsOneWidget);
      final scan = sent.singleWhere(
          (r) => r.url.path == '/v1/api/passport/scan/abc123');
      final headers = scan.headers.map((k, v) => MapEntry(k.toLowerCase(), v));
      expect(headers.containsKey('authorization'), isFalse);
      expect(headers.containsKey('cookie'), isFalse);
      expect(headers.values.any((v) => v.contains(jwt)), isFalse);
      appRouter.go('/');
    });
  });

  // ---------- Testing Lead: accessibility (WCAG 2.1 AA) ----------

  for (final theme in {
    'light': AppTheme.lightTheme,
    'dark': AppTheme.darkTheme,
  }.entries) {
    testWidgets(
        'TC-EMG-246: every text on every state is at least 4.5:1 against what '
        'is behind it (SC 1.4.3), app ${theme.key} theme', (t) async {
      final failures = <String>[];
      for (final s in _states.entries) {
        await _open(t, _FakeScan(s.value), theme: theme.value);
        failures.addAll(lowContrastText(t).map((f) => '${s.key}: $f'));
      }
      expect(failures, isEmpty);
    });
  }

  testWidgets(
      'TC-EMG-247: at 200% text on a 320 x 640 phone every state lays out '
      'without clipping or overflow (SC 1.4.4, 1.4.10)', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final problems = <String>[];
    for (final s in _states.entries) {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: PassportScanPage(
            key: UniqueKey(), token: 'abc123', service: _FakeScan(s.value)),
      ));
      await t.pumpAndSettle();
      final e = t.takeException();
      if (e != null) problems.add('${s.key}: $e');
      // A label taller than its button is painted outside it (cut off on
      // screen) without any layout error, so measure it.
      for (final button in find.byWidgetPredicate((w) => w is ButtonStyleButton)
          .evaluate()) {
        final box = button.renderObject! as RenderBox;
        for (final text in find
            .descendant(
                of: find.byWidget(button.widget), matching: find.byType(Text))
            .evaluate()) {
          final label = (text.widget as Text).data;
          final textBox = text.renderObject! as RenderBox;
          final top = textBox.localToGlobal(Offset.zero).dy -
              box.localToGlobal(Offset.zero).dy;
          if (top < 0 || top + textBox.size.height > box.size.height) {
            problems.add('${s.key}: "$label" is '
                '${textBox.size.height.toStringAsFixed(0)} px tall in a '
                '${box.size.height.toStringAsFixed(0)} px button');
          }
        }
      }
    }
    expect(problems, isEmpty);
  });

  testWidgets(
      'TC-EMG-248: the page header and every section title are headings, and '
      'the title of screen 4 and of each problem state is a live region',
      (t) async {
    final handle = t.ensureSemantics();
    await _open(t, _FakeScan([_full]));
    for (final title in [
      'EMERGENCY MEDICAL INFORMATION',
      'ALLERGIES',
      'CURRENT MEDICATIONS',
      'CHRONIC CONDITIONS',
      'EMERGENCY CONTACT',
    ]) {
      expect(t.getSemantics(find.text(title)), isSemantics(isHeader: true),
          reason: title);
    }
    for (final s in {
      'screen 4': ('This code isn\'t active', const ScanNotActive()),
      'too many tries': ('Too many tries', const ScanRateLimited()),
      "couldn't load": ('We couldn\'t load this information', const ScanFailed()),
    }.entries) {
      await _open(t, _FakeScan([s.value.$2]));
      expect(t.getSemantics(find.text(s.value.$1)),
          isSemantics(isLiveRegion: true),
          reason: s.key);
    }
    handle.dispose();
  });

  testWidgets(
      'TC-EMG-249: each Call button is one screen-reader button with a spoken '
      'label, and activating it from the screen reader places the call',
      (t) async {
    final handle = t.ensureSemantics();
    final launched = await _open(t, _FakeScan([_full]));
    const contact = 'Call Taylor Miller at (415) 555-0184';
    expect(find.bySemanticsLabel(contact), findsOneWidget);
    expect(t.getSemantics(find.bySemanticsLabel(contact)),
        isSemantics(label: contact, isButton: true, hasTapAction: true));
    t.semantics.tap(find.semantics.byLabel(contact));
    await t.pump();
    expect(launched, [Uri(scheme: 'tel', path: '4155550184')]);

    final launched911 = await _open(t, _FakeScan([const ScanNotActive()]));
    expect(t.getSemantics(find.bySemanticsLabel('Call 911')),
        isSemantics(label: 'Call 911', isButton: true, hasTapAction: true));
    t.semantics.tap(find.semantics.byLabel('Call 911'));
    await t.pump();
    expect(launched911, [Uri(scheme: 'tel', path: '911')]);
    handle.dispose();
  });

  testWidgets(
      'TC-EMG-250: every button is at least 48 x 48 and labelled (Android and '
      'iOS tap-target guidelines, SC 2.5.5 advisory)', (t) async {
    final handle = t.ensureSemantics();
    for (final s in _states.entries) {
      await _open(t, _FakeScan(s.value), theme: AppTheme.lightTheme);
      await expectLater(t, meetsGuideline(androidTapTargetGuideline),
          reason: s.key);
      await expectLater(t, meetsGuideline(iOSTapTargetGuideline), reason: s.key);
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline),
          reason: s.key);
    }
    handle.dispose();
  });
}
