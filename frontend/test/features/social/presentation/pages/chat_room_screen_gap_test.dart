// Gap tests for ChatRoomScreen
// (lib/features/social/presentation/pages/chat_room_screen.dart): caregiver
// permission edge cases, the blocked-attachment snackbar, a denied camera and
// a failing voice recorder. The REST side is a MockClient behind ApiService;
// plugins are faked at their method channels. No network is used.

import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/features/social/presentation/pages/chat_room_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../mock_user_provider.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
const _connectivityStatus =
    MethodChannel('dev.fluttercommunity.plus/connectivity_status');
const _permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
const _imagePicker = MethodChannel('plugins.flutter.io/image_picker');
const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');
const _record = MethodChannel('com.llfbandit.record/messages');

Map<String, dynamic> _msg(int id, int from, String content, String ts) => {
      'id': id,
      'senderId': from,
      'receiverId': from == 1 ? 2 : 1,
      'content': content,
      'timestamp': ts,
    };

/// Canned REST backend behind ApiService.
class _Backend {
  bool messagingEnabled = true;
  bool linkMatchesPeer = true;
  int caregiverPatientsStatus = 200;
  String caregiverPatientsBody = '[]';
  List<Map<String, dynamic>> conversation = [
    _msg(10, 2, 'Hello from Alice', '2026-10-01T10:00:00Z'),
    _msg(11, 1, 'Hi Alice', '2026-10-01T10:01:00Z'),
  ];
  final List<String> calls = <String>[];

  Future<http.Response> handle(http.BaseRequest request) async {
    final path = request.url.path;
    calls.add('${request.method} $path');
    if (path.endsWith('/messages/conversation')) {
      return http.Response(jsonEncode(conversation), 200);
    }
    if (path.endsWith('/messages/send')) {
      return http.Response('{}', 200);
    }
    if (path.contains('/caregiver-patient-links/patients/')) {
      return http.Response(
        jsonEncode([
          {
            'caregiverUserId': linkMatchesPeer ? 2 : 99,
            'patientMessagingEnabled': messagingEnabled,
          },
        ]),
        200,
      );
    }
    if (path.contains('/caregivers/') && path.endsWith('/patients')) {
      return http.Response(caregiverPatientsBody, caregiverPatientsStatus);
    }
    return http.Response('{}', 404);
  }
}

bool _withToken = false;
int _permissionStatus = 1;
bool _recorderFails = false;

void _mock(MethodChannel channel, Future<Object?> Function(MethodCall) h) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, h);
}

Future<void> _settle(WidgetTester tester, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<_Backend> _pump(
  WidgetTester tester, {
  String role = 'PATIENT',
  int? caregiverId,
  _Backend? backend,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final b = backend ?? _Backend();
  final client = MockClient(b.handle);
  ApiService.debugSetHttpClient(client);
  addTearDown(ApiService.debugResetHttpClient);

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) =>
            const ChatRoomScreen(peerUserId: 2, peerName: 'Alice'),
      ),
    ],
  );
  addTearDown(router.dispose);

  await http.runWithClient(() async {
    await tester.pumpWidget(
      ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(
          mockUser: MockUser(id: 1, role: role, caregiverId: caregiverId),
        ),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _settle(tester);
  }, () => client);
  return b;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _withToken = false;
    _permissionStatus = 1;
    _recorderFails = false;
    _mock(_secureStorage, (call) async {
      final key = (call.arguments as Map?)?['key'];
      if (call.method == 'read' && _withToken) {
        if (key == 'jwt_token') return 'test-token';
        if (key == 'token_expiry') return '9999999999';
      }
      if (call.method == 'readAll') return <String, String>{};
      if (call.method == 'containsKey') return false;
      return null;
    });
    _mock(_connectivity,
        (call) async => call.method == 'check' ? ['wifi'] : null);
    _mock(_connectivityStatus, (call) async => null);
    _mock(_permissions, (call) async {
      if (call.method == 'requestPermissions') {
        final list = (call.arguments as List).cast<int>();
        return {for (final p in list) p: _permissionStatus};
      }
      return _permissionStatus;
    });
    _mock(_imagePicker, (call) async => null);
    _mock(_pathProvider, (call) async => Directory.systemTemp.path);
    _mock(_record, (call) async {
      if (call.method == 'start' && _recorderFails) {
        throw PlatformException(code: 'record', message: 'no microphone');
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .allMessagesHandler = (channel, handler, message) {
      if (channel.startsWith('com.llfbandit.record/events/')) {
        return Future<ByteData?>.value(
            const StandardMethodCodec().encodeSuccessEnvelope(null));
      }
      if (handler == null) return null;
      return handler(message);
    };
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger.allMessagesHandler = null;
    for (final c in [
      _secureStorage,
      _connectivity,
      _connectivityStatus,
      _permissions,
      _imagePicker,
      _pathProvider,
      _record,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, null);
    }
  });

  group('messaging permission', () {
    testWidgets('a patient without a matching caregiver link keeps messaging',
        (tester) async {
      final b = _Backend()..linkMatchesPeer = false;
      await _pump(tester, backend: b);
      expect(find.textContaining('Messaging is disabled'), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled,
          isNot(false));
    });

    for (final scenario in {
      'an empty patient list': (200, '[]'),
      'a failed lookup': (500, '{}'),
      'a malformed payload': (200, '{"not":"a list"}'),
      'a link for another patient': (
        200,
        jsonEncode([
          {
            'link': {'patientUserId': 77, 'patientMessagingEnabled': false},
          },
        ]),
      ),
    }.entries) {
      testWidgets('a caregiver keeps messaging after ${scenario.key}',
          (tester) async {
        final b = _Backend()
          ..caregiverPatientsStatus = scenario.value.$1
          ..caregiverPatientsBody = scenario.value.$2;
        await _pump(tester, role: 'CAREGIVER', caregiverId: 7, backend: b);
        // The lookup was attempted but could not disable messaging.
        expect(
          b.calls.where((c) => c.contains('/caregivers/7/patients')),
          isNotEmpty,
        );
        expect(find.textContaining('Messaging is disabled'), findsNothing);
      });
    }

    testWidgets('a blocked contact cannot be sent attachments', (tester) async {
      final b = _Backend()..messagingEnabled = false;
      await _pump(tester, backend: b);
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text(
          'Messaging is disabled by your caregiver for this conversation.',
        ),
        findsWidgets,
      );
      expect(find.text('Camera / Photo Library'), findsNothing);
    });
  });

  group('attachments', () {
    testWidgets('a denied camera explains how to enable it', (tester) async {
      _withToken = true;
      await _pump(tester);
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Camera / Photo Library'));
      await _settle(tester);
      await tester.pumpAndSettle();
      _permissionStatus = 4; // permanently denied from here on
      await tester.tap(find.text('Camera'));
      await _settle(tester, 10);
      expect(find.textContaining('Camera permission denied'), findsOneWidget);
    });

    testWidgets('a recorder that cannot start closes the dialog',
        (tester) async {
      _recorderFails = true;
      await _pump(tester);
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Audio Recording'));
      await _settle(tester, 10);
      await tester.pumpAndSettle();
      expect(find.text('Recording'), findsNothing);
      expect(find.text('Hello from Alice'), findsOneWidget);
    });
  });
}
