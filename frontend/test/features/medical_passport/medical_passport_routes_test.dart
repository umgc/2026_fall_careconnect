// /medical-passport on the production route table, as
// health_data_routes_test.dart does for the Health Data routes.
//
// Test Plan §3.28: TC-EMG-374 and 375 are the author's; TC-EMG-398, 399 and
// 476…478 are the Testing Lead's (route, page, the real service and HTTP in
// process; 476…478 go on to the real /emergency-qr, PR #362 follow-up).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/config/router/app_router.dart';
import 'package:care_connect_app/features/emergency_passport/pages/emergency_qr_page.dart';
import 'package:care_connect_app/features/medical_passport/models/medical_passport.dart';
import 'package:care_connect_app/features/medical_passport/pages/medical_passport_page.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/user_role_storage_service.dart';

const _secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
const _connectivityStatus = EventChannel('dev.fluttercommunity.plus/connectivity_status');

Future<GoRouter> _open(WidgetTester t, {required bool signedIn}) async {
  if (signedIn) {
    await UserRoleStorageService.instance.setUserData(role: 'PATIENT', userId: 1, patientId: 1);
  } else {
    await UserRoleStorageService.instance.clearUserData();
  }
  final router = GoRouter(
    initialLocation: '/medical-passport',
    routes: appRouter.configuration.routes,
  );
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
    value: UserProvider(),
    child: MaterialApp.router(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 50));
  }
  return router;
}

