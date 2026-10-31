// Tests for InviteQrScreen and InviteQrAutoloadScreen
// (lib/features/invite_share/invite_qr_screen.dart,
//  lib/features/invite_share/invite_qr_autoload_screen.dart).
// InviteService uses package:http top-level calls, so bodies run inside
// http.runWithClient with a MockClient.

import 'dart:convert';

import 'package:care_connect_app/features/invite_share/invite_qr_autoload_screen.dart';
import 'package:care_connect_app/features/invite_share/invite_qr_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';

bool _launchResult = true;
final List<String> _shared = [];
final List<String> _clipboard = [];

void _channels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'containsKey') return false;
      return null;
    },
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/share'),
    (call) async {
      _shared.add('${(call.arguments as Map)['text']}');
      return 'dev.fluttercommunity.plus/share/success';
    },
  );
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      _clipboard.add('${(call.arguments as Map)['text']}');
    }
    return null;
  });
  for (final name in [
    'plugins.flutter.io/url_launcher',
    'plugins.flutter.io/url_launcher_android',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
      if (call.method == 'canLaunch') return _launchResult;
      return _launchResult;
    });
  }
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => page),
    GoRoute(
      path: '/invite/:token',
      builder: (_, s) => Text('landing:${s.pathParameters['token']}'),
    ),
  ]);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 500));
}

String _inviteJson({String linkType = 'TEMPORARY', String? expiresAt}) =>
    jsonEncode({
      'tokenId': 1,
      'token': 'tok123',
      'inviteUrl': 'https://app.example.test/invite/tok123',
      'linkId': 4,
      'linkType': linkType,
      'status': 'ACTIVE',
      'expiresAt': expiresAt,
    });

