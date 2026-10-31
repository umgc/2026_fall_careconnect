// Gap tests for AuthService: the Google deep-link OAuth flow, redirect guard,
// and response branches the existing suite does not reach.
//
// Why fakes: the OAuth flow depends on platform plugins (app_links and
// url_launcher) and the HTTP calls go through package:http, so each is replaced
// with an in-memory fake. No network is used and no ports are bound.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_links_platform_interface/app_links_platform_interface.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/services/auth_service.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/auth_token_manager.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../helpers/fake_http_overrides.dart';

/// Fake deep-link platform: tests push URIs through [controller].
class _FakeAppLinks extends AppLinksPlatform {
  final controller = StreamController<Uri>.broadcast();
  @override
  Stream<Uri> get uriLinkStream => controller.stream;
}

/// Fake url_launcher that records launches and can refuse them.
class _FakeLauncher extends UrlLauncherPlatform {
  _FakeLauncher({this.canLaunch_ = true});
  final bool canLaunch_;
  final launched = <String>[];

  @override
  get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => canLaunch_;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

Map<String, dynamic> _user({String role = 'PATIENT'}) => {
      'id': 7,
      'email': 'gap.user@example.test',
      'role': role,
      'token': 'unused',
      'name': 'Gap User',
      'patientId': 70,
      'emailVerified': true,
    };

/// Unsigned JWT-shaped token whose `exp` is an hour away, so AuthTokenManager
/// treats it as valid without calling the backend.
String _jwt([String tag = 'x']) {
  String enc(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  return '${enc({'alg': 'none'})}.${enc({'exp': exp, 'tag': tag})}.sig';
}

Uri _callback(Map<String, String> q) => Uri(
    scheme: 'careconnect',
    host: 'oauth',
    path: '/callback',
    queryParameters: q);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLocalizations t;
  // AppLinks() is a singleton that caches the first platform stream it sees,
  // so every test must feed the same fake.
  final links = _FakeAppLinks();
  late _FakeLauncher launcher;
  final googleJwt = _jwt('google');
  final cbJwt = _jwt('cb');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    t = await AppLocalizations.delegate.load(const Locale('en'));
    AppLinksPlatform.instance = links;
    launcher = _FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  tearDown(() => HttpOverrides.global = null);

  group('ApiConstants', () {
    test('webBaseUrl and baseUrl are consistent with the auth URL', () {
      expect(ApiConstants.webBaseUrl, isNotNull);
      expect(ApiConstants.baseUrl, isNotEmpty);
      expect(ApiConstants.auth, startsWith(ApiConstants.baseUrl));
    });
  });

  group('loginWithGoogle', () {
    /// Starts the flow and waits until the stream subscription exists.
    Future<Future<UserSession>> start() async {
      final f = AuthService.loginWithGoogle(t);
      // launchGoogleOAuth awaits canLaunchUrl/launchUrl before subscribing.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return f;
    }

    test('launches the backend OAuth URL and stores the session on success',
        () async {
      final f = await start();
      expect(launcher.launched.single, endsWith('/v1/api/auth/sso/google'));

      links.controller.add(_callback({
        'token': googleJwt,
        'user': Uri.encodeComponent(jsonEncode(_user())),
      }));
      final session = await f;

      expect(session.email, 'gap.user@example.test');
      expect(await AuthTokenManager.getJwtToken(), googleJwt);
      expect(await AuthService.getUserRole(), 'PATIENT');
      expect(await AuthService.isUserAuthenticated(), isTrue);
    });

    test('reports the error parameter from the callback', () async {
      final f = await start();
      final expectation = expectLater(
          f, throwsA(predicate((e) => e.toString().contains('access_denied'))));
      links.controller.add(_callback({'error': 'access_denied'}));
      await expectation;
      expect(await AuthTokenManager.getJwtToken(), isNull);
    });

    test('fails with the localized message when the token is missing',
        () async {
      final f = await start();
      final expectation = expectLater(
          f,
          throwsA(predicate(
              (e) => e.toString().contains(t.authservice_jwtTokenMissing))));
      links.controller.add(_callback({'user': '{}'}));
      await expectation;
    });

    test('fails with the localized message when user data is missing',
        () async {
      final f = await start();
      final expectation = expectLater(
          f,
          throwsA(predicate(
              (e) => e.toString().contains(t.authservice_userDataMissing))));
      links.controller.add(_callback({'token': 'abc'}));
      await expectation;
      expect(await AuthTokenManager.getJwtToken(), isNull);
    });

    test('fails when the user payload is not valid JSON', () async {
      final f = await start();
      final expectation = expectLater(f, throwsA(isA<FormatException>()));
      links.controller.add(_callback({'token': 'abc', 'user': 'not-json'}));
      await expectation;
    });

    test('propagates stream errors', () async {
      final f = await start();
      final expectation = expectLater(f, throwsA(isA<StateError>()));
      links.controller.addError(StateError('link stream broke'));
      await expectation;
    });

    test('throws when the OAuth URL cannot be launched', () async {
      UrlLauncherPlatform.instance = _FakeLauncher(canLaunch_: false);
      await expectLater(
        AuthService.loginWithGoogle(t),
        throwsA(predicate((e) => e.toString().contains('Could not launch'))),
      );
    });

    // Keep last: it runs inside fakeAsync, and AppLinks() caches the stream it
    // first subscribes to in that zone.
    test('times out with the localized message after five minutes', () {
      Object? error;
      fakeAsync((async) {
        AuthService.loginWithGoogle(t).then<void>((_) {}, onError: (Object e) {
          error = e;
        });
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 4, seconds: 59));
        expect(error, isNull, reason: 'must still be waiting before 5 min');
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
      });
      expect(error.toString(), contains(t.authservice_oauthTimedOut));
    });
  });

  group('processOAuthCallback', () {
    test('saves the token and returns the parsed session', () async {
      final s = await AuthService.processOAuthCallback(
        token: cbJwt,
        userDataString: Uri.encodeComponent(jsonEncode(_user())),
        t: t,
      );
      expect(s.id, 7);
      expect(await AuthTokenManager.getJwtToken(), cbJwt);
      expect(
          (await AuthService.getCurrentUser())?.email, 'gap.user@example.test');
    });
  });

  group('resetPassword', () {
    test('falls back to the localized failure text without error fields',
        () async {
      HttpOverrides.global = FakeHttpOverrides((m, u) {
        expect(u.path, endsWith('/reset-password'));
        return FakeResponse(400, '{}');
      });
      await expectLater(
        AuthService.resetPassword(
            email: 'a@example.test', resetToken: 'x', newPassword: 'pw', t: t),
        throwsA(predicate(
            (e) => e.toString().contains(t.authservice_passwordResetFailed))),
      );
    });
  });

  group('getAlexaAuthorizationCode', () {
    test('returns a network message when the socket fails', () async {
      HttpOverrides.global =
          FakeHttpOverrides((m, u) => throw const SocketException('offline'));
      final r = await AuthService.getAlexaAuthorizationCode(token: 'tk', t: t);
      expect(r['isSuccess'], isFalse);
      expect(r['code'], isNull);
      expect(r['message'], contains('offline'));
      expect(r['message'], startsWith(t.authservice_networkError));
    });

    test('returns a generic error payload for unexpected exceptions', () async {
      HttpOverrides.global =
          FakeHttpOverrides((m, u) => throw StateError('kaboom'));
      final r = await AuthService.getAlexaAuthorizationCode(token: 'tk', t: t);
      expect(r['isSuccess'], isFalse);
      expect(r['message'], contains('kaboom'));
    });

    test('sends the request to the Alexa code endpoint', () async {
      String? seen;
      HttpOverrides.global = FakeHttpOverrides((m, u) {
        seen = '$m ${u.path}';
        return FakeResponse(200, '{"code":"temp-1"}');
      });
      final r = await AuthService.getAlexaAuthorizationCode(token: 'tk', t: t);
      expect(seen, 'POST /v1/api/auth/sso/alexa/code');
      expect(r['code'], 'temp-1');
      expect(r['isSuccess'], isTrue);
    });
  });

  group('getCurrentUser', () {
    test('returns null when the stored session lacks required fields',
        () async {
      await AuthTokenManager.saveAuthData(
          jwtToken: 'tk', userSession: {'email': 'only@example.test'});
      expect(await AuthService.getCurrentUser(), isNull);
    });
  });

  group('checkAndRedirectIfUnauthenticated', () {
    Widget app(GoRouter router) => MaterialApp.router(routerConfig: router);

    testWidgets('redirects to the login route when signed out', (tester) async {
      bool? result;
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (c, s) => Scaffold(
            body: TextButton(
              onPressed: () async => result =
                  await AuthService.checkAndRedirectIfUnauthenticated(c,
                      loginRoute: '/signin'),
              child: const Text('guard'),
            ),
          ),
        ),
        GoRoute(path: '/signin', builder: (c, s) => const Text('Sign in page')),
      ]);
      await tester.pumpWidget(app(router));
      await tester.tap(find.text('guard'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(find.text('Sign in page'), findsOneWidget);
    });

    testWidgets('stays on the page when a valid session exists',
        (tester) async {
      await tester.runAsync(() => AuthTokenManager.saveAuthData(
          jwtToken: _jwt(), userSession: _user()));
      bool? result;
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (c, s) => Scaffold(
            body: TextButton(
              onPressed: () async => result =
                  await AuthService.checkAndRedirectIfUnauthenticated(c),
              child: const Text('guard'),
            ),
          ),
        ),
        GoRoute(path: '/login', builder: (c, s) => const Text('Login page')),
      ]);
      await tester.pumpWidget(app(router));
      await tester.tap(find.text('guard'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(find.text('Login page'), findsNothing);
    });
  });
}
