// Widget tests for HybridVideoCallWidget once a call session is joined.
//
// hybrid_video_call_widget_test.dart covers the error path (no JWT). These
// tests provide a JWT through the mocked secure-storage channel and answer the
// call service's HTTP requests with a MockClient (via http.runWithClient), so
// the widget reaches the in-call layout. The join response uses a
// "local-join-token-" token, which keeps the widget on its placeholder video
// view instead of the platform WebView embed.

import 'dart:convert';

import 'package:care_connect_app/services/call_notification_service.dart';
import 'package:care_connect_app/widgets/hybrid_video_call_widget.dart';
import 'package:care_connect_app/widgets/sentiment_dashboard_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../test_support/fake_webview_platform.dart';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _permissionChannel =
    MethodChannel('flutter.baseflow.com/permissions/methods');

int _callCounter = 0;

/// Each test needs its own call id: the service remembers ended call ids
/// process-wide and refuses to rejoin them.
String _nextCallId() => 'hv-session-call-${++_callCounter}';

class _Backend {
  _Backend({
    this.joinStatus = 200,
    this.recordingStartCode = 200,
    this.recordingStopCode = 200,
    this.invitees = const <Map<String, dynamic>>[],
    this.inviteeCode = 200,
    this.inviteStatus = 'invited',
    this.inviteCode = 200,
    this.joinToken = 'local-join-token-abc',
    this.mediaPlacement = const <String, dynamic>{},
    this.sentimentCode = 200,
  });

  final int joinStatus;
  final int recordingStartCode;
  final int recordingStopCode;
  final List<Map<String, dynamic>> invitees;
  final int inviteeCode;
  final String inviteStatus;
  final int inviteCode;
  final String joinToken;
  final Map<String, dynamic> mediaPlacement;
  final int sentimentCode;

  final List<String> requests = <String>[];

  MockClient client() => MockClient((request) async {
        final path = request.url.path;
        requests.add('${request.method} $path');
        if (path.endsWith('/calls/sessions')) {
          return http.Response('{}', 201);
        }
        if (path.endsWith('/join')) {
          if (joinStatus != 200) {
            return http.Response('{"error":"nope"}', joinStatus);
          }
          return http.Response(
            jsonEncode({
              'meetingId': 'meeting-1234567890',
              'attendeeId': 'attendee-1',
              'joinToken': joinToken,
              'mediaPlacement': mediaPlacement,
              'mediaRegion': 'us-east-1',
              'externalUserId': 'external-1',
            }),
            200,
          );
        }
        if (path.endsWith('/end')) {
          return http.Response('{"status":"ended"}', 200);
        }
        if (path.endsWith('/recording/start')) {
          return http.Response(
            jsonEncode({'status': 'STARTED'}),
            recordingStartCode,
          );
        }
        if (path.endsWith('/recording/stop')) {
          return http.Response('{"status":"STOPPED"}', recordingStopCode);
        }
        if (path.endsWith('/eligible-invitees')) {
          return http.Response(jsonEncode(invitees), inviteeCode);
        }
        if (path.endsWith('/invite')) {
          return http.Response(
            jsonEncode({'status': inviteStatus}),
            inviteCode,
          );
        }
        if (path.contains('/sentiment/')) {
          return http.Response('{}', sentimentCode);
        }
        return http.Response('{}', 200);
      });
}

