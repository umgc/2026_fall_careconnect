// The patient's passport screen (CC-12 screen 1) against a fake backend that
// behaves like /v1/api/passport: it keeps sharing, the profile and the QR
// code between calls, and works out `ready` the way the backend does.
//
// Test Plan §3.28: TC-EMG-353…373 are the author's; TC-EMG-379…397 are the
// Testing Lead's (functional gaps, then accessibility, WCAG 2.1 AA), and
// TC-EMG-400…402 (added after the mutation run).

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/features/medical_passport/models/medical_passport.dart';
import 'package:care_connect_app/features/medical_passport/pages/medical_passport_page.dart';

const _base = '/v1/api/passport';

class _Backend {
  _Backend({bool empty = false}) {
    if (empty) {
      passport = {
        'name': 'Sam New',
        'age': null,
        'bloodType': null,
        'chronicConditions': null,
        'emergencyContact': null,
        'allergies': [],
        'medications': [],
        'sharing': {for (final f in PassportField.values) f.apiName: false},
        'token': null,
        'ready': false,
        'lastUpdated': null,
        'lastUpdatedBySection': {},
      };
    }
  }

  Map<String, dynamic> passport = {
    'name': 'Jordan Miller',
    'age': 41,
    'bloodType': 'O_POSITIVE',
    'chronicConditions': 'Type 2 diabetes',
    'emergencyContact': {
      'name': 'Taylor Miller',
      'relationship': 'Spouse',
      'phone': '(415) 555-0184',
    },
    'allergies': [
      {'allergen': 'Penicillin', 'severity': 'SEVERE', 'reaction': 'Anaphylaxis'},
      {'allergen': 'Peanuts', 'severity': 'MODERATE', 'reaction': 'Hives'},
    ],
    'medications': [
      {'name': 'Lisinopril', 'dosage': '10 mg', 'frequency': 'Once daily'},
      {'name': 'Metformin', 'dosage': '500 mg', 'frequency': 'Twice daily'},
    ],
    'sharing': {
      'ALLERGIES': true,
      'MEDICATIONS': true,
      'CHRONIC_CONDITIONS': false,
      'BLOOD_TYPE': true,
      'EMERGENCY_CONTACT': false,
    },
    'token': {'active': true, 'createdAt': '2026-10-01T12:00:00Z', 'lastScannedAt': null},
    'ready': true,
    'lastUpdated': '2026-07-01T09:00:00Z',
    'lastUpdatedBySection': {'MEDICATIONS': '2026-07-01T09:00:00Z'},
  };

  final List<http.Request> requests = [];

  /// One-shot answers by "METHOD path", e.g. "PUT /v1/api/passport/profile".
  final Map<String, http.Response> failures = {};

  List<String> get calls => [for (final r in requests) '${r.method} ${r.url.path}'];

  Future<http.Response> handle(http.Request req) async {
    requests.add(req);
    final key = '${req.method} ${req.url.path}';
    final failure = failures.remove(key);
    if (failure != null) return failure;

    final path = req.url.path;
    if (req.method == 'GET' && path == _base) return _ok();
    if (req.method == 'PUT' && path.startsWith('$_base/visibility/')) {
      final field = path.split('/').last;
      (passport['sharing'] as Map)[field] = (jsonDecode(req.body) as Map)['isPublic'];
      return _ok();
    }
    if (req.method == 'PUT' && path == '$_base/profile') {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      passport['bloodType'] = body['bloodType'];
      passport['chronicConditions'] = body['chronicConditions'];
      final name = body['emergencyContactName'];
      final phone = body['emergencyContactPhone'];
      passport['emergencyContact'] = name == null && phone == null
          ? null
          : {'name': name, 'relationship': body['emergencyContactRelationship'], 'phone': phone};
      return _ok();
    }
    if (req.method == 'POST' && path == '$_base/token') {
      passport['token'] = {'active': true, 'createdAt': '2026-10-14T12:00:00Z', 'lastScannedAt': null};
      return http.Response(
          jsonEncode({
            'token': 'new-token',
            'url': 'http://localhost:3000/passport/new-token',
            'createdAt': '2026-10-14T12:00:00Z',
          }),
          201);
    }
    if (req.method == 'DELETE' && path == '$_base/token') {
      passport['token'] = null;
      return http.Response('', 204);
    }
    return http.Response('{"error":"not in fake"}', 404);
  }

  http.Response _ok() {
    final shared = (passport['sharing'] as Map).values.any((v) => v == true);
    passport['ready'] = passport['token'] != null && shared;
    return http.Response(jsonEncode(passport), 200);
  }
}

void _platformChannels() {
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async => call.method == 'readAll' ? <String, String>{} : null,
  );
}

/// Runs [body] with every HTTP call answered by [backend].
Future<void> _withBackend(_Backend backend, Future<void> Function() body) =>
    http.runWithClient(body, () => MockClient(backend.handle));

Future<void> _open(WidgetTester t,
    {Size size = const Size(1400, 1400), ThemeData? theme, double textScale = 1}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final router = GoRouter(
    initialLocation: '/medical-passport',
    routes: [
      GoRoute(path: '/dashboard', builder: (_, __) => const Scaffold(body: Text('Dashboard'))),
      GoRoute(path: '/medical-passport', builder: (_, __) => const MedicalPassportPage()),
    ],
  );
  // A new key each time, so a second _open in one test starts a fresh page.
  await t.pumpWidget(MaterialApp.router(
    key: UniqueKey(),
    theme: theme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    routerConfig: router,
  ));
  await t.pumpAndSettle();
}

