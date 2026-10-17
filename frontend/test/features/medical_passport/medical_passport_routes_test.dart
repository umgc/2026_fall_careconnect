// /medical-passport on the production route table, as
// health_data_routes_test.dart does for the Health Data routes.
//
// Test Plan §3.28: TC-EMG-374 and 375 are the author's; TC-EMG-398 and 399 are
// the Testing Lead's (route, page, the real service and HTTP in process).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/config/router/app_router.dart';
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
  });
}
