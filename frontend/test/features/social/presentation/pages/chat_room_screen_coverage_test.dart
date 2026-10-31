// Additional coverage for ChatRoomScreen
// (lib/features/social/presentation/pages/chat_room_screen.dart):
// signed-out state, periodic permission refresh, caregiver and patient link edge cases, camera
// permission denial, download write failures, recorder start failure and
// conversation load errors. Backend and plugins are faked as in
// chat_room_screen_flow_test.dart.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/social/presentation/pages/chat_room_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';

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

// permission_handler codes.
const _permCamera = 1;
const _granted = 1;
const _permanentlyDenied = 4;

final _conversation = [
  {
    'id': 10,
    'senderId': 2,
    'receiverId': 1,
    'content': 'Hello from Alice',
    'timestamp': '2026-10-01T10:00:00Z',
  },
  {
    'id': 14,
    'senderId': 2,
    'receiverId': 1,
    'content': '',
    'timestamp': '2026-10-01T10:04:00Z',
    'attachmentId': 102,
    'attachmentName': 'report.pdf',
    'attachmentContentType': 'application/pdf',
    'attachmentSize': 2048,
  },
];

/// Canned backend behind ApiService and package:http.
class _Backend {
  /// Body for the patient -> caregiver link lookup.
  Object patientLinks = [
    {'caregiverUserId': '2', 'patientMessagingEnabled': 'false'},
  ];

  /// Status / body for the caregiver -> patients lookup.
  int caregiverPatientsStatus = 200;
  Object caregiverPatients = const [];

  int downloadStatus = 200;
  final List<String> calls = <String>[];

  Future<http.Response> handle(http.BaseRequest request) async {
    final path = request.url.path;
    calls.add('${request.method} $path');
    if (path.endsWith('/messages/conversation')) {
      return http.Response(jsonEncode(_conversation), 200);
    }
    if (path.endsWith('/messages/send')) {
      return http.Response('{}', 200);
    }
    if (path.endsWith('/messages/send-attachment')) {
      return http.Response('{}', 200);
    }
    if (path.contains('/caregiver-patient-links/patients/')) {
      return http.Response(jsonEncode(patientLinks), 200);
    }
    if (path.contains('/caregivers/') && path.endsWith('/patients')) {
      return http.Response(
        jsonEncode(caregiverPatients),
        caregiverPatientsStatus,
      );
    }
    if (path.endsWith('/download')) {
      return http.Response.bytes([1, 2, 3], downloadStatus);
    }
    return http.Response('{}', 404);
  }
}

late Directory _tmp;
bool _withToken = false;
int _cameraStatus = _granted;
String? _tempDirOverride;
bool _recordStartFails = false;

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
        builder: (_, __) => const ChatRoomScreen(
          peerUserId: 2,
          peerName: 'Alice',
        ),
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

Future<void> _withHttp(_Backend b, Future<void> Function() body) =>
    http.runWithClient(body, () => MockClient(b.handle));

/// A UserProvider with no signed-in user.
class _SignedOutProvider extends MockUserProvider {
  @override
  UserSession? get user => null;
}