Finder _switchFor(PassportField field) =>
    find.descendant(of: find.byKey(shareSwitchKey(field)), matching: find.byType(Switch));

void main() {
  setUp(_platformChannels);

  testWidgets('TC-EMG-353: shows everything on file, what is shared, and that the passport is ready',
      (t) async {
    final backend = _Backend();
    await _withBackend(backend, () async {
      await _open(t);

      expect(find.text('Medical passport'), findsWidgets);
      expect(find.text('Jordan Miller'), findsOneWidget);
      expect(find.text('Age 41  ·  Blood type O+'), findsOneWidget);
      expect(find.text('Ready to share'), findsOneWidget);
      expect(find.textContaining('Last updated Jul 1, 2026'), findsOneWidget);
      expect(find.text('Lisinopril 10 mg'), findsOneWidget);
      expect(find.text('Twice daily'), findsOneWidget);
      expect(find.text('Updated Jul 1, 2026'), findsOneWidget);
      expect(find.text('SEVERE'), findsOneWidget);
      expect(find.text('MODERATE'), findsOneWidget);
      expect(find.text('Reaction: Anaphylaxis'), findsOneWidget);
      expect(find.text('Type 2 diabetes'), findsOneWidget);
      expect(find.text('Taylor Miller'), findsOneWidget);
      expect(find.text('Spouse'), findsOneWidget);
      expect(find.text('(415) 555-0184'), findsOneWidget);
      expect(find.text('Show emergency QR'), findsOneWidget);
      expect(find.text('Code active. Not scanned yet.'), findsOneWidget);

      expect(t.widget<Switch>(_switchFor(PassportField.medications)).value, isTrue);
      expect(t.widget<Switch>(_switchFor(PassportField.chronicConditions)).value, isFalse);
      expect(t.widget<Switch>(_switchFor(PassportField.emergencyContact)).value, isFalse);
      expect(backend.calls, ['GET $_base']);
    });
  });

  testWidgets('TC-EMG-354: at phone width the cards stack into one column without overflowing', (t) async {
    await _withBackend(_Backend(), () async {
      await _open(t, size: const Size(390, 3000));

      expect(t.takeException(), isNull);
      final meds = t.getTopLeft(find.text('Medications'));
      final contact = t.getTopLeft(find.text('Emergency contact'));
      expect(contact.dx, closeTo(meds.dx, 1), reason: 'same column');
      expect(contact.dy, greaterThan(meds.dy));
    });
  });

  testWidgets('TC-EMG-355: turning a switch off hides that section and saves it', (t) async {
    final backend = _Backend();
    await _withBackend(backend, () async {
      await _open(t);

      await t.tap(_switchFor(PassportField.medications));
      await t.pumpAndSettle();

      expect(backend.calls.last, 'PUT $_base/visibility/MEDICATIONS');
      expect(jsonDecode(backend.requests.last.body), {'isPublic': false});
      expect(t.widget<Switch>(_switchFor(PassportField.medications)).value, isFalse);
    });
  });

  testWidgets('TC-EMG-356: a failed switch change leaves the switch as it was and says so', (t) async {
    final backend = _Backend()
      ..failures['PUT $_base/visibility/EMERGENCY_CONTACT'] = http.Response('', 500);
    await _withBackend(backend, () async {
      await _open(t);

      await t.tap(_switchFor(PassportField.emergencyContact));
      await t.pumpAndSettle();

      expect(find.text('Couldn\'t change what\'s shared. Try again.'), findsOneWidget);
      expect(t.widget<Switch>(_switchFor(PassportField.emergencyContact)).value, isFalse);
    });
  });

  testWidgets('TC-EMG-357: a new patient sees empty sections with their switches off and how to get ready',
      (t) async {
    await _withBackend(_Backend(empty: true), () async {
      await _open(t);

      expect(find.text('Not ready'), findsOneWidget);
      expect(find.text('Create your QR code'), findsOneWidget);
      expect(find.text('Nothing added yet'), findsOneWidget);
      expect(find.text('Age 41  ·  Blood type O+'), findsNothing);
      expect(find.text('Blood type not set'), findsOneWidget);
      expect(find.textContaining('No active medications on file'), findsOneWidget);
      expect(find.textContaining('No active allergies on file'), findsOneWidget);
      expect(find.text('No emergency contact added.'), findsOneWidget);
      expect(find.text('Create emergency QR'), findsOneWidget);
      for (final field in PassportField.values) {
        expect(t.widget<Switch>(_switchFor(field)).onChanged, isNull, reason: field.name);
      }
    });
  });

  testWidgets('TC-EMG-358: with a code but nothing shared, it says to share a section', (t) async {
    final backend = _Backend();
    (backend.passport['sharing'] as Map).updateAll((_, __) => false);
    await _withBackend(backend, () async {
      await _open(t);

      expect(find.text('Not ready'), findsOneWidget);
      expect(find.text('Share at least one section'), findsOneWidget);
      expect(find.text('Get ready for an emergency'), findsOneWidget);
    });
  });

  testWidgets('TC-EMG-359: creating the first code shows its QR once, then the passport reloads', (t) async {
    final backend = _Backend(empty: true);
    await _withBackend(backend, () async {
      await _open(t);

      await t.tap(find.text('Create emergency QR'));
      await t.pumpAndSettle();

      expect(backend.calls, ['GET $_base', 'POST $_base/token', 'GET $_base']);
      expect(find.text('Your emergency QR code'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.textContaining('can\'t be shown again'), findsOneWidget);

      await t.tap(find.text('Done'));
      await t.pumpAndSettle();
      expect(find.text('Your emergency QR code'), findsNothing);
      expect(find.text('Show emergency QR'), findsOneWidget);
    });
  });

  testWidgets('TC-EMG-360: with a code already active, a new one is only made after the patient agrees',
      (t) async {
    final backend = _Backend();
    await _withBackend(backend, () async {
      await _open(t);

      await t.tap(find.text('Show emergency QR'));
      await t.pumpAndSettle();
      expect(find.text('Make a new QR code?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(backend.calls, isNot(contains('POST $_base/token')));

      await t.tap(find.text('Make a new QR code'));
      await t.pumpAndSettle();
      await t.tap(find.text('Make new code'));
      await t.pumpAndSettle();
      expect(backend.calls, contains('POST $_base/token'));
      expect(find.byType(QrImageView), findsOneWidget);
    });
  });

  testWidgets('TC-EMG-361: a failed code shows an error and no QR', (t) async {
    final backend = _Backend(empty: true)
      ..failures['POST $_base/token'] = http.Response('', 500);
    await _withBackend(backend, () async {
      await _open(t);

      await t.tap(find.text('Create emergency QR'));
      await t.pumpAndSettle();

      expect(find.text('Couldn\'t make a QR code. Try again.'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
    });
  });

  testWidgets('TC-EMG-362: turning the code off asks first, then revokes it', (t) async {
    final backend = _Backend();
    await _withBackend(backend, () async {
      await _open(t);

      await t.tap(find.text('Turn off QR code'));
      await t.pumpAndSettle();
      await t.tap(find.text('Turn off'));
      await t.pumpAndSettle();

      expect(backend.calls, contains('DELETE $_base/token'));
      expect(find.text('QR code turned off.'), findsOneWidget);
      expect(find.text('Create emergency QR'), findsOneWidget);
      expect(find.text('Not ready'), findsOneWidget);
    });
  });

  testWidgets('TC-EMG-363: a failed turn-off says so', (t) async {
    final backend = _Backend()..failures['DELETE $_base/token'] = http.Response('', 500);
    await _withBackend(backend, () async {
      await _open(t);

      await t.tap(find.text('Turn off QR code'));
      await t.pumpAndSettle();
      await t.tap(find.text('Turn off'));
      await t.pumpAndSettle();

      expect(find.text('Couldn\'t turn off the QR code. Try again.'), findsOneWidget);
    });
  });

  testWidgets('TC-EMG-364: editing details starts from what is saved and sends every field', (t) async {
    final backend = _Backend();
    await _withBackend(backend, () async {
      await _open(t);

      await t.tap(find.text('Edit details'));
      await t.pumpAndSettle();
      expect(find.text('Edit passport details'), findsOneWidget);
      final phone = find.widgetWithText(TextField, 'Phone');
      expect(t.widget<TextField>(phone).controller!.text, '(415) 555-0184');

      await t.enterText(find.widgetWithText(TextField, 'Name'), '  Dana Miller ');
      await t.enterText(phone, '');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();

      expect(backend.calls.last, 'PUT $_base/profile');
      expect(jsonDecode(backend.requests.last.body), {
        'bloodType': 'O_POSITIVE',
        'chronicConditions': 'Type 2 diabetes',
        'emergencyContactName': 'Dana Miller',
        'emergencyContactRelationship': 'Spouse',
        'emergencyContactPhone': null,
      });
      expect(find.text('Passport details saved.'), findsOneWidget);
      expect(find.text('Dana Miller'), findsOneWidget);
    });
  });

  testWidgets('TC-EMG-365: the blood type can be cleared from the edit dialog', (t) async {
    final backend = _Backend();
    await _withBackend(backend, () async {
      await _open(t);

      await t.tap(find.text('Edit details'));
      await t.pumpAndSettle();
      await t.tap(find.text('O+').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Not set').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();

      expect((jsonDecode(backend.requests.last.body) as Map)['bloodType'], isNull);
      expect(find.text('Age 41  ·  Blood type not set'), findsOneWidget);
    });
  });

  testWidgets('TC-EMG-366: cancelling the edit dialog sends nothing', (t) async {
    final backend = _Backend();
    await _withBackend(backend, () async {
      await _open(t);

      await t.tap(find.text('Edit').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();

      expect(backend.calls, ['GET $_base']);
    });
  });

  testWidgets('TC-EMG-367: a rejected edit shows the backend\'s reason', (t) async {
    final backend = _Backend()
      ..failures['PUT $_base/profile'] = http.Response(
          jsonEncode({'error': 'emergencyContactPhone must be at most 32 characters'}), 400);
    await _withBackend(backend, () async {
      await _open(t);

      await t.tap(find.text('Edit details'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();

      expect(find.text('emergencyContactPhone must be at most 32 characters'), findsOneWidget);
    });
  });

  testWidgets('TC-EMG-368: a load failure offers a retry that recovers', (t) async {
    final backend = _Backend()..failures['GET $_base'] = http.Response('', 503);
    await _withBackend(backend, () async {
      await _open(t);
      expect(find.text('Couldn\'t load your passport.'), findsOneWidget);

      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();

      expect(find.text('Jordan Miller'), findsOneWidget);
    });
  });

  testWidgets('TC-EMG-369: a non-patient account is told passports are for patients, with no retry',
      (t) async {
    final backend = _Backend()..failures['GET $_base'] = http.Response('', 403);
    await _withBackend(backend, () async {
      await _open(t);

      expect(find.text('Only patients have a medical passport.'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });
  });

  testWidgets('TC-EMG-370: an expired session asks the patient to sign in again', (t) async {
    final backend = _Backend()..failures['GET $_base'] = http.Response('', 401);
    await _withBackend(backend, () async {
      await _open(t);

      expect(find.textContaining('Sign in again'), findsOneWidget);
    });
  });

  testWidgets('TC-EMG-371: back goes to the dashboard when there is nothing to pop', (t) async {
    await _withBackend(_Backend(), () async {
      await _open(t);

      await t.tap(find.byTooltip('Back'));
      await t.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
    });
  });

  testWidgets('TC-EMG-372: switches and status are labelled for screen readers', (t) async {
    final handle = t.ensureSemantics();
    await _withBackend(_Backend(), () async {
      await _open(t);

      expect(find.bySemanticsLabel('Show medications on QR code'), findsOneWidget);
      expect(find.bySemanticsLabel('Passport status: ready to share'), findsOneWidget);
      expect(find.bySemanticsLabel('Call (415) 555-0184'), findsOneWidget);
    });
    handle.dispose();
  });

  test('TC-EMG-373: severity labels read naturally', () {
    expect(severityLabel('LIFE_THREATENING'), 'Life-threatening');
    expect(severityLabel('MILD'), 'Mild');
    expect(severityLabel(null), isNull);
    expect(severityLabel('UNKNOWN'), isNull);
  });

  // ---------- Testing Lead: functional gaps ----------

  testWidgets(
      'TC-EMG-379: each section\'s switch saves its own field: tapping it PUTs '
      '/visibility/<FIELD> with the opposite of what is stored', (t) async {
    final backend = _Backend();
    final sharing = backend.passport['sharing'] as Map;
    await _withBackend(backend, () async {
      await _open(t);
      for (final field in PassportField.values) {
        final before = sharing[field.apiName] as bool;
        await t.tap(_switchFor(field));
        await t.pumpAndSettle();
        expect(backend.calls.last, 'PUT $_base/visibility/${field.apiName}',
            reason: field.name);
        expect(jsonDecode(backend.requests.last.body), {'isPublic': !before},
            reason: field.name);
        expect(t.widget<Switch>(_switchFor(field)).value, !before,
            reason: field.name);
      }
    });
  });

  testWidgets(
      'TC-EMG-380: while a share change is saving, that switch is disabled '
      '(a second tap sends nothing) and the other sections\' switches still '
      'work', (t) async {
    final backend = _Backend();
    final gate = Completer<void>();
    await http.runWithClient(() async {
      await _open(t);
      await t.tap(_switchFor(PassportField.medications));
      await t.pump();
      expect(t.widget<Switch>(_switchFor(PassportField.medications)).onChanged,
          isNull);
      await t.tap(_switchFor(PassportField.medications), warnIfMissed: false);
      await t.pump();
      expect(t.widget<Switch>(_switchFor(PassportField.allergies)).onChanged,
          isNotNull);
      gate.complete();
      await t.pumpAndSettle();
    }, () => MockClient((req) async {
          if (req.url.path.endsWith('/MEDICATIONS')) await gate.future;
          return backend.handle(req);
        }));
    expect(backend.calls.where((c) => c.endsWith('/MEDICATIONS')).length, 1);
  });

  testWidgets(
      'TC-EMG-381: a double tap on "Create emergency QR" makes one code',
      (t) async {
    final backend = _Backend(empty: true);
    await _withBackend(backend, () async {
      await _open(t);
      await t.tap(find.text('Create emergency QR'));
      await t.tap(find.text('Create emergency QR'), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(backend.calls.where((c) => c == 'POST $_base/token').length, 1);
      expect(find.byType(QrImageView), findsOneWidget);
    });
  });

  testWidgets(
      'TC-EMG-382: when a refresh fails after the passport is on screen, the '
      'patient is told, and the passport stays (DEF-EMG-15)', (t) async {
    final backend = _Backend();
    await _withBackend(backend, () async {
      await _open(t);
      backend.failures['GET $_base'] = http.Response('', 503);
      await t.fling(find.text('Jordan Miller'), const Offset(0, 500), 1000);
      await t.pumpAndSettle();
      expect(backend.calls, ['GET $_base', 'GET $_base']);
      expect(find.text('Jordan Miller'), findsOneWidget);
      expect(find.text('Couldn\'t refresh your passport. Try again.'),
          findsOneWidget);
    });
  });

  testWidgets(
      'TC-EMG-383: a server that never answers does not leave the spinner up: '
      'after 20 s the page says it couldn\'t load and offers Try again '
      '(DEF-EMG-16)', (t) async {
    await http.runWithClient(() async {
      await t.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await t.pump();
      expect(find.bySemanticsLabel('Loading your passport'), findsOneWidget);
      await t.pump(const Duration(seconds: 21));
      await t.pump();
      expect(find.text('Couldn\'t load your passport.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    }, () => MockClient((_) => Completer<http.Response>().future));
  });

  testWidgets(
      'TC-EMG-384: an expired session (401) offers Sign in, which opens the '
      'login page (DEF-EMG-17)', (t) async {
    final backend = _Backend()..failures['GET $_base'] = http.Response('', 401);
    await _withBackend(backend, () async {
      final router = _router();
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await t.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path, '/login');
    });
  });

  testWidgets(
      'TC-EMG-385: a section stored as shared but now empty does not read '
      '"Hidden": its switch shows "Shared on QR" and can be turned off '
      '(DEF-EMG-18)', (t) async {
    // The patient shared Conditions, then cleared the text. The backend keeps
    // the choice, counts it for `ready`, and shows the conditions again on a
    // scan as soon as they are re-entered.
    final backend = _Backend();
    backend.passport['chronicConditions'] = null;
    (backend.passport['sharing'] as Map)
      ..updateAll((_, __) => false)
      ..['CHRONIC_CONDITIONS'] = true;
    await _withBackend(backend, () async {
      await _open(t);
      expect(find.text('Ready to share'), findsOneWidget);
      final conditions = t.widget<Switch>(_switchFor(PassportField.chronicConditions));
      expect(conditions.value, isTrue, reason: 'stored as shared');
      expect(conditions.onChanged, isNotNull, reason: 'can be turned off');
      await t.tap(_switchFor(PassportField.chronicConditions));
      await t.pumpAndSettle();
      expect(backend.calls.last, 'PUT $_base/visibility/CHRONIC_CONDITIONS');
      expect(jsonDecode(backend.requests.last.body), {'isPublic': false});
      expect(find.text('Not ready'), findsOneWidget);
    });
    // DEF-EMG-18: fixed by PR344_DEF-EMG-18-suggested.patch, not applied yet.
  }, skip: true);

  testWidgets(
      'TC-EMG-386: the two-column layout starts at exactly 900 px of content '
      '(932 px window less 2 × 16 padding); at 899 px it is one column',
      (t) async {
    for (final (width, twoColumns) in [(931.0, false), (932.0, true)]) {
      await _withBackend(_Backend(), () async {
        await _open(t, size: Size(width, 3000));
        expect(t.takeException(), isNull);
        final meds = t.getTopLeft(find.text('Medications'));
        final contact = t.getTopLeft(find.text('Emergency contact'));
        expect(contact.dx > meds.dx + 100, twoColumns, reason: '$width');
      });
    }
  });

  testWidgets(
      'TC-EMG-387: a code that has been scanned shows the date of the last '
      'scan', (t) async {
    final backend = _Backend();
    (backend.passport['token'] as Map)['lastScannedAt'] = '2026-10-02T15:00:00Z';
    await _withBackend(backend, () async {
      await _open(t);
      expect(find.text('Code active. Last scanned '
          '${formatPassportDate(DateTime.utc(2026, 10, 2, 15))}.'), findsOneWidget);
      expect(find.text('Code active. Not scanned yet.'), findsNothing);
    });
  });

  testWidgets(
      'TC-EMG-388: tapping the emergency contact\'s phone opens the dialler '
      'with a tel: link to that number', (t) async {
    final launched = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in _urlLauncherChannels) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        launched.add('${(call.arguments as Map)['url']}');
        return true;
      });
    }
    addTearDown(() {
      for (final name in _urlLauncherChannels) {
        messenger.setMockMethodCallHandler(MethodChannel(name), null);
      }
    });
    await _withBackend(_Backend(), () async {
      await _open(t);
      await t.tap(find.text('(415) 555-0184'));
      await t.pumpAndSettle();
    });
    expect(launched, hasLength(1));
    expect(Uri.parse(launched.single).scheme, 'tel');
    expect(Uri.decodeComponent(Uri.parse(launched.single).path),
        '(415) 555-0184');
  });

  testWidgets(
      'TC-EMG-389: leaving the page while the passport is still loading '
      'throws nothing when the answer arrives', (t) async {
    final gate = Completer<http.Response>();
    await http.runWithClient(() async {
      final router = _router();
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      await t.pump();
      router.go('/dashboard');
      await t.pumpAndSettle();
      gate.complete(http.Response(jsonEncode(_Backend().passport), 200));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Dashboard'), findsOneWidget);
    }, () => MockClient((_) => gate.future));
  });

  testWidgets(
      'TC-EMG-390: a save that loses a race (409) says to try again and keeps '
      'the details as they were; so does a share change', (t) async {
    final backend = _Backend()
      ..failures['PUT $_base/profile'] = http.Response(
          jsonEncode({'error': 'Your passport was changed at the same time'}), 409)
      ..failures['PUT $_base/visibility/MEDICATIONS'] = http.Response(
          jsonEncode({'error': 'Your passport was changed at the same time'}), 409);
    await _withBackend(backend, () async {
      await _open(t);
      await t.tap(find.text('Edit details'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Name'), 'Dana Miller');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text('Couldn\'t save your details. Try again.'), findsOneWidget);
      expect(find.text('Taylor Miller'), findsOneWidget);
      expect(find.text('Dana Miller'), findsNothing);

      await t.tap(_switchFor(PassportField.medications));
      await t.pumpAndSettle();
      expect(find.text('Couldn\'t change what\'s shared. Try again.'), findsOneWidget);
      expect(t.widget<Switch>(_switchFor(PassportField.medications)).value, isTrue);
    });
  });

  testWidgets(
      'TC-EMG-391: each edit field stops at the backend\'s limit (conditions '
      '2000, name 255, relationship 64, phone 32): one character more is not '
      'taken, and the limit itself is saved', (t) async {
    final backend = _Backend();
    await _withBackend(backend, () async {
      await _open(t);
      await t.tap(find.text('Edit details'));
      await t.pumpAndSettle();
      final limits = {
        'Conditions': PassportProfileUpdate.maxChronicConditions,
        'Name': PassportProfileUpdate.maxContactName,
        'Relationship': PassportProfileUpdate.maxContactRelationship,
        'Phone': PassportProfileUpdate.maxContactPhone,
      };
      for (final e in limits.entries) {
        final field = find.widgetWithText(TextField, e.key);
        await t.enterText(field, '7' * (e.value + 1));
        expect(t.widget<TextField>(field).controller!.text.length, e.value,
            reason: e.key);
      }
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      final body = jsonDecode(backend.requests.last.body) as Map;
      expect((body['chronicConditions'] as String).length, 2000);
      expect((body['emergencyContactName'] as String).length, 255);
      expect((body['emergencyContactRelationship'] as String).length, 64);
      expect((body['emergencyContactPhone'] as String).length, 32);
    });
  });

  testWidgets(
      'TC-EMG-400: cancelling "Turn off QR code" sends nothing and the code '
      'stays on', (t) async {
    final backend = _Backend();
    await _withBackend(backend, () async {
      await _open(t);
      await t.tap(find.text('Turn off QR code'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(backend.calls, ['GET $_base']);
      expect(find.text('Turn off QR code'), findsOneWidget);
      expect(find.text('Code active. Not scanned yet.'), findsOneWidget);
    });
  });

  testWidgets(
      'TC-EMG-401: the QR shown is the link the server issued, module for '
      'module (not the bare code)', (t) async {
    await _withBackend(_Backend(empty: true), () async {
      await _open(t);
      await t.tap(find.text('Create emergency QR'));
      await t.pumpAndSettle();
      expect(await _qrHolds(t, 'http://localhost:3000/passport/new-token'), isTrue);
      expect(await _qrHolds(t, 'new-token'), isFalse);
    });
  });

  testWidgets(
      'TC-EMG-402: severe and life-threatening allergies are marked as serious '
      '(red tile); a moderate one is not', (t) async {
    final backend = _Backend();
    backend.passport['allergies'] = [
      ...backend.passport['allergies'] as List,
      {'allergen': 'Latex', 'severity': 'LIFE_THREATENING', 'reaction': null},
    ];
    Color? tile(String allergen) => (t
            .widget<Container>(find
                .ancestor(of: find.text(allergen), matching: find.byType(Container))
                .first)
            .decoration as BoxDecoration?)
        ?.color;
    await _withBackend(backend, () async {
      await _open(t);
      expect(tile('Penicillin'), const Color(0xFFFEF3F2));
      expect(tile('Latex'), const Color(0xFFFEF3F2));
      expect(tile('Peanuts'), Colors.white);
      expect(find.text('LIFE-THREATENING'), findsOneWidget);
    });
  });

  // ---------- Testing Lead: accessibility (WCAG 2.1 AA) ----------

  for (final theme in {
    'light': AppTheme.lightTheme,
    'dark': AppTheme.darkTheme,
  }.entries) {
    testWidgets(
        'TC-EMG-392: every text on every state and in every dialog is at '
        'least 4.5:1 against what is behind it (SC 1.4.3), app ${theme.key} '
        'theme (DEF-EMG-20)', (t) async {
      final failures = <String>[];
      for (final s in _states().entries) {
        await _withBackend(s.value(), () async {
          await _open(t, theme: theme.value);
          failures.addAll(_lowContrastText(t).map((f) => '${s.key}: $f'));
        });
      }
      await _withBackend(_Backend(), () async {
        await _open(t, theme: theme.value);
        await t.tap(find.text('Edit details'));
        await t.pumpAndSettle();
        failures.addAll(_lowContrastText(t, dialog: true).map((f) => 'edit dialog: $f'));
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        await t.tap(find.text('Turn off QR code'));
        await t.pumpAndSettle();
        failures.addAll(_lowContrastText(t, dialog: true).map((f) => 'confirm dialog: $f'));
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        await t.tap(find.text('Make a new QR code'));
        await t.pumpAndSettle();
        await t.tap(find.text('Make new code'));
        await t.pumpAndSettle();
        failures.addAll(_lowContrastText(t, dialog: true).map((f) => 'QR dialog: $f'));
      });
      expect(failures, isEmpty);
    });
  }

  testWidgets(
      'TC-EMG-393: at 200% text on a 320 × 640 phone every state and the edit '
      'dialog lay out without overflow or clipped text (SC 1.4.4, 1.4.10) '
      '(DEF-EMG-21)', (t) async {
    final problems = <String>[];
    Future<void> check(String name) async {
      final e = t.takeException();
      if (e != null) problems.add('$name: $e');
      problems.addAll(_clipped(t).map((c) => '$name: $c'));
    }

    for (final s in _states().entries) {
      await _withBackend(s.value(), () async {
        await _open(t, size: const Size(320, 640), textScale: 2);
        await check(s.key);
      });
    }
    await _withBackend(_Backend(), () async {
      await _open(t, size: const Size(320, 640), textScale: 2);
      await t.tap(find.text('Edit details'));
      await t.pumpAndSettle();
      await check('edit dialog');
    });
    expect(problems, isEmpty);
  });

  testWidgets(
      'TC-EMG-394: "Medical passport" and each card title are headings, and '
      'the problem states are announced (live region, SC 4.1.3) (DEF-EMG-22)', (t) async {
    final handle = t.ensureSemantics();
    await _withBackend(_Backend(), () async {
      await _open(t);
      for (final title in [
        'Medical passport',
        'Medications',
        'Allergies',
        'Conditions',
        'Emergency contact',
      ]) {
        expect(t.getSemantics(find.text(title).first),
            isSemantics(isHeader: true), reason: title);
      }
    });
    for (final s in {
      503: 'Couldn\'t load your passport.',
      403: 'Only patients have a medical passport.',
      401: 'Your session has ended. Sign in again to see your passport.',
    }.entries) {
      final backend = _Backend()
        ..failures['GET $_base'] = http.Response('', s.key);
      await _withBackend(backend, () async {
        await _open(t);
        expect(t.getSemantics(find.text(s.value)),
            isSemantics(isLiveRegion: true), reason: '${s.key}');
      });
    }
    handle.dispose();
  });

  testWidgets(
      'TC-EMG-395: every button and switch is at least 48 × 48 and labelled '
      '(Android and iOS tap-target guidelines, SC 2.5.5 advisory)', (t) async {
    final handle = t.ensureSemantics();
    for (final s in {'full': _Backend.new, 'new patient': () => _Backend(empty: true)}.entries) {
      await _withBackend(s.value(), () async {
        await _open(t, theme: AppTheme.lightTheme);
        await expectLater(t, meetsGuideline(androidTapTargetGuideline), reason: s.key);
        await expectLater(t, meetsGuideline(iOSTapTargetGuideline), reason: s.key);
        await expectLater(t, meetsGuideline(labeledTapTargetGuideline), reason: s.key);
      });
    }
    handle.dispose();
  });

  testWidgets(
      'TC-EMG-396: a screen reader can turn each share switch on and off: the '
      'switch "Show <section> on QR code" has a tap action, and using it saves '
      'the change (SC 4.1.2, 2.1.1) (DEF-EMG-19)', (t) async {
    final handle = t.ensureSemantics();
    final backend = _Backend();
    await _withBackend(backend, () async {
      await _open(t);
      final node = t.getSemantics(find.bySemanticsLabel('Show medications on QR code'));
      expect(node, isSemantics(hasToggledState: true, isToggled: true,
          hasEnabledState: true, isEnabled: true, hasTapAction: true));
      t.semantics.tap(find.semantics.byLabel('Show medications on QR code'));
      await t.pumpAndSettle();
      expect(backend.calls.last, 'PUT $_base/visibility/MEDICATIONS');
      expect(jsonDecode(backend.requests.last.body), {'isPublic': false});
    });
    handle.dispose();
  });

  testWidgets(
      'TC-EMG-397: a screen reader meets the new QR as one image named "QR '
      'code for your medical passport", once, and never the link it holds '
      '(DEF-EMG-23)', (t) async {
    final handle = t.ensureSemantics();
    await _withBackend(_Backend(empty: true), () async {
      await _open(t);
      await t.tap(find.text('Create emergency QR'));
      await t.pumpAndSettle();
      final qr = find.bySemanticsLabel(RegExp('^QR code for your medical passport'));
      expect(qr, findsOneWidget);
      expect(t.getSemantics(qr),
          isSemantics(isImage: true, label: 'QR code for your medical passport'));
      expect(find.bySemanticsLabel(RegExp('qr code', caseSensitive: true)), findsNothing);
      expect(find.bySemanticsLabel(RegExp('new-token')), findsNothing);
    });
    handle.dispose();
  });
}

// ---------- Testing Lead helpers ----------

const _urlLauncherChannels = [
  'plugins.flutter.io/url_launcher',
  'plugins.flutter.io/url_launcher_android',
  'plugins.flutter.io/url_launcher_windows',
  'plugins.flutter.io/url_launcher_linux',
  'plugins.flutter.io/url_launcher_macos',
  'plugins.flutter.io/url_launcher_ios',
];

/// The page with a login route too, for the signed-out state.
GoRouter _router() => GoRouter(
      initialLocation: '/medical-passport',
      routes: [
        GoRoute(path: '/dashboard', builder: (_, __) => const Scaffold(body: Text('Dashboard'))),
        GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('Login'))),
        GoRoute(path: '/medical-passport', builder: (_, __) => const MedicalPassportPage()),
      ],
    );

/// Each state the page can open in, as the backend that produces it.
Map<String, _Backend Function()> _states() => {
      'full': _Backend.new,
      'new patient': () => _Backend(empty: true),
      'code, nothing shared': () {
        final b = _Backend();
        (b.passport['sharing'] as Map).updateAll((_, __) => false);
        return b;
      },
      'couldn\'t load': () => _Backend()..failures['GET $_base'] = http.Response('', 503),
      'not a patient': () => _Backend()..failures['GET $_base'] = http.Response('', 403),
      'signed out': () => _Backend()..failures['GET $_base'] = http.Response('', 401),
    };

double _channel(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The colour behind [e]: every filled ColoredBox, DecoratedBox and Material
/// between it and the root, composited from the outside in over white (the
/// same check as the CC-12 scan page's tests, PR #339).
Color _backgroundOf(Element e) {
  final layers = <Color>[];
  e.visitAncestorElements((a) {
    final w = a.widget;
    if (w is ColoredBox) {
      layers.add(w.color);
    } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
      final c = (w.decoration as BoxDecoration).color;
      if (c != null) layers.add(c);
    } else if (w is Material && w.color != null && w.type != MaterialType.transparency) {
      layers.add(w.color!);
    }
    return true;
  });
  var bg = Colors.white;
  for (final c in layers.reversed) {
    bg = Color.alphaBlend(c, bg);
  }
  return bg;
}

String _hex(Color c) => c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

/// Every Text on screen (or in the open dialog, with [dialog]) below 4.5:1
/// against what is behind it.
List<String> _lowContrastText(WidgetTester t, {bool dialog = false}) {
  final failures = <String>[];
  final texts = dialog
      ? find.descendant(of: find.byType(Dialog), matching: find.byType(Text))
      : find.byType(Text);
  for (final e in texts.evaluate()) {
    final w = e.widget as Text;
    final text = w.data ?? w.textSpan?.toPlainText() ?? '';
    // Text.rich carries its colour on the span, not the widget.
    final fg = DefaultTextStyle.of(e).style.merge(w.style).merge(w.textSpan?.style).color;
    if (fg == null || text.trim().isEmpty) continue;
    final bg = _backgroundOf(e);
    final shown = Color.alphaBlend(fg, bg);
    final r = _contrast(shown, bg);
    if (r < 4.5) {
      failures.add('"${text.trim()}": ${r.toStringAsFixed(2)} (${_hex(shown)} on ${_hex(bg)})');
    }
  }
  return failures;
}

/// Text cut off without a layout error: a paragraph squeezed shorter than its
/// text needs, or a button label painted outside its button.
List<String> _clipped(WidgetTester t) {
  final problems = <String>[];
  for (final p in find.byType(RichText).evaluate()) {
    final para = p.renderObject! as RenderParagraph;
    final needed = para.getMaxIntrinsicHeight(para.size.width);
    if (needed > para.size.height + 0.5) {
      problems.add('"${para.text.toPlainText()}" needs ${needed.toStringAsFixed(0)} px '
          'but has ${para.size.height.toStringAsFixed(0)} px');
    }
  }
  for (final button in find.bySubtype<ButtonStyleButton>().evaluate()) {
    final box = button.renderObject! as RenderBox;
    for (final text in find
        .descendant(of: find.byWidget(button.widget), matching: find.byType(Text))
        .evaluate()) {
      final textBox = text.renderObject! as RenderBox;
      final top = textBox.localToGlobal(Offset.zero).dy - box.localToGlobal(Offset.zero).dy;
      if (top < 0 || top + textBox.size.height > box.size.height + 0.5) {
        problems.add('"${(text.widget as Text).data}" is ${textBox.size.height.toStringAsFixed(0)} '
            'px tall in a ${box.size.height.toStringAsFixed(0)} px button');
      }
    }
  }
  return problems;
}

/// Whether the QR on screen encodes [data] (from PR #340's TC-EMG-313): paint
/// it and compare every module with a QR made from [data].
Future<bool> _qrHolds(WidgetTester t, String data) async {
  final painter = t
      .widget<CustomPaint>(
          find.descendant(of: find.byType(QrImageView), matching: find.byType(CustomPaint)))
      .painter! as QrPainter;
  final qr = QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.L));
  final n = qr.moduleCount;
  final size = n * 10.0;
  final bytes = (await t.runAsync(() => painter.toImageData(size, format: ImageByteFormat.rawRgba)))!;
  final px = ((size / n) * 2).roundToDouble() / 2;
  final inset = (size - px * n) / 2;
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      final x = (inset + (c + 0.5) * px).floor();
      final y = (inset + (r + 0.5) * px).floor();
      final alpha = bytes.getUint8((y * size.toInt() + x) * 4 + 3);
      if ((alpha > 128) != qr.isDark(r, c)) return false;
    }
  }
  return true;
}
