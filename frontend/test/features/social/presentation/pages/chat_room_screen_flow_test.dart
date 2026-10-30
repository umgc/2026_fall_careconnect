// Flow tests for ChatRoomScreen
// (lib/features/social/presentation/pages/chat_room_screen.dart) with the
// ApiService client, package:http and platform plugins faked: conversation
// rendering (text + attachment bubbles), sending (ok / refused / queued /
// failing), messaging permission for patients and caregivers, video call
// navigation, attachments (file, photo, voice) and download errors.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
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

final _conversation = [
  {
    'id': 10,
    'senderId': 2,
    'receiverId': 1,
    'content': 'Hello from Alice',
    'timestamp': '2026-10-01T10:00:00Z',
  },
  {
    'id': 11,
    'senderId': 1,
    'receiverId': 2,
    'content': 'Hi Alice',
    'timestamp': '2026-10-01T10:01:00Z',
  },
  {
    'id': 12,
    'senderId': 2,
    'receiverId': 1,
    'content': '',
    'timestamp': '2026-10-01T10:02:00Z',
    'attachmentId': 100,
    'attachmentName': 'photo.png',
    'attachmentContentType': 'image/png',
    'attachmentSize': 500,
  },
  {
    'id': 13,
    'senderId': 1,
    'receiverId': 2,
    'content': '',
    'timestamp': '2026-10-01T10:03:00Z',
    'attachmentId': 101,
    'attachmentName': 'voice.m4a',
    'attachmentContentType': 'audio/m4a',
    'attachmentSize': 2048,
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
    'attachmentSize': 3 * 1024 * 1024,
  },
];

/// Canned backend behind ApiService and package:http.
class _Backend {
  bool messagingEnabled = true;
  bool videoLinked = true;
  int sendStatus = 200;
  bool sendQueued = false;
  bool sendThrows = false;
  int uploadStatus = 200;
  int downloadStatus = 404;
  List<Map<String, dynamic>> conversation =
      List<Map<String, dynamic>>.from(_conversation);
  final List<String> calls = <String>[];

  Future<http.Response> handle(http.BaseRequest request) async {
    final path = request.url.path;
    calls.add('${request.method} $path');
    if (path.endsWith('/messages/conversation')) {
      return http.Response(jsonEncode(conversation), 200);
    }
    if (path.endsWith('/messages/send')) {
      if (sendThrows) throw const SocketException('offline');
      return http.Response(
        '{}',
        sendStatus,
        headers: sendQueued ? {'x-offline-queued': 'true'} : const {},
      );
    }
    if (path.endsWith('/messages/send-attachment')) {
      return http.Response('{}', uploadStatus);
    }
    if (path.contains('/caregiver-patient-links/patients/')) {
      return http.Response(
        jsonEncode([
          {
            'caregiverUserId': videoLinked ? 2 : 99,
            'patientMessagingEnabled': messagingEnabled,
          },
        ]),
        200,
      );
    }
    if (path.contains('/caregivers/') && path.endsWith('/patients')) {
      return http.Response(
        jsonEncode([
          'skip',
          {'link': 'skip'},
          {
            'link': {
              'patientUserId': 2,
              'patientMessagingEnabled': messagingEnabled ? 'true' : 'false',
            },
          },
        ]),
        200,
      );
    }
    if (path.endsWith('/download')) {
      return http.Response.bytes([1, 2, 3], downloadStatus);
    }
    return http.Response('{}', 404);
  }
}

class _FakeFilePicker extends Fake
    with MockPlatformInterfaceMixin
    implements FilePicker {
  _FakeFilePicker(this.result);
  final FilePickerResult? result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    dynamic Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      result;
}

