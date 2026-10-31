// Coverage for AuthService.loginWithGoogle (deep-link OAuth callback flow)
// and checkAndRedirectIfUnauthenticated. The app_links event channel and
// url_launcher channels are mocked (app links via a fake platform
// instance); the 5-minute OAuth timeout timer is
// driven with fake time via tester.pump.

import 'dart:async';
import 'dart:convert';

// ignore: depend_on_referenced_packages
import 'package:app_links_platform_interface/app_links_platform_interface.dart';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _urlChannels = [
  'plugins.flutter.io/url_launcher',
  'plugins.flutter.io/url_launcher_android',
  'plugins.flutter.io/url_launcher_ios',
  'plugins.flutter.io/url_launcher_linux',
  'plugins.flutter.io/url_launcher_macos',
  'plugins.flutter.io/url_launcher_windows',
];

/// Link delivered when the OAuth flow subscribes; null = nothing arrives.
String? _link;
Object? _linkError;

/// Fake app_links platform: every subscription gets a fresh stream that
/// emits the configured link or error once listened to.
class _FakeAppLinksPlatform extends AppLinksPlatform {
  @override
  Stream<Uri> get uriLinkStream {
    late StreamController<Uri> controller;
    controller = StreamController<Uri>(onListen: () {
      if (_linkError != null) {
        controller.addError(_linkError!);
      } else if (_link != null) {
        controller.add(Uri.parse(_link!));
      }
    });
    return controller.stream;
  }

  @override
  Stream<String> get stringLinkStream => const Stream.empty();
}

void main() {
  final t = lookupAppLocalizations(const Locale('en'));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    _link = null;
    _linkError = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in _urlChannels) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        if (call.method == 'canLaunch') return true;
        return true;
      });
    }
    AppLinksPlatform.instance = _FakeAppLinksPlatform();
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in _urlChannels) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  });

  /// Starts the login, delivers the mocked link, then advances past the
  /// 5-minute timeout so no timer is left pending.
  Future<(UserSession?, Object?)> runLogin(WidgetTester tester) async {
    UserSession? session;
    Object? error;
    var done = false;
    AuthService.loginWithGoogle(t).then((s) {
      session = s;
      done = true;
    }, onError: (Object e) {
      error = e;
      done = true;
    });
    for (var i = 0; i < 20 && !done; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await tester.pump(const Duration(minutes: 5, seconds: 1));
    for (var i = 0; i < 5 && !done; i++) {
      await tester.pump();
    }
    return (session, error);
  }

  testWidgets('successful callback returns the session', (tester) async {
    final user = Uri.encodeComponent(jsonEncode({
      'id': 12,
      'email': 'g@x.com',
      'role': 'PATIENT',
      'name': 'Gee',
      'token': 'oauth-jwt',
    }));
    _link = 'careconnect://oauth/callback?token=oauth-jwt&user=$user';

    final (session, error) = await runLogin(tester);
    expect(error, isNull);
    expect(session?.id, 12);
    expect(session?.email, 'g@x.com');
  });

  testWidgets('error parameter fails the login', (tester) async {
    _link = 'careconnect://oauth/callback?error=access_denied';
    final (_, error) = await runLogin(tester);
    expect(error.toString(), contains('access_denied'));
  });

  testWidgets('missing token fails the login', (tester) async {
    _link = 'careconnect://oauth/callback?user=x';
    final (_, error) = await runLogin(tester);
    expect(error.toString(), contains(t.authservice_jwtTokenMissing));
  });

  testWidgets('missing user data fails the login', (tester) async {
    _link = 'careconnect://oauth/callback?token=abc';
    final (_, error) = await runLogin(tester);
    expect(error.toString(), contains(t.authservice_userDataMissing));
  });

  testWidgets('malformed user data surfaces the decode error',
      (tester) async {
    _link = 'careconnect://oauth/callback?token=abc&user=not-json';
    final (session, error) = await runLogin(tester);
    expect(session, isNull);
    expect(error, isA<FormatException>());
  });

  testWidgets('link stream errors fail the login', (tester) async {
    _linkError = StateError('stream broke');
    final (_, error) = await runLogin(tester);
    expect(error, isA<StateError>());
  });

  testWidgets('no callback times out after five minutes', (tester) async {
    final (session, error) = await runLogin(tester);
    expect(session, isNull);
    expect(error.toString(), contains(t.authservice_oauthTimedOut));
  });

  testWidgets('checkAndRedirectIfUnauthenticated sends guests to login',
      (tester) async {
    late BuildContext homeContext;
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (c, s) {
          homeContext = c;
          return const Text('home');
        },
      ),
      GoRoute(path: '/login', builder: (c, s) => const Text('login page')),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    late bool result;
    await tester.runAsync(() async {
      result = await AuthService.checkAndRedirectIfUnauthenticated(homeContext);
    });
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(find.text('login page'), findsOneWidget);
  });
}