void main() {
  setUp(() {
    _launchResult = true;
    _shared.clear();
    _clipboard.clear();
    _channels();
  });

  group('InviteQrScreen', () {
    testWidgets('renders QR, chips and supports copy/share/open',
        (tester) async {
      Map<String, dynamic>? body;
      final client = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
            _inviteJson(expiresAt: '2026-11-01T10:30:00Z'), 201);
      });
      await http.runWithClient(() async {
        await _pump(
            tester,
            const InviteQrScreen(
              linkId: 4,
              invitedEmail: 'kin@example.test',
              inviteReason: 'Help with Mom',
            ));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await _settle(tester);

        expect(find.byType(QrImageView), findsOneWidget);
        expect(find.text('Temporary link'), findsOneWidget);
        expect(find.textContaining('Expires 2026-11-0'), findsOneWidget);

        await tester.tap(find.byTooltip('Copy link'));
        await _settle(tester);
        expect(find.text('Invite link copied to clipboard'), findsOneWidget);

        await tester.tap(find.text('Share invite'));
        await _settle(tester);

        await tester.tap(find.text('Open link'));
        await _settle(tester);
      }, () => client);
      expect(body?['invitedEmail'], 'kin@example.test');
      expect(body?['inviteReason'], 'Help with Mom');
      expect(_clipboard.single, 'https://app.example.test/invite/tok123');
      expect(_shared.single, contains('Help with Mom'));
    });

    testWidgets('open link falls back to the local landing route',
        (tester) async {
      _launchResult = false;
      final client = MockClient(
          (req) async => http.Response(_inviteJson(linkType: 'PERMANENT'), 200));
      await http.runWithClient(() async {
        await _pump(tester, const InviteQrScreen(linkId: 4));
        await _settle(tester);
        expect(find.text('Permanent link'), findsOneWidget);
        expect(find.text('No expiration'), findsOneWidget);
        await tester.tap(find.text('Copy link').last);
        await _settle(tester);
        await tester.tap(find.text('Share invite'));
        await _settle(tester);
        await tester.tap(find.text('Open link'));
        await _settle(tester);
      }, () => client);
      expect(find.text('landing:tok123'), findsOneWidget);
      expect(_shared.single, startsWith('Join my CareConnect care circle'));
    });

    testWidgets('emergency and unknown link types render labels',
        (tester) async {
      for (final type in ['EMERGENCY', 'CUSTOM']) {
        final client = MockClient(
            (req) async => http.Response(_inviteJson(linkType: type), 200));
        await http.runWithClient(() async {
          await _pump(tester, InviteQrScreen(key: ValueKey(type), linkId: 4));
          await _settle(tester);
        }, () => client);
        expect(find.text(type == 'EMERGENCY' ? 'Emergency link' : 'CUSTOM'),
            findsOneWidget);
      }
    });

    testWidgets('error statuses show messages and retry', (tester) async {
      final statuses = [401, 403, 404, 409, 500];
      var i = 0;
      final client = MockClient((req) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response('', statuses[i++]);
      });
      await http.runWithClient(() async {
        await _pump(tester, const InviteQrScreen(linkId: 4));
        await _settle(tester);
        expect(find.textContaining('session has expired'), findsOneWidget);
        await tester.tap(find.text('Try again'));
        await _settle(tester);
        expect(find.textContaining('do not have permission'), findsOneWidget);
        await tester.tap(find.text('Try again'));
        await _settle(tester);
        expect(find.textContaining('could not be found'), findsOneWidget);
        await tester.tap(find.text('Try again'));
        await _settle(tester);
        expect(find.textContaining('already exists'), findsOneWidget);
        await tester.tap(find.text('Try again'));
        await _settle(tester);
        expect(find.textContaining('error 500'), findsOneWidget);
      }, () => client);
    });

    testWidgets('network failure and bad body show errors', (tester) async {
      final client = MockClient((req) async => throw Exception('down'));
      await http.runWithClient(() async {
        await _pump(tester, const InviteQrScreen(linkId: 4));
        await _settle(tester);
      }, () => client);
      expect(find.textContaining('Could not reach the server'), findsOneWidget);

      final bad = MockClient((req) async => http.Response('[]', 200));
      await http.runWithClient(() async {
        await _pump(tester, const InviteQrScreen(key: ValueKey('b'), linkId: 4));
        await _settle(tester);
      }, () => bad);
      expect(find.textContaining('Something went wrong generating'),
          findsOneWidget);
    });
  });

  group('InviteQrAutoloadScreen', () {
    testWidgets('resolves the active link id then shows the QR screen',
        (tester) async {
      final client = MockClient((req) async {
        if (req.method == 'GET') {
          return http.Response(
              jsonEncode([
                {'id': 3, 'status': 'REVOKED'},
                {'id': '8', 'status': 'ACTIVE'},
              ]),
              200);
        }
        expect(req.url.path, contains('/care-circle/8/invite'));
        return http.Response(_inviteJson(), 201);
      });
      await http.runWithClient(() async {
        await _pump(tester, const InviteQrAutoloadScreen());
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await _settle(tester);
        await _settle(tester);
      }, () => client);
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('error responses show the message and retry', (tester) async {
      final responses = <http.Response>[
        http.Response('', 401),
        http.Response('', 403),
        http.Response('', 500),
        http.Response('{}', 200),
        http.Response('[]', 200),
        http.Response(jsonEncode([
          {'status': 'ACTIVE', 'id': null}
        ]), 200),
      ];
      var i = 0;
      final client = MockClient((req) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return responses[i++];
      });
      final expected = [
        'session has expired',
        'available for patient accounts',
        'error 500',
        'could not be read',
        'No family-member link',
        'No usable care-circle link',
      ];
      await http.runWithClient(() async {
        await _pump(tester, const InviteQrAutoloadScreen());
        await _settle(tester);
        for (var k = 0; k < expected.length; k++) {
          expect(find.textContaining(expected[k]), findsOneWidget,
              reason: expected[k]);
          if (k < expected.length - 1) {
            await tester.tap(find.text('Try again'));
            await _settle(tester);
          }
        }
      }, () => client);
    });

    testWidgets('network failure shows connection message', (tester) async {
      final client = MockClient((req) async => throw Exception('down'));
      await http.runWithClient(() async {
        await _pump(tester, const InviteQrAutoloadScreen());
        await _settle(tester);
      }, () => client);
      expect(find.textContaining('Check your connection'), findsOneWidget);
    });
  });
}