String _path(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

/// The route on top: a pushed page (context.push) leaves [_path] unchanged.
String _top(GoRouter r) => r.routerDelegate.currentConfiguration.matches.last.matchedLocation;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secure, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'containsKey') return false;
      return null;
    });
    messenger.setMockMethodCallHandler(
        _connectivity, (call) async => call.method == 'check' ? ['wifi'] : null);
    messenger.setMockStreamHandler(
        _connectivityStatus, MockStreamHandler.inline(onListen: (_, __) {}));
  });

  tearDown(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secure, null);
    messenger.setMockMethodCallHandler(_connectivity, null);
    messenger.setMockStreamHandler(_connectivityStatus, null);
  });

  testWidgets('TC-EMG-374: /medical-passport without signing in goes to the login page', (t) async {
    // Only where the router lands is under test. The inherited login page
    // overflows its Rows with the test font; that layout error is ignored.
    final previous = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.exceptionAsString().contains('RenderFlex overflowed')) previous?.call(d);
    };
    addTearDown(() => FlutterError.onError = previous);
    final r = await _open(t, signedIn: false);
    FlutterError.onError = previous;
    expect(_path(r), '/login');
    expect(find.byType(MedicalPassportPage), findsNothing);
  });

  testWidgets('TC-EMG-375: /medical-passport opens the passport for a signed-in patient', (t) async {
    await http.runWithClient(() async {
      final r = await _open(t, signedIn: true);
      expect(_path(r), '/medical-passport');
      expect(find.byType(MedicalPassportPage), findsOneWidget);
    }, () => MockClient((_) async => http.Response(jsonEncode({'name': 'Jordan Miller'}), 200)));
  });

  // ---------- Testing Lead: the route table, the page, the real service and HTTP ----------

  group('in process, with the stored sign-in', () {
    late Map<String, String> secure;
    late List<http.Request> sent;
    const jwt = 'eyJhbGciOiJIUzI1NiJ9.synthetic.signature';

    setUp(() {
      sent = [];
      secure = {'jwt_token': jwt, 'token_expiry': '4102444800'};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secure, (call) async {
        final args = (call.arguments as Map?) ?? const {};
        final key = args['key'] as String?;
        switch (call.method) {
          case 'read':
            return secure[key];
          case 'write':
            secure[key!] = args['value'] as String;
            return null;
          case 'delete':
            secure.remove(key);
            return null;
          case 'readAll':
            return Map<String, String>.of(secure);
          case 'containsKey':
            return secure.containsKey(key);
        }
        return null;
      });
    });

    List<http.Request> passportCalls() =>
        [for (final r in sent) if (r.url.path.startsWith('/v1/api/passport')) r];

    Map<String, Object?> passport() => {
          'name': 'Mary Johnson',
          'age': 68,
          'bloodType': 'O_POSITIVE',
          'allergies': [
            {'allergen': 'Penicillin', 'severity': 'MODERATE', 'reaction': 'Rash'},
          ],
          'medications': [],
          'sharing': {'ALLERGIES': true, 'BLOOD_TYPE': true},
          'token': null,
          'ready': false,
        };

    testWidgets(
        'TC-EMG-398: a signed-in patient opens /medical-passport through the '
        'app\'s route table; the GET and a share change both carry the stored '
        'sign-in, and the page shows what the server saved', (t) async {
      t.view.physicalSize = const Size(1400, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var current = passport();
      await http.runWithClient(() async {
        final r = await _open(t, signedIn: true);
        expect(_path(r), '/medical-passport');
        expect(find.text('Mary Johnson'), findsOneWidget);

        final allergies = find.descendant(
            of: find.byKey(shareSwitchKey(PassportField.allergies)),
            matching: find.byType(Switch));
        expect(t.widget<Switch>(allergies).value, isTrue);
        await t.tap(allergies);
        for (var i = 0; i < 10; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(t.widget<Switch>(allergies).value, isFalse);
      }, () => MockClient((req) async {
            sent.add(req);
            if (req.method == 'PUT' && req.url.path == '/v1/api/passport/visibility/ALLERGIES') {
              current = {
                ...current,
                'sharing': {'ALLERGIES': (jsonDecode(req.body) as Map)['isPublic'], 'BLOOD_TYPE': true},
              };
            }
            if (req.url.path.startsWith('/v1/api/passport')) {
              return http.Response(jsonEncode(current), 200);
            }
            return http.Response('{}', 404);
          }));

      expect([for (final r in passportCalls()) '${r.method} ${r.url.path}'], [
        'GET /v1/api/passport',
        'PUT /v1/api/passport/visibility/ALLERGIES',
      ]);
      expect(jsonDecode(passportCalls().last.body), {'isPublic': false});
      for (final r in passportCalls()) {
        expect(r.headers['Authorization'], 'Bearer $jwt', reason: r.url.path);
      }
    });

    testWidgets(
        'TC-EMG-399: a signed-in caregiver who opens /medical-passport is told '
        'passports are for patients (403), with no switches, no QR button and '
        'no retry', (t) async {
      await UserRoleStorageService.instance.setUserData(role: 'CAREGIVER', userId: 9, caregiverId: 9);
      await http.runWithClient(() async {
        final router = GoRouter(
          initialLocation: '/medical-passport',
          routes: appRouter.configuration.routes,
        );
        await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
          value: UserProvider(),
          child: MaterialApp.router(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ));
        for (var i = 0; i < 20; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(_path(router), '/medical-passport');
        expect(find.text('Only patients have a medical passport.'), findsOneWidget);
        expect(find.byType(Switch), findsNothing);
        expect(find.textContaining('emergency QR'), findsNothing);
        expect(find.text('Try again'), findsNothing);
      }, () => MockClient((req) async {
            sent.add(req);
            return req.url.path.startsWith('/v1/api/passport')
                ? http.Response('{"error":"Only patients have a passport"}', 403)
                : http.Response('{}', 404);
          }));
      expect([for (final r in passportCalls()) '${r.method} ${r.url.path}'],
          ['GET /v1/api/passport']);
      expect(passportCalls().single.headers['Authorization'], 'Bearer $jwt');
    });

    // ---------- PR #362 follow-up: screen 1 and the real screen 2 ----------

    const created = '2026-10-18T15:00:00.123456Z';
    const link = 'http://localhost:3000/#/passport/Q3k9xZ2v';
    const keptKey = 'cc12_emergency_qr_1';

    /// GET, POST /token and DELETE /token, keeping the code between calls, as
    /// the backend does. Every request is recorded in [sent].
    MockClient backend(Map<String, Object?> state) => MockClient((req) async {
          sent.add(req);
          final path = req.url.path;
          if (req.method == 'POST' && path == '/v1/api/passport/token') {
            state['token'] = {'active': true, 'createdAt': created, 'lastScannedAt': null};
            state['ready'] = true;
            return http.Response(
                jsonEncode({
                  'token': 'Q3k9xZ2v',
                  'url': 'http://localhost:3000/passport/Q3k9xZ2v',
                  'createdAt': created,
                }),
                201);
          }
          if (req.method == 'DELETE' && path == '/v1/api/passport/token') {
            state['token'] = null;
            state['ready'] = false;
            return http.Response('', 204);
          }
          if (req.method == 'GET' && path == '/v1/api/passport') {
            return http.Response(jsonEncode(state), 200);
          }
          return http.Response('{}', 404);
        });

    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 20; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> tapText(WidgetTester t, String text) async {
      await t.ensureVisible(find.text(text));
      await t.tap(find.text(text));
      await settle(t);
    }

    List<String> calls() => [for (final r in passportCalls()) '${r.method} ${r.url.path}'];

    void allSignedIn() {
      for (final r in passportCalls()) {
        expect(r.headers['Authorization'], 'Bearer $jwt', reason: '${r.method} ${r.url.path}');
      }
    }

    testWidgets(
        'TC-EMG-476: from the passport, "Create emergency QR" opens the real '
        'emergency QR screen; the code made there is kept on the device under '
        'the patient, and back on the passport it reloads and shows the code as '
        'active', (t) async {
      t.view.physicalSize = const Size(1400, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final state = passport();
      await http.runWithClient(() async {
        final r = await _open(t, signedIn: true);
        expect(find.text('Not ready'), findsOneWidget);

        await tapText(t, 'Create emergency QR');
        expect(_top(r), '/emergency-qr');
        expect(find.byType(EmergencyQrPage), findsOneWidget);
        await tapText(t, 'Create my emergency QR');
        expect(find.byType(QrImageView), findsOneWidget);

        await t.tap(find.byTooltip('Back'));
        await settle(t);
        expect(_path(r), '/medical-passport');
        expect(find.text('Show emergency QR'), findsOneWidget);
        expect(find.text('Code active. Not scanned yet.'), findsOneWidget);
        expect(find.text('Ready to share'), findsOneWidget);
      }, () => backend(state));

      expect(calls(), [
        'GET /v1/api/passport',
        'GET /v1/api/passport',
        'POST /v1/api/passport/token',
        'GET /v1/api/passport',
      ]);
      allSignedIn();
      final kept = jsonDecode(secure[keptKey]!) as Map;
      expect(kept['url'], link);
      expect(secure.keys.where((k) => k.startsWith('cc12_emergency_qr_')), [keptKey]);
    });

    testWidgets(
        'TC-EMG-477: with a code kept on this device, "Show emergency QR" shows '
        'that QR again on the emergency QR screen without making a new code',
        (t) async {
      t.view.physicalSize = const Size(1400, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      secure[keptKey] = jsonEncode({'url': link, 'createdAt': created});
      final state = {
        ...passport(),
        'token': {'active': true, 'createdAt': created, 'lastScannedAt': null},
        'ready': true,
      };
      await http.runWithClient(() async {
        final r = await _open(t, signedIn: true);
        await tapText(t, 'Show emergency QR');
        expect(_top(r), '/emergency-qr');
        expect(find.byType(QrImageView), findsOneWidget);
        expect(find.text('Your QR isn\'t saved on this device'), findsNothing);

        await t.tap(find.byTooltip('Back'));
        await settle(t);
        expect(_path(r), '/medical-passport');
      }, () => backend(state));

      expect(calls(), [
        'GET /v1/api/passport',
        'GET /v1/api/passport',
        'GET /v1/api/passport',
      ]);
      allSignedIn();
      expect(jsonDecode(secure[keptKey]!)['url'], link);
    });

    testWidgets(
        'TC-EMG-478: "Turn off QR code" on the passport turns the code off on '
        'the server and forgets the copy kept on this device; the emergency QR '
        'screen then offers a new code and shows no QR (DEF-EMG-27)', (t) async {
      t.view.physicalSize = const Size(1400, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      secure[keptKey] = jsonEncode({'url': link, 'createdAt': created});
      final state = {
        ...passport(),
        'token': {'active': true, 'createdAt': created, 'lastScannedAt': null},
        'ready': true,
      };
      await http.runWithClient(() async {
        final r = await _open(t, signedIn: true);
        await tapText(t, 'Turn off QR code');
        await tapText(t, 'Turn off');
        expect(find.text('QR code turned off.'), findsOneWidget);
        expect(find.text('Create emergency QR'), findsOneWidget);

        await tapText(t, 'Create emergency QR');
        expect(_top(r), '/emergency-qr');
        expect(find.text('Create my emergency QR'), findsOneWidget);
        expect(find.byType(QrImageView), findsNothing);
      }, () => backend(state));

      expect(calls(), [
        'GET /v1/api/passport',
        'DELETE /v1/api/passport/token',
        'GET /v1/api/passport',
        'GET /v1/api/passport',
      ]);
      allSignedIn();
      expect(secure.containsKey(keptKey), isFalse);
    });
  });
}
