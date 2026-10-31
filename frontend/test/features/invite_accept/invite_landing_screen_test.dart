// Tests for InviteLandingScreen
// (lib/features/invite_accept/invite_landing_screen.dart).
// InviteAcceptService uses package:http top-level calls, so bodies run
// inside http.runWithClient with a MockClient.

import 'dart:convert';

import 'package:care_connect_app/features/invite_accept/invite_landing_screen.dart';
import 'package:care_connect_app/features/invite_accept/services/pending_invite.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mock_user_provider.dart';

final Map<String, String> _secure = {};

void _channels() {
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      final args = (call.arguments as Map?) ?? const {};
      switch (call.method) {
        case 'read':
          return _secure[args['key']];
        case 'write':
          _secure[args['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          _secure.remove(args['key']);
          return null;
        case 'readAll':
          return Map<String, String>.from(_secure);
        case 'containsKey':
          return _secure.containsKey(args['key']);
      }
      return null;
    },
  );
}

void _signIn() {
  _secure['jwt_token'] = 'jwt';
  _secure['token_expiry'] =
      '${DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000}';
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(initialLocation: '/invite/tok', routes: [
    GoRoute(path: '/', builder: (_, __) => const Text('route:/')),
    GoRoute(
      path: '/invite/:token',
      builder: (_, s) =>
          InviteLandingScreen(token: s.pathParameters['token']!),
    ),
    GoRoute(path: '/login', builder: (_, __) => const Text('route:/login')),
    GoRoute(path: '/signup', builder: (_, __) => const Text('route:/signup')),
  ]);
  await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
    value: MockUserProvider(),
    child: MaterialApp.router(routerConfig: router),
  ));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 500));
}

String _preview({
  bool valid = true,
  String status = 'VALID',
  String nextAction = 'ACCEPT',
}) =>
    jsonEncode({
      'valid': valid,
      'status': status,
      'nextAction': nextAction,
      'inviterName': 'Jane Doe',
      'patientName': 'John Smith',
      'inviteReason': 'Help with Dad',
      'expiresAt': '2026-12-01T12:00:00Z',
    });

void main() {
  setUp(() {
    _secure.clear();
    PendingInvite.clear();
    _channels();
  });
  tearDown(PendingInvite.clear);

  testWidgets('signed-in user accepts and joins, then goes to dashboard',
      (tester) async {
    _signIn();
    final client = MockClient((req) async {
      if (req.method == 'POST') {
        return http.Response(jsonEncode({'linkId': 5}), 200);
      }
      return http.Response(_preview(), 200);
    });
    await http.runWithClient(() async {
      await _pump(tester);
      await _settle(tester);
      expect(find.text("You're invited"), findsOneWidget);
      expect(find.textContaining('Jane Doe has invited you'), findsOneWidget);
      expect(find.textContaining('Expires 2026-12-0'), findsOneWidget);
      await tester.tap(find.text('Accept invitation'));
      await _settle(tester);
      expect(find.text('Welcome aboard!'), findsOneWidget);
      await tester.tap(find.text('Go to dashboard'));
      await _settle(tester);
    }, () => client);
    // No stored user data, so navigation falls through to login.
    expect(find.text('route:/login'), findsOneWidget);
  });

  testWidgets('signed-out user is sent to sign-up with token stashed',
      (tester) async {
    final client = MockClient((req) async => http.Response(_preview(), 200));
    await http.runWithClient(() async {
      await _pump(tester);
      await _settle(tester);
      await tester.tap(find.text('Accept invitation'));
      await _settle(tester);
    }, () => client);
    expect(PendingInvite.token, 'tok');
    expect(find.text('route:/signup'), findsOneWidget);
  });

  testWidgets('SIGN_IN next action sends a signed-out user to login',
      (tester) async {
    final client = MockClient(
        (req) async => http.Response(_preview(nextAction: 'SIGN_IN'), 200));
    await http.runWithClient(() async {
      await _pump(tester);
      await _settle(tester);
      await tester.tap(find.text('Accept invitation'));
      await _settle(tester);
    }, () => client);
    expect(find.text('route:/login'), findsOneWidget);
  });

  testWidgets('not now returns home', (tester) async {
    final client = MockClient((req) async => http.Response(_preview(), 200));
    await http.runWithClient(() async {
      await _pump(tester);
      await _settle(tester);
      await tester.tap(find.text('Not now'));
      await _settle(tester);
    }, () => client);
    expect(find.text('route:/'), findsOneWidget);
  });

  for (final c in [
    ('EXPIRED', 'has expired', 'REQUEST_NEW', 'Close'),
    ('REVOKED', 'been revoked', 'REQUEST_NEW', 'Close'),
    ('ACCEPTED', 'already been accepted', 'SIGN_IN', 'Sign in'),
    ('INVALID', 'not valid', 'REQUEST_NEW', 'Close'),
  ]) {
    testWidgets('unavailable invite ${c.$1} shows message and action',
        (tester) async {
      final client = MockClient((req) async => http.Response(
          _preview(valid: false, status: c.$1, nextAction: c.$3), 200));
      await http.runWithClient(() async {
        await _pump(tester);
        await _settle(tester);
        expect(find.text('Invitation unavailable'), findsOneWidget);
        expect(find.textContaining(c.$2), findsOneWidget);
        await tester.tap(find.text(c.$4));
        await _settle(tester);
      }, () => client);
      expect(find.text(c.$4 == 'Sign in' ? 'route:/login' : 'route:/'),
          findsOneWidget);
    });
  }

  testWidgets('preview error shows problem and retry reloads', (tester) async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (calls == 1) return http.Response('', 500);
      if (calls == 2) throw Exception('down');
      return http.Response('not json', 200);
    });
    await http.runWithClient(() async {
      await _pump(tester);
      await _settle(tester);
      expect(find.text('Invitation problem'), findsOneWidget);
      expect(find.textContaining('error 500'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(find.textContaining('Could not reach the server'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(find.text('Something went wrong loading this invitation.'),
          findsOneWidget);
    }, () => client);
  });

  for (final c in [
    (401, 'Please sign in'),
    (403, 'different account'),
    (409, 'already been accepted'),
    (410, 'expired or been revoked'),
    (500, 'error 500'),
  ]) {
    testWidgets('accept ${c.$1} shows failure', (tester) async {
      _signIn();
      final client = MockClient((req) async {
        if (req.method == 'POST') return http.Response('', c.$1);
        return http.Response(_preview(), 200);
      });
      await http.runWithClient(() async {
        await _pump(tester);
        await _settle(tester);
        await tester.tap(find.text('Accept invitation'));
        await _settle(tester);
      }, () => client);
      expect(find.text('Invitation problem'), findsOneWidget);
      expect(find.textContaining(c.$2), findsOneWidget);
    });
  }

  testWidgets('accept network failure and bad body show failure',
      (tester) async {
    _signIn();
    var posts = 0;
    final client = MockClient((req) async {
      if (req.method == 'POST') {
        posts++;
        if (posts == 1) throw Exception('down');
        return http.Response('[]', 200);
      }
      return http.Response(_preview(), 200);
    });
    await http.runWithClient(() async {
      await _pump(tester);
      await _settle(tester);
      await tester.tap(find.text('Accept invitation'));
      await _settle(tester);
      expect(find.textContaining('Could not reach the server'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      await tester.tap(find.text('Accept invitation'));
      await _settle(tester);
      expect(find.text('Something went wrong accepting this invitation.'),
          findsOneWidget);
    }, () => client);
  });
}