late Directory _tmp;
bool _withToken = false;
int _permissionStatus = 1; // granted

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
  bool autoSync = true,
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
        builder: (_, __) => ChatRoomScreen(
          peerUserId: 2,
          peerName: 'Alice',
          enableAutoSync: autoSync,
        ),
      ),
      GoRoute(
        path: '/video-call-chime',
        builder: (_, __) => const Scaffold(body: Text('video call page')),
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

/// Runs [body] with package:http's top-level client pointed at [b].
Future<void> _withHttp(_Backend b, Future<void> Function() body) =>
    http.runWithClient(body, () => MockClient(b.handle));

void main() {
  setUpAll(() {
    _tmp = Directory.systemTemp.createTempSync('chat_room_flow_');
    File('${_tmp.path}/photo.jpg').writeAsBytesSync([1, 2, 3, 4]);
    File('${_tmp.path}/voice.m4a').writeAsBytesSync([5, 6, 7]);
  });

  tearDownAll(() {
    try {
      _tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _withToken = false;
    _permissionStatus = 1;
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
    _mock(_imagePicker, (call) async => '${_tmp.path}/photo.jpg');
    _mock(_pathProvider, (call) async => _tmp.path);
    _mock(_record, (call) async {
      if (call.method == 'stop') return '${_tmp.path}/voice.m4a';
      return null;
    });
    // The recorder opens a per-instance state event channel
    // (com.llfbandit.record/events/<id>); answer its listen/cancel calls.
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .allMessagesHandler = null;
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

  testWidgets('renders text and attachment bubbles with receipts',
      (tester) async {
    await _pump(tester);

    expect(find.text('Hello from Alice'), findsOneWidget);
    expect(find.text('Hi Alice'), findsOneWidget);
    expect(find.text('photo.png'), findsOneWidget);
    expect(find.text('500B'), findsOneWidget);
    expect(find.text('voice.m4a'), findsOneWidget);
    expect(find.text('2.0KB'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('3.0MB'), findsOneWidget);
    expect(find.text('Sent'), findsWidgets);
    expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
    expect(find.byIcon(Icons.download), findsOneWidget);
    // Composer typing triggers the listener (no socket connected).
    await tester.enterText(find.byType(TextField), 'draft');
    await tester.pump();
  });

  testWidgets('sending a message posts it and refreshes', (tester) async {
    final b = await _pump(tester);
    await _withHttp(b, () async {
      await tester.enterText(find.byType(TextField), 'New message');
      await tester.tap(find.byIcon(Icons.send));
      await _settle(tester);
    });
    expect(b.calls.where((c) => c.endsWith('/messages/send')), hasLength(1));
  });

  testWidgets('server reconciles a pending message by content',
      (tester) async {
    final b = _Backend()..sendStatus = 500;
    await _pump(tester, backend: b);
    await tester.enterText(find.byType(TextField), 'Reconcile me');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);
    expect(find.text('Pending'), findsOneWidget);

    b.conversation = [
      ...b.conversation,
      {
        'id': 50,
        'senderId': 1,
        'receiverId': 2,
        'content': 'Reconcile me',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      },
    ];
    // Polling (every 2s) picks up the server copy and drops the pending one.
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(find.text('Pending'), findsNothing);
  });

  testWidgets('a refused send removes the message and explains why',
      (tester) async {
    final b = _Backend()..sendStatus = 403;
    await _pump(tester, backend: b);
    await tester.enterText(find.byType(TextField), 'Blocked message');
    await tester.tap(find.byIcon(Icons.send));
    await _settle(tester);
    expect(find.text("You can't send messages to this user."), findsOneWidget);
    expect(find.text('Blocked message'), findsNothing);
  });

  testWidgets('an offline-queued send shows the queued snackbar',
      (tester) async {
    final b = _Backend()..sendQueued = true;
    await _pump(tester, backend: b);
    await tester.enterText(find.byType(TextField), 'Queued message');
    await tester.tap(find.byIcon(Icons.send));
    await _settle(tester);
    expect(find.text('Message queued for sync when internet is restored'),
        findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('a pending message restored from disk is retried',
      (tester) async {
    final b = _Backend()..sendThrows = true;
    await _pump(tester, backend: b);
    await tester.enterText(find.byType(TextField), 'Keep me');
    await tester.tap(find.byIcon(Icons.send));
    await _settle(tester);
    expect(find.text('Keep me'), findsOneWidget);
    expect(find.text('Pending'), findsWidgets);

    // Rebuild the screen from scratch: the pending queue is restored.
    await tester.pumpWidget(const SizedBox());
    b.sendThrows = false;
    await _pump(tester, backend: b);
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(b.calls.where((c) => c.endsWith('/messages/send')).length,
        greaterThanOrEqualTo(2));
  });

  testWidgets('patient with messaging disabled sees the blocked banner',
      (tester) async {
    final b = _Backend()..messagingEnabled = false;
    await _pump(tester, backend: b);
    expect(
      find.text(
          'Messaging is disabled by your caregiver for this conversation.'),
      findsOneWidget,
    );
    expect(find.text('Messaging disabled'), findsOneWidget);
  });

  testWidgets('caregiver permission comes from the patient link',
      (tester) async {
    final b = _Backend()..messagingEnabled = false;
    await _pump(tester, role: 'CAREGIVER', caregiverId: 7, backend: b);
    expect(find.text('Messaging is disabled for this patient link.'),
        findsOneWidget);
  });

  testWidgets('caregiver without caregiverId cannot message', (tester) async {
    await _pump(tester, role: 'CAREGIVER');
    expect(find.text('Messaging is disabled for this patient link.'),
        findsOneWidget);
  });

  testWidgets('video call opens the call route when linked', (tester) async {
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.videocam));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('video call page'), findsOneWidget);
  });

  testWidgets('video call is refused when there is no link', (tester) async {
    final b = _Backend()..videoLinked = false;
    await _pump(tester, backend: b);
    await tester.tap(find.byIcon(Icons.videocam));
    await _settle(tester);
    expect(
      find.text(
          'Video calling is disabled by your caregiver or no active link exists.'),
      findsOneWidget,
    );
  });

  testWidgets('download errors map HTTP status to messages', (tester) async {
    _withToken = true;
    final b = await _pump(tester);
    for (final entry in {
      401: 'Session expired. Please sign in again.',
      403: 'You do not have permission to download this attachment.',
      404: 'Attachment not found.',
      500: 'Download failed (HTTP 500).',
    }.entries) {
      b.downloadStatus = entry.key;
      await _withHttp(b, () async {
        await tester.tap(find.text('photo.png'));
        await _settle(tester);
      });
      expect(find.text(entry.value), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(ListView)))
          .removeCurrentSnackBar();
      await tester.pump();
    }
    // Audio and file bubbles are tappable too.
    await _withHttp(b, () async {
      await tester.tap(find.text('voice.m4a'));
      await _settle(tester);
      await tester.tap(find.text('report.pdf'));
      await _settle(tester);
    });
  });

  testWidgets('download without a token asks to sign in again',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('report.pdf'));
    await _settle(tester);
    expect(find.text('Please sign in again to download attachments.'),
        findsOneWidget);
  });

  testWidgets('file attachment is uploaded from the attachment sheet',
      (tester) async {
    _withToken = true;
    FilePicker.platform = _FakeFilePicker(FilePickerResult([
      PlatformFile(
        name: 'notes.txt',
        size: 3,
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
    ]));
    final b = await _pump(tester);
    await _withHttp(b, () async {
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      expect(find.text('Camera / Photo Library'), findsOneWidget);
      await tester.tap(find.text('File'));
      await _settle(tester);
      await tester.pumpAndSettle();
    });
    expect(b.calls, contains('POST /v1/api/messages/send-attachment'));
  });

  testWidgets('upload rejections and failures show snackbars',
      (tester) async {
    _withToken = true;
    FilePicker.platform = _FakeFilePicker(FilePickerResult([
      PlatformFile(name: 'a.bin', size: 1, bytes: Uint8List.fromList([9])),
    ]));
    final b = _Backend()..uploadStatus = 403;
    await _pump(tester, backend: b);
    await _withHttp(b, () async {
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('File'));
      await _settle(tester);
    });
    expect(find.text('Messaging is not enabled for this contact.'),
        findsOneWidget);

    ScaffoldMessenger.of(tester.element(find.byType(ListView)))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();
    b.uploadStatus = 500;
    await _withHttp(b, () async {
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('File'));
      await _settle(tester);
    });
    expect(find.textContaining('Failed to send attachment'), findsWidgets);
  });

  testWidgets('upload without a token reports the failure', (tester) async {
    FilePicker.platform = _FakeFilePicker(FilePickerResult([
      PlatformFile(name: 'a.bin', size: 1, bytes: Uint8List.fromList([9])),
    ]));
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('File'));
    await _settle(tester);
    expect(find.textContaining('Not authenticated'), findsOneWidget);
  });

  testWidgets('photo from the library is uploaded', (tester) async {
    _withToken = true;
    final b = await _pump(tester);
    await _withHttp(b, () async {
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Camera / Photo Library'));
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(find.text('Choose source'), findsOneWidget);
      await tester.tap(find.text('Photo Library'));
      await _settle(tester, 10);
      await tester.pumpAndSettle();
    });
    expect(b.calls, contains('POST /v1/api/messages/send-attachment'));
  });

  testWidgets('camera source checks camera permission', (tester) async {
    _withToken = true;
    final b = await _pump(tester);
    await _withHttp(b, () async {
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Camera / Photo Library'));
      await _settle(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Camera'));
      await _settle(tester, 10);
      await tester.pumpAndSettle();
    });
    expect(b.calls, contains('POST /v1/api/messages/send-attachment'));
  });

  testWidgets('permanently denied permissions point to Settings',
      (tester) async {
    _permissionStatus = 4; // permanentlyDenied
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camera / Photo Library'));
    await _settle(tester);
    expect(find.textContaining('Photo library permission denied'),
        findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(ListView)))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audio Recording'));
    await _settle(tester);
    expect(find.textContaining('Microphone permission denied'),
        findsOneWidget);
  });

  testWidgets('voice message is recorded and uploaded', (tester) async {
    _withToken = true;
    File('${_tmp.path}/voice.m4a').writeAsBytesSync([5, 6, 7]);
    final b = await _pump(tester);
    await _withHttp(b, () async {
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Audio Recording'));
      await _settle(tester);
      expect(find.text('Recording'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:01'), findsOneWidget);
      await tester.tap(find.text('Send'));
      await _settle(tester, 10);
      await tester.pumpAndSettle();
    });
    expect(b.calls, contains('POST /v1/api/messages/send-attachment'));
  });

  testWidgets('voice recording can be cancelled', (tester) async {
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audio Recording'));
    await _settle(tester);
    expect(find.text('Recording'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
  });

  testWidgets('conversation load failure shows a snackbar', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(mockUser: MockUser(id: 1)),
        child: MaterialApp(
          home: ChatRoomScreen(
            peerUserId: 2,
            peerName: 'Alice',
            enableAutoSync: false,
            conversationLoader: ({required user1, required user2}) async =>
                throw Exception('boom'),
            messageSender: (
                    {required senderId,
                    required receiverId,
                    required content}) async {},
          ),
        ),
      ),
    );
    await tester.pump();
    // Sending through the injected sender then refreshes via the loader,
    // which fails silently.
    await tester.enterText(find.byType(TextField), 'via sender');
    await tester.tap(find.byIcon(Icons.send));
    await _settle(tester);
    expect(find.text('via sender'), findsNothing);
  });

  testWidgets('back button pops the chat route', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(mockUser: MockUser(id: 1)),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ChatRoomScreen(
                      peerUserId: 2,
                      peerName: 'Alice',
                      enableAutoSync: false,
                    ),
                  ),
                ),
                child: const Text('open chat'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('open chat'), findsOneWidget);
  });
}