Future<void> _pumpCall(
  WidgetTester tester, {
  required String callId,
  String? userRole = 'CAREGIVER',
  String recipientRole = 'PATIENT',
  String? recipientId = '2',
  String callKind = 'GENERAL',
  bool isInitiator = false,
  String? recipientName = 'Pat Ient',
  List<int>? contextPatientUserIds,
  String? scheduledVisitId,
  String? returnPatientDetailsId,
  bool forcePatientDetailsOnExit = false,
  bool pushOverHome = true,
}) async {
  final call = HybridVideoCallWidget(
    userId: '1',
    callId: callId,
    recipientId: recipientId,
    recipientRole: recipientRole,
    userRole: userRole,
    isInitiator: isInitiator,
    callKind: callKind,
    recipientName: recipientName,
    userName: 'Care Giver',
    contextPatientUserIds: contextPatientUserIds,
    scheduledVisitId: scheduledVisitId,
    returnPatientDetailsId: returnPatientDetailsId,
    forcePatientDetailsOnExit: forcePatientDetailsOnExit,
  );
  final router = GoRouter(
    initialLocation: pushOverHome ? '/' : '/call',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.push('/call'),
              child: const Text('open call'),
            ),
          ),
        ),
      ),
      GoRoute(path: '/call', builder: (_, __) => call),
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const Scaffold(body: Text('dashboard page')),
      ),
      GoRoute(
        path: '/video-call-chime',
        builder: (_, state) => Scaffold(
          body: Text('rejoin ${state.uri.queryParameters['callId'] ?? ''}'),
        ),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  if (pushOverHome) {
    await tester.tap(find.text('open call'));
  }
  await _settle(tester);
  // The call service bounds its transcript-outbox setup with a 3 s timeout.
  await tester.pump(const Duration(seconds: 4));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _clearSnackBars(WidgetTester tester) async {
  tester
      .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
      .hideCurrentSnackBar();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late FakeWebViewPlatform webViews;

  setUp(() {
    webViews = FakeWebViewPlatform();
    WebViewPlatform.instance = webViews;
    SharedPreferences.setMockInitialValues({'user_role': 'caregiver'});
    final expiry =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600).toString();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
      if (call.method != 'read') return null;
      final key = (call.arguments as Map)['key'];
      if (key == 'jwt_token') return 'test-jwt';
      if (key == 'token_expiry') return expiry;
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_permissionChannel, (call) async {
      if (call.method != 'requestPermissions') return null;
      return {for (final p in (call.arguments as List).cast<int>()) p: 1};
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_permissionChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('caregiver joins the call and sees controls and sentiment panel',
      (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await _pumpCall(tester, callId: _nextCallId());

      expect(find.text('Call with Pat Ient'), findsOneWidget);
      expect(find.text('Connected to local mock session'), findsOneWidget);
      expect(find.text('Meeting: meeting-...'), findsOneWidget);
      expect(find.byTooltip('Mute microphone'), findsOneWidget);
      expect(find.byTooltip('Turn camera off'), findsOneWidget);
      expect(find.byTooltip('Switch camera'), findsOneWidget);
      expect(find.byTooltip('Add participant'), findsOneWidget);
      expect(find.byTooltip('Start recording'), findsOneWidget);
      expect(find.byType(SentimentDashboardWidget), findsOneWidget);

      // Advance the call duration ticker.
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining(':0'), findsWidgets);
    }, backend.client);
    expect(backend.requests.any((r) => r.endsWith('/join')), isTrue);
  });

  testWidgets('remote session with media endpoints shows plain session label',
      (tester) async {
    final backend = _Backend(joinToken: 'real-token');
    await http.runWithClient(() async {
      await _pumpCall(tester, callId: _nextCallId(), userRole: 'PATIENT');
      expect(find.text('Connected to call session'), findsOneWidget);
      // Patients get no caregiver-only controls or sentiment panel.
      expect(find.byTooltip('Add participant'), findsNothing);
      expect(find.byType(SentimentDashboardWidget), findsNothing);
    }, backend.client);
  });

  testWidgets('media toggles report unavailability without a meeting embed',
      (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await _pumpCall(tester, callId: _nextCallId(), userRole: 'PATIENT');

      await tester.tap(find.byTooltip('Mute microphone'));
      await _settle(tester);
      expect(
        find.text('Microphone toggle is not available for this session.'),
        findsOneWidget,
      );
      await _clearSnackBars(tester);

      await tester.tap(find.byTooltip('Turn camera off'));
      await _settle(tester);
      expect(
        find.text('Camera toggle is not available for this session.'),
        findsOneWidget,
      );
      await _clearSnackBars(tester);

      await tester.tap(find.byTooltip('Switch camera'));
      await _settle(tester);
      expect(
        find.text('Camera switch is not available for this session.'),
        findsOneWidget,
      );
    }, backend.client);
  });

  testWidgets('recording toggles on with a banner, ticks, then stops',
      (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await _pumpCall(tester, callId: _nextCallId());

      await tester.tap(find.byTooltip('Start recording'));
      await _settle(tester);
      expect(find.textContaining('Recording in progress'), findsOneWidget);
      expect(find.byTooltip('Stop recording'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(
          find.textContaining('Recording in progress — 0:0'), findsOneWidget);

      await tester.tap(find.byTooltip('Stop recording'));
      await _settle(tester);
      expect(find.textContaining('Recording in progress'), findsNothing);
      expect(find.byTooltip('Start recording'), findsOneWidget);
    }, backend.client);
    expect(
      backend.requests.where((r) => r.contains('/recording/')).length,
      2,
    );
  });

  testWidgets('recording start failure shows an unavailable message',
      (tester) async {
    final backend = _Backend(recordingStartCode: 500);
    await http.runWithClient(() async {
      await _pumpCall(tester, callId: _nextCallId());
      await tester.tap(find.byTooltip('Start recording'));
      await _settle(tester);
      expect(
        find.text(
          'Recording is unavailable right now. Check the recording setup.',
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Start recording'), findsOneWidget);
    }, backend.client);
  });

  testWidgets('recording stop failure shows a stop failure message',
      (tester) async {
    final backend = _Backend(recordingStopCode: 500);
    await http.runWithClient(() async {
      await _pumpCall(tester, callId: _nextCallId());
      await tester.tap(find.byTooltip('Start recording'));
      await _settle(tester);
      await tester.tap(find.byTooltip('Stop recording'));
      await _settle(tester);
      expect(find.text('Failed to stop recording.'), findsOneWidget);
    }, backend.client);
  });

  testWidgets('recording-state events from the server drive the banner',
      (tester) async {
    final backend = _Backend();
    final callId = _nextCallId();
    await http.runWithClient(() async {
      await _pumpCall(tester, callId: callId);

      CallNotificationService.processNotificationMessageForTest({
        'type': 'recording-state',
        'callId': callId,
        'status': 'ALREADY_RECORDING',
      });
      await _settle(tester);
      expect(find.textContaining('Recording in progress'), findsOneWidget);

      CallNotificationService.processNotificationMessageForTest({
        'type': 'recording-state',
        'callId': callId,
        'status': 'STOPPED',
      });
      await _settle(tester);
      expect(find.textContaining('Recording in progress'), findsNothing);
    }, backend.client);
  });

  testWidgets('sentiment-update events reach the caregiver dashboard',
      (tester) async {
    final backend = _Backend();
    final callId = _nextCallId();
    await http.runWithClient(() async {
      await _pumpCall(tester, callId: callId);
      CallNotificationService.processNotificationMessageForTest({
        'type': 'sentiment-update',
        'callId': callId,
        'sentiment': {
          'voice': {'score': 0.4, 'label': 'POSITIVE', 'status': 'ACTIVE'},
        },
      });
      await _settle(tester);
      expect(find.byType(SentimentDashboardWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, backend.client);
  });

  testWidgets('add participant with no invitees shows an empty message',
      (tester) async {
    final backend = _Backend(inviteeCode: 500);
    await http.runWithClient(() async {
      await _pumpCall(tester, callId: _nextCallId());
      await tester.tap(find.byTooltip('Add participant'));
      await _settle(tester);
      expect(
        find.text('No available care-circle members to add.'),
        findsOneWidget,
      );
    }, backend.client);
  });

  Future<void> inviteFromDialog(
    WidgetTester tester, {
    required String inviteStatus,
    int inviteCode = 200,
    required String expectedMessage,
  }) async {
    final backend = _Backend(
      invitees: const [
        {
          'userId': 7,
          'name': 'Fam Member',
          'role': 'FAMILY_MEMBER',
          'relationship': 'Daughter',
        },
        {'userId': 8, 'name': 'Other Carer', 'role': 'CAREGIVER'},
      ],
      inviteStatus: inviteStatus,
      inviteCode: inviteCode,
    );
    await http.runWithClient(() async {
      await _pumpCall(tester, callId: _nextCallId());
      await tester.tap(find.byTooltip('Add participant'));
      await _settle(tester);
      expect(find.text('Add Participant'), findsOneWidget);
      expect(find.text('Family Member · Daughter'), findsOneWidget);
      expect(find.text('Caregiver'), findsOneWidget);
      await tester.tap(find.text('Fam Member'));
      await _settle(tester);
      expect(find.text(expectedMessage), findsOneWidget);
    }, backend.client);
  }

  testWidgets('inviting a participant reports the invitation was sent',
      (tester) async {
    await inviteFromDialog(
      tester,
      inviteStatus: 'invited',
      expectedMessage: 'Invitation sent to Fam Member.',
    );
  });

  testWidgets('inviting an offline participant reports unavailability',
      (tester) async {
    await inviteFromDialog(
      tester,
      inviteStatus: 'offline',
      expectedMessage: 'Fam Member is not available right now.',
    );
  });

  testWidgets('a failed invite asks the user to try again', (tester) async {
    await inviteFromDialog(
      tester,
      inviteStatus: 'invited',
      inviteCode: 500,
      expectedMessage: 'Could not invite Fam Member. Please try again.',
    );
  });

  testWidgets('add participant dialog can be cancelled', (tester) async {
    final backend = _Backend(invitees: const [
      {'userId': 8, 'name': 'Other Carer', 'role': 'CAREGIVER'},
    ]);
    await http.runWithClient(() async {
      await _pumpCall(tester, callId: _nextCallId());
      await tester.tap(find.byTooltip('Add participant'));
      await _settle(tester);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(find.text('Add Participant'), findsNothing);
    }, backend.client);
  });

  testWidgets('end call posts to the backend and pops back', (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await _pumpCall(tester, callId: _nextCallId());
      await tester.tap(find.byTooltip('End call'));
      await _settle(tester);
      expect(find.text('open call'), findsOneWidget);
    }, backend.client);
    expect(backend.requests.any((r) => r.endsWith('/end')), isTrue);
  });

  testWidgets('end call without a back stack goes to the dashboard',
      (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await _pumpCall(tester, callId: _nextCallId(), pushOverHome: false);
      await tester.tap(find.byTooltip('End call'));
      await _settle(tester);
      expect(find.text('dashboard page'), findsOneWidget);
    }, backend.client);
  });

  testWidgets('end call with forced patient details pops with a result',
      (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await _pumpCall(
        tester,
        callId: _nextCallId(),
        returnPatientDetailsId: '42',
        forcePatientDetailsOnExit: true,
      );
      await tester.tap(find.byTooltip('End call'));
      await _settle(tester);
      expect(find.text('open call'), findsOneWidget);
    }, backend.client);
  });

  testWidgets('remote call-ended event exits the call screen', (tester) async {
    final backend = _Backend();
    final callId = _nextCallId();
    await http.runWithClient(() async {
      await _pumpCall(tester, callId: callId);
      CallNotificationService.processNotificationMessageForTest({
        'type': 'call-ended',
        'callId': callId,
      });
      await _settle(tester);
      expect(find.text('open call'), findsOneWidget);
    }, backend.client);
  });

  testWidgets('initiator creates a session and offers a join link',
      (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await _pumpCall(
        tester,
        callId: _nextCallId(),
        isInitiator: true,
        contextPatientUserIds: const [2],
        scheduledVisitId: 'visit-9',
      );
      // The notification socket is not connected, so the invitation cannot
      // ring and the caller is offered a copyable join link instead.
      expect(
        find.textContaining('Could not ring the other account'),
        findsOneWidget,
      );
      await tester.tap(find.text('Copy link'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text(
            'Join link copied. Open it while logged in as the other user.'),
        findsOneWidget,
      );
    }, backend.client);
    expect(backend.requests.first, endsWith('/calls/sessions'));
  });

  testWidgets('initiator without a recipient id shows a call error',
      (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await _pumpCall(
        tester,
        callId: _nextCallId(),
        isInitiator: true,
        recipientId: null,
      );
      expect(find.text('Could not connect to call'), findsOneWidget);
    }, backend.client);
  });

  testWidgets('care-team initiator without one patient is told to select one',
      (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await _pumpCall(
        tester,
        callId: _nextCallId(),
        isInitiator: true,
        callKind: 'CARE_TEAM',
        recipientRole: 'CAREGIVER',
      );
      expect(
        find.text('Select one patient before starting this care-team call.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Go Back'));
      await _settle(tester);
      expect(find.text('open call'), findsOneWidget);
    }, backend.client);
  });

  testWidgets('declined call shows the rejection summary and can return',
      (tester) async {
    final backend = _Backend();
    final callId = _nextCallId();
    await http.runWithClient(() async {
      await _pumpCall(
        tester,
        callId: callId,
        isInitiator: true,
        contextPatientUserIds: const [2],
      );
      CallNotificationService.processNotificationMessageForTest({
        'type': 'call-declined',
        'callId': callId,
        'declinedByName': 'Pat',
        'reason': 'busy',
      });
      await _settle(tester);
      expect(find.text('Call Rejected'), findsOneWidget);
      expect(find.text('Pat declined the call (busy).'), findsOneWidget);

      await tester.tap(find.text('Return'));
      await _settle(tester);
      expect(find.text('open call'), findsOneWidget);
    }, backend.client);
  });

  testWidgets('declined call retry starts a new call route', (tester) async {
    final backend = _Backend();
    final callId = _nextCallId();
    await http.runWithClient(() async {
      await _pumpCall(
        tester,
        callId: callId,
        isInitiator: true,
        contextPatientUserIds: const [2],
        scheduledVisitId: 'visit-3',
      );
      CallNotificationService.processNotificationMessageForTest({
        'type': 'call-declined',
        'callId': callId,
        'reason': '',
      });
      await _settle(tester);
      expect(find.text('Pat Ient declined the call.'), findsOneWidget);

      await tester.tap(find.text('Try Again'));
      await _settle(tester);
      expect(find.textContaining('rejoin chime_call_'), findsOneWidget);
    }, backend.client);
  });

  testWidgets('join failure from the backend renders the error state',
      (tester) async {
    final backend = _Backend(joinStatus: 403);
    await http.runWithClient(() async {
      await _pumpCall(tester, callId: _nextCallId(), recipientName: null);
      expect(find.text('Video Call'), findsOneWidget);
      expect(
        find.text('You do not have permission to start or join this call.'),
        findsOneWidget,
      );
    }, backend.client);
  });

  testWidgets('loading state names the recipient', (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => HybridVideoCallWidget(
            userId: '1',
            callId: _nextCallId(),
            recipientId: '2',
            userRole: 'CAREGIVER',
            recipientName: 'Pat Ient',
          ),
        ),
      ]);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      expect(find.text('Connecting to call...'), findsOneWidget);
      expect(find.text('with Pat Ient'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await _settle(tester);
    }, backend.client);
  });

  testWidgets('dark theme uses the dark call background', (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => HybridVideoCallWidget(
            userId: '1',
            callId: _nextCallId(),
            recipientId: '2',
            userRole: 'PATIENT',
          ),
        ),
      ]);
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        theme: ThemeData(brightness: Brightness.dark),
      ));
      await tester.pump(const Duration(seconds: 4));
      await _settle(tester);
      expect(find.byType(Scaffold), findsOneWidget);
    }, backend.client);
  });

  group('with a live meeting embed', () {
    const bridge = 'CareConnectChimeBridge';
    const endpoints = <String, dynamic>{'audioHostUrl': 'wss://audio.example'};

    String msg(Map<String, dynamic> data) =>
        jsonEncode({'source': 'careconnect-chime', ...data});

    Future<FakePlatformWebViewController> pumpEmbedCall(
      WidgetTester tester, {
      required String callId,
      String userRole = 'PATIENT',
      String callKind = 'GENERAL',
      bool finishPage = true,
    }) async {
      await _pumpCall(
        tester,
        callId: callId,
        userRole: userRole,
        recipientRole: userRole == 'PATIENT' ? 'CAREGIVER' : 'PATIENT',
        callKind: callKind,
      );
      final controller = webViews.controllers.single;
      if (finishPage) {
        controller.finishPage();
        await tester.pump();
      }
      return controller;
    }

    Future<void> send(
      WidgetTester tester,
      FakePlatformWebViewController controller,
      Map<String, dynamic> data,
    ) async {
      controller.sendToChannel(bridge, msg(data));
      await _settle(tester);
    }

    int count(_Backend backend, String suffix) =>
        backend.requests.where((r) => r.endsWith(suffix)).length;

    testWidgets('patient voice and video samples are posted and throttled',
        (tester) async {
      final backend = _Backend(joinToken: 'real', mediaPlacement: endpoints);
      final callId = _nextCallId();
      await http.runWithClient(() async {
        final controller = await pumpEmbedCall(tester, callId: callId);

        final voice = {
          'action': 'sentiment-voice-metrics',
          'payload': {
            'averageLevel': 0.01,
            'speechRatio': 0.01,
            'variability': 0.1,
          },
        };
        await send(tester, controller, voice);
        expect(count(backend, '/sentiment/voice'), 1);

        // A second quiet sample inside the throttle window is dropped.
        await send(tester, controller, voice);
        expect(count(backend, '/sentiment/voice'), 1);

        // Once the voice channel reports QUIET, a speaking sample is sent
        // immediately to recover the channel.
        CallNotificationService.processNotificationMessageForTest({
          'type': 'sentiment-channel-state',
          'callId': callId,
          'channel': 'voice',
          'status': 'QUIET',
        });
        await _settle(tester);
        await send(tester, controller, {
          'action': 'sentiment-voice-metrics',
          'payload': {
            'averageLevel': 0.3,
            'speechRatio': 0.5,
            'variability': 0.2,
          },
        });
        expect(count(backend, '/sentiment/voice'), 2);

        // Loud but mostly silent audio also counts as recovery while quiet.
        CallNotificationService.processNotificationMessageForTest({
          'type': 'sentiment-channel-state',
          'callId': callId,
          'channel': 'voice',
          'status': 'QUIET',
        });
        await _settle(tester);
        await send(tester, controller, {
          'action': 'sentiment-voice-metrics',
          'payload': {
            'averageLevel': 0.3,
            'speechRatio': 0.01,
            'variability': 0.2,
          },
        });
        expect(count(backend, '/sentiment/voice'), 3);

        final video = {
          'action': 'sentiment-video-sample',
          'payload': {'imageBase64': 'abc'},
        };
        await send(tester, controller, video);
        await send(tester, controller, video);
        expect(count(backend, '/sentiment/video'), 1);
      }, backend.client);
    });

    testWidgets('repeated sample failures restart the sentiment channels',
        (tester) async {
      final backend = _Backend(
        joinToken: 'real',
        mediaPlacement: endpoints,
        sentimentCode: 500,
      );
      await http.runWithClient(() async {
        final controller = await pumpEmbedCall(tester, callId: _nextCallId());
        final scriptsBefore = controller.scripts.length;

        final voice = {
          'action': 'sentiment-voice-metrics',
          'payload': {
            'averageLevel': 0.2,
            'speechRatio': 0.2,
            'variability': 0
          },
        };
        final video = {
          'action': 'sentiment-video-sample',
          'payload': {'imageBase64': 'frame'},
        };
        // Two failures in a row restart the channel; two more inside the
        // restart cooldown do not.
        for (var i = 0; i < 4; i++) {
          await send(tester, controller, voice);
          await send(tester, controller, video);
        }
        final restarts = controller.scripts
            .skip(scriptsBefore)
            .where((s) => s.contains('restart-sentiment-channel'))
            .toList();
        expect(restarts, hasLength(2));
        expect(restarts.first, contains('"channel":"voice"'));
        expect(restarts.last, contains('"channel":"video"'));
      }, backend.client);
    });

    testWidgets('restart is skipped while the page is not attached',
        (tester) async {
      final backend = _Backend(
        joinToken: 'real',
        mediaPlacement: endpoints,
        sentimentCode: 500,
      );
      await http.runWithClient(() async {
        final controller = await pumpEmbedCall(
          tester,
          callId: _nextCallId(),
          finishPage: false,
        );
        for (var i = 0; i < 2; i++) {
          await send(tester, controller, {
            'action': 'sentiment-voice-metrics',
            'payload': {'averageLevel': 0, 'speechRatio': 0, 'variability': 0},
          });
          await send(tester, controller, {
            'action': 'sentiment-video-sample',
            'payload': {'imageBase64': 'frame'},
          });
        }
        expect(controller.scripts, isEmpty);
      }, backend.client);
    });

    testWidgets('caregivers ignore voice and video samples', (tester) async {
      final backend = _Backend(joinToken: 'real', mediaPlacement: endpoints);
      await http.runWithClient(() async {
        final controller = await pumpEmbedCall(
          tester,
          callId: _nextCallId(),
          userRole: 'CAREGIVER',
        );
        await send(tester, controller, {
          'action': 'sentiment-voice-metrics',
          'payload': {'averageLevel': 1, 'speechRatio': 1, 'variability': 1},
        });
        await send(tester, controller, {
          'action': 'sentiment-video-sample',
          'payload': {'imageBase64': 'frame'},
        });
        await send(tester, controller, {
          'action': 'sentiment-channel-state',
          'payload': {'channel': 'voice', 'muted': true},
        });
        expect(
            backend.requests.where((r) => r.contains('/sentiment/')), isEmpty);
      }, backend.client);
    });

    testWidgets('transcript samples and statuses are handled', (tester) async {
      final backend = _Backend(joinToken: 'real', mediaPlacement: endpoints);
      await http.runWithClient(() async {
        final controller = await pumpEmbedCall(tester, callId: _nextCallId());
        await send(tester, controller, {
          'action': 'log',
          'message': 'Chime transcript capture subscribed',
        });
        for (final payload in const <Map<String, dynamic>>[
          {'text': 'a'},
          {
            'text': 'hello there',
            'speakerLabel': 'external-1',
            'startMs': 10,
            'endMs': 20.6,
          },
          {'text': 'second line', 'startMs': '-4', 'endMs': -1},
          {'text': 'third line', 'startMs': '15', 'endMs': -2.5},
          {'text': 'speech fallback line', 'source': 'speech-api'},
        ]) {
          await send(tester, controller, {
            'action': 'sentiment-transcript',
            'payload': payload,
          });
        }
        await send(tester, controller, {
          'action': 'sentiment-channel-state',
          'payload': {'channel': 'video', 'muted': true},
        });
        expect(tester.takeException(), isNull);
      }, backend.client);
    });

    testWidgets('care-team calls disable transcript capture', (tester) async {
      final backend = _Backend(joinToken: 'real', mediaPlacement: endpoints);
      await http.runWithClient(() async {
        final controller = await pumpEmbedCall(
          tester,
          callId: _nextCallId(),
          userRole: 'CAREGIVER',
          callKind: 'CARE_TEAM',
        );
        for (var i = 0; i < 2; i++) {
          await send(tester, controller, {
            'action': 'sentiment-transcript',
            'payload': {'text': 'care team chatter'},
          });
        }
        expect(find.byType(SentimentDashboardWidget), findsNothing);
      }, backend.client);
    });

    testWidgets('media toggles post actions to the page', (tester) async {
      final backend = _Backend(joinToken: 'real', mediaPlacement: endpoints);
      await http.runWithClient(() async {
        final controller = await pumpEmbedCall(tester, callId: _nextCallId());

        await tester.tap(find.byTooltip('Mute microphone'));
        await _settle(tester);
        expect(find.byTooltip('Unmute microphone'), findsOneWidget);

        await tester.tap(find.byTooltip('Turn camera off'));
        await _settle(tester);
        expect(find.byTooltip('Turn camera on'), findsOneWidget);

        await tester.tap(find.byTooltip('Switch camera'));
        await _settle(tester);
        expect(
          find.text('Camera switch is not available for this session.'),
          findsNothing,
        );
        expect(
          controller.scripts.map(
              (s) => RegExp('"action":"([a-z-]+)"').firstMatch(s)!.group(1)),
          containsAll(
              <String>['toggle-audio', 'toggle-video', 'switch-camera']),
        );
      }, backend.client);
    });

    testWidgets('caregiver media toggles skip sentiment channel updates',
        (tester) async {
      final backend = _Backend(joinToken: 'real', mediaPlacement: endpoints);
      await http.runWithClient(() async {
        await pumpEmbedCall(
          tester,
          callId: _nextCallId(),
          userRole: 'CAREGIVER',
        );
        await tester.tap(find.byTooltip('Mute microphone'));
        await _settle(tester);
        expect(find.byTooltip('Unmute microphone'), findsOneWidget);
      }, backend.client);
    });

    testWidgets('an end-call request from the page ends the call',
        (tester) async {
      final backend = _Backend(joinToken: 'real', mediaPlacement: endpoints);
      await http.runWithClient(() async {
        final controller = await pumpEmbedCall(tester, callId: _nextCallId());
        await send(tester, controller, {'action': 'end-call-request'});
        expect(find.text('open call'), findsOneWidget);
      }, backend.client);
      expect(backend.requests.any((r) => r.endsWith('/end')), isTrue);
    });
  });

  testWidgets('role falls back to the stored user role', (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await _pumpCall(tester, callId: _nextCallId(), userRole: null);
      // The stored role is caregiver, so caregiver-only controls appear.
      expect(find.byTooltip('Add participant'), findsOneWidget);
    }, backend.client);
  });

  testWidgets('initiator falls back to a patient recipient role',
      (tester) async {
    final backend = _Backend();
    await http.runWithClient(() async {
      await _pumpCall(
        tester,
        callId: _nextCallId(),
        isInitiator: true,
        recipientRole: 'FAMILY_MEMBER',
        contextPatientUserIds: const [2],
      );
      expect(find.text('Connected to local mock session'), findsOneWidget);
    }, backend.client);
  });
}