void main() {
  setUpAll(() {
    _tmp = Directory.systemTemp.createTempSync('chat_room_cov_');
    File('${_tmp.path}/photo.jpg').writeAsBytesSync([1, 2, 3, 4]);
  });

  tearDownAll(() {
    try {
      _tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _withToken = false;
    _cameraStatus = _granted;
    _tempDirOverride = null;
    _recordStartFails = false;
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
      int statusFor(int p) => p == _permCamera ? _cameraStatus : _granted;
      if (call.method == 'requestPermissions') {
        final list = (call.arguments as List).cast<int>();
        return {for (final p in list) p: statusFor(p)};
      }
      if (call.method == 'checkPermissionStatus') {
        return statusFor(call.arguments as int);
      }
      return _granted;
    });
    _mock(_imagePicker, (call) async => '${_tmp.path}/photo.jpg');
    _mock(_pathProvider, (call) async => _tempDirOverride ?? _tmp.path);
    _mock(_record, (call) async {
      if (call.method == 'start' && _recordStartFails) {
        throw PlatformException(code: 'record', message: 'mic busy');
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

  testWidgets('signed-out user triggers the not-logged-in notice',
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<UserProvider>.value(
        value: _SignedOutProvider(),
        child: const MaterialApp(
          home: Scaffold(
            body: ChatRoomScreen(peerUserId: 2, peerName: 'Alice'),
          ),
        ),
      ),
    );
    // The screen tries to show a 'User not logged in' snackbar while its
    // dependencies are first resolved (inside the build phase), which the
    // framework rejects; the screen never initialises a chat session.
    final error = tester.takeException();
    expect(error, isA<FlutterError>());
    expect(error.toString(), contains('showSnackBar'));
  });

  testWidgets('patient link with string ids disables messaging',
      (tester) async {
    final b = await _pump(tester);
    // Patient link with string ids disables messaging.
    expect(
      find.text(
          'Messaging is disabled by your caregiver for this conversation.'),
      findsOneWidget,
    );
    expect(b.calls.any((c) => c.contains('/caregiver-patient-links/')), isTrue);
  });

  testWidgets('messaging permission is refreshed periodically', (tester) async {
    final b = _Backend()
      ..patientLinks = [
        {'caregiverUserId': 99, 'patientMessagingEnabled': false},
      ];
    await _pump(tester, backend: b);
    final before =
        b.calls.where((c) => c.contains('/caregiver-patient-links/')).length;
    await _withHttp(b, () async {
      await tester.pump(const Duration(seconds: 5));
      await _settle(tester);
    });
    final after =
        b.calls.where((c) => c.contains('/caregiver-patient-links/')).length;
    expect(after, greaterThan(before));
    // No matching link: messaging stays enabled.
    expect(find.text('Messaging disabled'), findsNothing);
  });

  group('caregiver link lookup edge cases keep messaging enabled', () {
    final cases = <String, _Backend Function()>{
      'non-200': () => _Backend()..caregiverPatientsStatus = 500,
      'non-list payload': () => _Backend()..caregiverPatients = {'x': 1},
      'empty list': () => _Backend()..caregiverPatients = const [],
      'no matching patient': () => _Backend()
        ..caregiverPatients = [
          {
            'link': {'patientUserId': '77', 'patientMessagingEnabled': false},
          },
        ],
    };
    cases.forEach((name, make) {
      testWidgets(name, (tester) async {
        final b = make();
        await _pump(tester, role: 'CAREGIVER', caregiverId: 7, backend: b);
        expect(
            b.calls.any((c) => c.endsWith('/caregivers/7/patients')), isTrue);
        expect(find.text('Messaging is disabled for this patient link.'),
            findsNothing);
      });
    });

    testWidgets('string patient id match disables messaging', (tester) async {
      final b = _Backend()
        ..caregiverPatients = [
          {
            'link': {'patientUserId': '2', 'patientMessagingEnabled': 'false'},
          },
        ];
      await _pump(tester, role: 'CAREGIVER', caregiverId: 7, backend: b);
      expect(find.text('Messaging is disabled for this patient link.'),
          findsOneWidget);
    });
  });

  testWidgets('permanently denied camera points to Settings', (tester) async {
    _cameraStatus = _permanentlyDenied;
    final b = _Backend()
      ..patientLinks = [
        {'caregiverUserId': 2, 'patientMessagingEnabled': true},
      ];
    await _pump(tester, backend: b);
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camera / Photo Library'));
    await _settle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camera'));
    await _settle(tester);
    expect(find.textContaining('Camera permission denied'), findsOneWidget);
    expect(b.calls, isNot(contains('POST /v1/api/messages/send-attachment')));
  });

  testWidgets('download that cannot be saved reports the error',
      (tester) async {
    _tempDirOverride = '${_tmp.path}/missing/dir';
    final b = await _pump(tester);
    // Provide the token only after start-up so no chat socket is opened.
    _withToken = true;
    await _withHttp(b, () async {
      await tester.tap(find.text('report.pdf'));
      await _settle(tester, 10);
      // The failing file write is real I/O; give it time on slow machines.
      final error = find.textContaining('Could not open attachment');
      for (var i = 0; i < 100 && !tester.any(error); i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 20));
      }
    });
    expect(b.calls, contains('GET /v1/api/files/102/download'));
    expect(find.textContaining('Could not open attachment'), findsOneWidget);
  });

  testWidgets('recorder start failure closes the recording dialog',
      (tester) async {
    _recordStartFails = true;
    final b = _Backend()
      ..patientLinks = [
        {'caregiverUserId': 2, 'patientMessagingEnabled': true},
      ];
    await _pump(tester, backend: b);
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audio Recording'));
    await _settle(tester, 10);
    await tester.pumpAndSettle();
    expect(find.text('Recording'), findsNothing);
    expect(b.calls, isNot(contains('POST /v1/api/messages/send-attachment')));
  });

  testWidgets('initial conversation load failure shows a snackbar',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final b = _Backend();
    ApiService.debugSetHttpClient(MockClient(b.handle));
    addTearDown(ApiService.debugResetHttpClient);
    await tester.pumpWidget(
      ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(mockUser: MockUser(id: 1)),
        child: MaterialApp(
          home: ChatRoomScreen(
            peerUserId: 2,
            peerName: 'Alice',
            conversationLoader: ({required user1, required user2}) async =>
                throw Exception('boom'),
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(find.textContaining('Failed to load conversation'), findsOneWidget);
    // Replace the tree so periodic timers are cancelled by dispose.
    await tester.pumpWidget(const SizedBox());
  });
}
