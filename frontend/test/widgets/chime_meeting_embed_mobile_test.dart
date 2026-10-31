// Widget tests for the mobile Chime meeting embed
// (lib/widgets/chime_meeting_embed_mobile.dart, reached through the
// conditional import in chime_meeting_embed.dart on VM platforms).
//
// The embed hosts the Chime JS SDK inside a WebView. A FakeWebViewPlatform
// stands in for the native WebView so the tests can finish page loads, send
// bridge messages from "JavaScript", and inspect the actions Flutter posts
// back into the page.

import 'dart:convert';

import 'package:care_connect_app/widgets/chime_meeting_embed.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../test_support/fake_webview_platform.dart';

const _permissionChannel =
    MethodChannel('flutter.baseflow.com/permissions/methods');
const _bridge = 'CareConnectChimeBridge';

class _Recorder {
  int endRequests = 0;
  final List<Map<String, dynamic>> transcripts = <Map<String, dynamic>>[];
  final List<String> statuses = <String>[];
  final List<List<double>> voice = <List<double>>[];
  final List<String> video = <String>[];
  final List<String> channelStates = <String>[];
}

Future<_Recorder> _pumpEmbed(
  WidgetTester tester, {
  String meetingId = 'meeting-a',
  String? externalUserId,
  bool withCallbacks = true,
}) async {
  final recorder = _Recorder();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: buildChimeMeetingEmbed(
          meetingId: meetingId,
          attendeeId: 'attendee-12345678',
          joinToken: 'join-token',
          mediaPlacement: const {'audioHostUrl': 'wss://audio.example'},
          externalUserId: externalUserId,
          videoEnabled: true,
          audioEnabled: true,
          enableAutoSentimentCapture: true,
          onEndCallRequested:
              withCallbacks ? () => recorder.endRequests++ : null,
          onTranscriptSample: withCallbacks ? recorder.transcripts.add : null,
          onTranscriptStatus: withCallbacks
              ? (status, detail) => recorder.statuses.add(status)
              : null,
          onVoiceMetricsSample:
              withCallbacks ? (a, b, c) => recorder.voice.add([a, b, c]) : null,
          onVideoSample: withCallbacks ? recorder.video.add : null,
          onSentimentChannelState: withCallbacks
              ? (channel, muted) =>
                  recorder.channelStates.add('$channel:$muted')
              : null,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return recorder;
}

String _msg(Map<String, dynamic> data) =>
    jsonEncode({'source': 'careconnect-chime', ...data});

void main() {
  late FakeWebViewPlatform platform;
  late List<MethodCall> permissionCalls;
  late int permissionResult;

  setUp(() {
    platform = FakeWebViewPlatform();
    WebViewPlatform.instance = platform;
    permissionCalls = <MethodCall>[];
    permissionResult = 1; // PermissionStatus.granted
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_permissionChannel, (call) async {
      permissionCalls.add(call);
      if (call.method == 'requestPermissions') {
        final requested = (call.arguments as List).cast<int>();
        return {for (final p in requested) p: permissionResult};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_permissionChannel, null);
  });

  test('page actions report false when no meeting embed is active', () async {
    expect(await requestChimeAudioToggle(muted: true), isFalse);
    expect(await requestChimeVideoToggle(muted: true), isFalse);
    expect(await requestChimeCameraSwitch(), isFalse);
    expect(
      await requestChimeSentimentChannelRestart(channel: 'voice'),
      isFalse,
    );
    expect(
      await requestChimeSentimentChannelRestart(channel: 'other'),
      isFalse,
    );
  });

  testWidgets('desktop platforms show an unsupported message', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _pumpEmbed(tester);
      expect(
        find.text(
          'Real-time Chime media is supported on Android/iOS for mobile builds.',
        ),
        findsOneWidget,
      );
      expect(platform.controllers, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('loads the meeting page and walks through the load lifecycle',
      (tester) async {
    await _pumpEmbed(tester);

    expect(permissionCalls.single.method, 'requestPermissions');
    final controller = platform.controllers.single;
    expect(controller.channels.keys, contains(_bridge));
    expect(controller.loadedBaseUrl, 'https://localhost');
    expect(controller.loadedHtml, contains('careconnect-'));
    expect(find.byKey(const ValueKey<String>('fake-webview')), findsOneWidget);
    expect(find.text('Preparing secure connection...'), findsOneWidget);

    controller.startPage();
    await tester.pump();
    expect(find.text('Opening video call...'), findsOneWidget);

    // Not attached until the page finishes, so actions cannot be posted yet.
    expect(
      await requestChimeAudioToggle(muted: true, meetingId: 'meeting-a'),
      isFalse,
    );

    controller.finishPage();
    await tester.pump();
    expect(find.text('Connecting to participant...'), findsOneWidget);
  });

  testWidgets('denied permissions still build the page', (tester) async {
    permissionResult = 0; // PermissionStatus.denied
    await _pumpEmbed(tester, externalUserId: 'ext-1');
    expect(platform.controllers, hasLength(1));
    expect(platform.controllers.single.loadedHtml, contains('ext-1'));
  });

  testWidgets('permission plugin failures are tolerated', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_permissionChannel, (call) async {
      throw PlatformException(code: 'boom');
    });
    await _pumpEmbed(tester);
    expect(platform.controllers, hasLength(1));
  });

  testWidgets('posts toggle, switch and restart actions into the page',
      (tester) async {
    await _pumpEmbed(tester);
    final controller = platform.controllers.single;
    controller.finishPage();
    await tester.pump();

    expect(
      await requestChimeAudioToggle(muted: true, meetingId: 'meeting-a'),
      isTrue,
    );
    expect(await requestChimeVideoToggle(muted: false), isTrue);
    expect(await requestChimeCameraSwitch(meetingId: ' meeting-a '), isTrue);
    expect(
      await requestChimeSentimentChannelRestart(
        channel: ' Voice ',
        meetingId: 'meeting-a',
      ),
      isTrue,
    );
    expect(
      await requestChimeSentimentChannelRestart(channel: 'smell'),
      isFalse,
    );
    expect(
      await requestChimeAudioToggle(muted: true, meetingId: 'other-meeting'),
      isFalse,
    );

    expect(controller.scripts, hasLength(4));
    expect(controller.scripts[0], contains('"action":"toggle-audio"'));
    expect(controller.scripts[1], contains('"action":"toggle-video"'));
    expect(controller.scripts[2], contains('"action":"switch-camera"'));
    expect(controller.scripts[3], contains('"channel":"voice"'));

    controller.failJavaScript = true;
    expect(await requestChimeCameraSwitch(), isFalse);
  });

  testWidgets('dispose posts a teardown and unregisters the meeting',
      (tester) async {
    await _pumpEmbed(tester);
    final controller = platform.controllers.single;
    controller.finishPage();
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(controller.scripts.last, contains('"action":"teardown"'));
    expect(await requestChimeCameraSwitch(), isFalse);
  });

  testWidgets('ignores malformed or foreign bridge messages', (tester) async {
    final recorder = await _pumpEmbed(tester);
    final controller = platform.controllers.single;

    controller.sendToChannel(_bridge, 'not json');
    controller.sendToChannel(_bridge, '[1, 2]');
    controller.sendToChannel(
      _bridge,
      jsonEncode({'source': 'someone-else', 'action': 'end-call-request'}),
    );
    await tester.pump();
    expect(recorder.endRequests, 0);
    expect(find.text('Preparing secure connection...'), findsOneWidget);
  });

  testWidgets('end-call requests reach the callback', (tester) async {
    final recorder = await _pumpEmbed(tester);
    platform.controllers.single
        .sendToChannel(_bridge, _msg({'action': 'end-call-request'}));
    expect(recorder.endRequests, 1);
  });

  testWidgets('log messages map to user-facing status text', (tester) async {
    await _pumpEmbed(tester);
    final controller = platform.controllers.single;

    Future<void> log(String message, {String level = 'info'}) async {
      controller.sendToChannel(
        _bridge,
        _msg({'action': 'log', 'level': level, 'message': message}),
      );
      await tester.pump();
    }

    const mapped = <String, String>{
      'Loading Chime SDK v3': 'Preparing secure call connection...',
      'Creating meeting session...': 'Joining call session...',
      'Preparing audio/video devices...': 'Checking camera and microphone...',
      'Starting Chime media session...': 'Starting audio and video...',
      'Failed to initialize call media':
          'Unable to start video right now. Please rejoin the call.',
      'Participant joined (audio only)':
          'Connected with participant (audio only)',
      'Connected with participant (audio only)':
          'Connected with participant (audio only)',
      'In call lobby: waiting for participant video...':
          'In call lobby: waiting for another participant to join...',
      'In call lobby: waiting for the other person to join...':
          'In call lobby: waiting for another participant to join...',
      'Call ended': 'Disconnected',
      'Connected with participant': 'Connected with participant',
      'Some other status': 'Some other status',
    };
    for (final entry in mapped.entries) {
      await log(entry.key, level: 'warn');
      expect(find.text(entry.value), findsOneWidget, reason: entry.key);
    }

    // Transport noise is hidden: the banner keeps the previous status.
    for (final noise in const [
      'Trying SDK URL: x',
      'Chime SDK loaded from: x',
      'Audio input devices: 1',
      'Audio input started: mic',
      'audioVideo.start() invoked',
      'audioVideoDidStart',
      'Presence update: a',
      'Local video tile bound',
      'Remote video tile bound',
      'Requested local video tile start',
      'Video play() interrupted for tile',
      '   ',
    ]) {
      await log(noise, level: 'warning');
      expect(find.text('Some other status'), findsOneWidget, reason: noise);
    }
  });

  testWidgets('transcript log lines drive the transcript status',
      (tester) async {
    final recorder = await _pumpEmbed(tester);
    final controller = platform.controllers.single;

    for (final line in const [
      ['info', 'Chime transcript capture subscribed'],
      ['info', 'Speech transcription capture started'],
      ['info', 'SpeechRecognition API unavailable'],
      ['info', 'speech recognition error: not-allowed'],
      ['info', 'speech recognition error: service-not-allowed'],
      ['warn', 'No usable transcript text captured'],
      ['info', 'No usable transcript text captured'],
    ]) {
      controller.sendToChannel(
        _bridge,
        _msg({'action': 'log', 'level': line[0], 'message': line[1]}),
      );
    }
    await tester.pump();
    expect(recorder.statuses, [
      'AWAITING',
      'FALLBACK',
      'BLOCKED',
      'BLOCKED',
      'BLOCKED',
      'FALLBACK',
    ]);
  });

  testWidgets('transcript samples are forwarded in every payload shape',
      (tester) async {
    final recorder = await _pumpEmbed(tester);
    final controller = platform.controllers.single;

    controller.sendToChannel(
      _bridge,
      _msg({
        'action': 'sentiment-transcript',
        'payload': {'text': ' hello there ', 'speakerLabel': 'ME'},
      }),
    );
    controller.sendToChannel(
      _bridge,
      _msg({
        'action': 'sentiment-transcript',
        'payload': jsonEncode({'text': 'from string', 'source': 'speech-api'}),
      }),
    );
    controller.sendToChannel(
      _bridge,
      _msg({'action': 'sentiment-transcript', 'payload': '{not json'}),
    );
    controller.sendToChannel(
      _bridge,
      _msg({'action': 'sentiment-transcript', 'payload': '   '}),
    );
    controller.sendToChannel(
      _bridge,
      _msg({'action': 'sentiment-transcript', 'payload': 5}),
    );
    await tester.pump();

    expect(recorder.transcripts, hasLength(2));
    expect(recorder.transcripts[0]['speakerLabel'], 'ME');
    expect(recorder.transcripts[1]['speakerLabel'], 'PARTICIPANT');
    expect(recorder.statuses, ['CONNECTED', 'FALLBACK']);
  });

  testWidgets('voice, video and channel-state samples are forwarded',
      (tester) async {
    final recorder = await _pumpEmbed(tester);
    final controller = platform.controllers.single;

    controller.sendToChannel(
      _bridge,
      _msg({
        'action': 'sentiment-voice-metrics',
        'payload': {
          'averageLevel': 0.5,
          'speechRatio': '0.25',
          'variability': 0.1,
        },
      }),
    );
    controller.sendToChannel(
      _bridge,
      _msg({
        'action': 'sentiment-voice-metrics',
        'payload': {'averageLevel': 'x', 'speechRatio': 1, 'variability': 1},
      }),
    );
    controller.sendToChannel(
      _bridge,
      _msg({
        'action': 'sentiment-video-sample',
        'payload': {'imageBase64': ' abc '},
      }),
    );
    controller.sendToChannel(
      _bridge,
      _msg({
        'action': 'sentiment-video-sample',
        'payload': {'imageBase64': ''},
      }),
    );
    for (final channel in const ['Voice', 'video', 'text', 'smell']) {
      controller.sendToChannel(
        _bridge,
        _msg({
          'action': 'sentiment-channel-state',
          'payload': {'channel': channel, 'muted': channel == 'video'},
        }),
      );
    }
    await tester.pump();

    expect(recorder.voice, [
      [0.5, 0.25, 0.1],
    ]);
    expect(recorder.video, ['abc']);
    expect(recorder.channelStates, ['voice:false', 'video:true', 'text:false']);
  });

  testWidgets('messages are safe without registered callbacks', (tester) async {
    await _pumpEmbed(tester, withCallbacks: false);
    final controller = platform.controllers.single;
    controller.sendToChannel(_bridge, _msg({'action': 'end-call-request'}));
    controller.sendToChannel(
      _bridge,
      _msg({'action': 'log', 'message': 'Chime transcript capture subscribed'}),
    );
    controller.sendToChannel(
      _bridge,
      _msg({
        'action': 'sentiment-transcript',
        'payload': {'text': 'hi'},
      }),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('error-level bridge messages replace the view with the error',
      (tester) async {
    await _pumpEmbed(tester);
    platform.controllers.single.sendToChannel(
      _bridge,
      _msg({'level': 'error', 'message': 'Media device lost'}),
    );
    await tester.pump();
    expect(find.text('Media device lost'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('fake-webview')), findsNothing);
  });

  testWidgets('an error with no message shows a generic media error',
      (tester) async {
    await _pumpEmbed(tester);
    platform.controllers.single
        .sendToChannel(_bridge, _msg({'level': 'error'}));
    await tester.pump();
    expect(find.text('Unknown Chime media error'), findsOneWidget);
  });

  testWidgets('main-frame load errors are shown, sub-resource errors ignored',
      (tester) async {
    await _pumpEmbed(tester);
    final controller = platform.controllers.single;

    controller.failResource(
      const WebResourceError(
        errorCode: -2,
        description: 'image missing',
        isForMainFrame: false,
      ),
    );
    await tester.pump();
    expect(find.textContaining('WebView load error'), findsNothing);

    controller.failResource(
      const WebResourceError(
        errorCode: -6,
        description: 'connection refused',
        isForMainFrame: true,
      ),
    );
    await tester.pump();
    expect(
      find.text('WebView load error: connection refused'),
      findsOneWidget,
    );
  });
}
