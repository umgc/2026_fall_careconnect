import 'dart:convert';

import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/utils/sentiment_clip_recording_status.dart';
import 'package:care_connect_app/utils/sentiment_clip_window.dart';
import 'package:care_connect_app/widgets/post_call_telemetry_summary_screen.dart';
import 'package:care_connect_app/widgets/sentiment_clip_player_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

Future<void> _pumpLoaded(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpClipLoaded(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tapTimelineNearFirstVoiceSample(WidgetTester tester) async {
  final timeline = find.byKey(const Key('sentiment_timeline_canvas'));
  await tester.scrollUntilVisible(
    timeline,
    120,
    scrollable: find.byType(Scrollable).first,
  );

  final voiceChip = find.widgetWithText(ChoiceChip, 'Voice');
  if (tester.any(voiceChip)) {
    final chip = tester.widget<ChoiceChip>(voiceChip.first);
    if (!chip.selected) {
      await tester.tap(voiceChip.first);
      await tester.pump();
    }
  }

  expect(timeline, findsOneWidget);
  final box = tester.renderObject<RenderBox>(timeline);
  final global = box.localToGlobal(const Offset(174, 86));
  await tester.tapAt(global);
  await tester.pump();
}

Future<void> _tapTimelineNearSecondVoiceSample(WidgetTester tester) async {
  final timeline = find.byKey(const Key('sentiment_timeline_canvas'));
  await tester.scrollUntilVisible(
    timeline,
    120,
    scrollable: find.byType(Scrollable).first,
  );

  expect(timeline, findsOneWidget);
  final box = tester.renderObject<RenderBox>(timeline);
  final global = box.localToGlobal(const Offset(275, 157));
  await tester.tapAt(global);
  await tester.pump();
}

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async => 0;

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 0;

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    return Stream<VideoEvent>.value(
      VideoEvent(
        eventType: VideoEventType.initialized,
        size: const Size(1920, 1080),
        duration: const Duration(minutes: 5),
      ),
    );
  }

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildView(int playerId) => Texture(textureId: playerId);

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      Texture(textureId: options.playerId);
}

http.Response _richTelemetryResponse() {
  return http.Response(
    jsonEncode([
      {
        'eventType': 'CALL_STARTED',
        'occurredAt': '2026-03-12T15:00:00Z',
      },
      {
        'eventType': 'SENTIMENT_VOICE',
        'channel': 'VOICE',
        'sentimentScore': 0.72,
        'sentimentLabel': 'CALM',
        'sentimentNotes': 'steady voice',
        'occurredAt': '2026-03-12T15:01:00Z',
      },
      {
        'eventType': 'SENTIMENT_VOICE',
        'channel': 'VOICE',
        'sentimentScore': 0.42,
        'sentimentLabel': 'ANXIOUS',
        'sentimentNotes': 'mild tension',
        'occurredAt': '2026-03-12T15:02:00Z',
      },
      {
        'eventType': 'SENTIMENT_FINAL',
        'channel': 'COMBINED',
        'sentimentScore': 0.68,
        'sentimentLabel': 'CALM',
        'sentimentNotes': 'Recovered by end of call',
        'occurredAt': '2026-03-12T15:04:00Z',
      },
      {
        'eventType': 'CALL_ENDED',
        'occurredAt': '2026-03-12T15:05:00Z',
        'metadata': {'reason': 'completed'},
      },
    ]),
    200,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  group('computeSentimentClipWindow', () {
    test('parses UTC timestamps for post-call clip offset', () {
      final window = computeSentimentClipWindow(
        sentimentOccurredAt: DateTime.parse('2026-03-12T15:01:00Z'),
        recordingStartedAt: DateTime.parse('2026-03-12T15:00:00Z'),
      );

      expect(window.offsetSec, 60);
      expect(window.clipStartSec, 45);
      expect(window.clipEndSec, 75);
    });
  });

  group('sentimentClipRecordingStatusMessage', () {
    test('available when user-initiated and playback ready', () {
      expect(
        sentimentClipRecordingStatusMessage({
          'initiatedByUserId': 42,
          'playbackReady': true,
        }),
        kSentimentClipRecordingStatusAvailable,
      );
    });

    test('processing when user-initiated and not ready', () {
      expect(
        sentimentClipRecordingStatusMessage({
          'initiatedByUserId': 42,
          'playbackReady': false,
        }),
        kSentimentClipRecordingStatusProcessing,
      );
    });

    test('unavailable for system-only recording', () {
      expect(
        sentimentClipRecordingStatusMessage({
          'initiatedByUserId': null,
          'playbackReady': false,
        }),
        kSentimentClipRecordingStatusUnavailable,
      );
    });
  });

  group('PostCallTelemetrySummaryScreen', () {
    setUpAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, (call) async {
        switch (call.method) {
          case 'read':
            return null;
          case 'write':
          case 'delete':
          case 'deleteAll':
            return null;
          case 'containsKey':
            return false;
          case 'readAll':
            return <String, String>{};
          default:
            return null;
        }
      });
    });

    tearDownAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, null);
    });

    tearDown(() {
      ApiService.debugResetHttpClient();
    });

    setUp(() {
      VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();
    });

    testWidgets('renders empty telemetry state when backend has no call data', (
      tester,
    ) async {
      ApiService.debugSetHttpClient(
        MockClient((request) async {
          if (request.url.path.endsWith('/telemetry')) {
            return http.Response(jsonEncode(<Map<String, dynamic>>[]), 200);
          }
          if (request.url.path.endsWith('/summary')) {
            return http.Response('', 404);
          }
          if (request.url.path.endsWith('/transcript/segments')) {
            return http.Response(jsonEncode(<Map<String, dynamic>>[]), 200);
          }
          if (request.url.path.endsWith('/recording')) {
            return http.Response('', 404);
          }
          return http.Response('', 404);
        }),
      );

      await tester.pumpWidget(
        _wrap(
          const PostCallTelemetrySummaryScreen(
            callId: 'call-empty',
            recipientName: 'Pat Doe',
          ),
        ),
      );
      await _pumpLoaded(tester);

      expect(find.text('Call Summary'), findsOneWidget);
      expect(
          find.text('No telemetry saved for this call yet.'), findsOneWidget);
      expect(
        find.text('No sentiment data available for this call.'),
        findsOneWidget,
      );
      expect(find.text('Call Transcript'), findsNothing);
    });

    testWidgets('renders summary, recording, transcript, and action callbacks',
        (
      tester,
    ) async {
      var callAgainTapped = 0;
      var sendMessageTapped = 0;

      ApiService.debugSetHttpClient(
        MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/telemetry')) {
            return http.Response(
              jsonEncode([
                {
                  'eventType': 'CALL_STARTED',
                  'occurredAt': '2026-03-12T15:00:00Z',
                },
                {
                  'eventType': 'SENTIMENT_VOICE',
                  'channel': 'VOICE',
                  'sentimentScore': 0.72,
                  'sentimentLabel': 'CALM',
                  'sentimentNotes': 'steady voice',
                  'occurredAt': '2026-03-12T15:01:00Z',
                },
                {
                  'eventType': 'SENTIMENT_VOICE',
                  'channel': 'VOICE',
                  'sentimentScore': 0.42,
                  'sentimentLabel': 'ANXIOUS',
                  'sentimentNotes': 'mild tension',
                  'occurredAt': '2026-03-12T15:02:00Z',
                },
                {
                  'eventType': 'SENTIMENT_FINAL',
                  'channel': 'COMBINED',
                  'sentimentScore': 0.68,
                  'sentimentLabel': 'CALM',
                  'sentimentNotes': 'Recovered by end of call',
                  'occurredAt': '2026-03-12T15:04:00Z',
                },
                {
                  'eventType': 'CALL_ENDED',
                  'occurredAt': '2026-03-12T15:05:00Z',
                  'metadata': {'reason': 'completed'},
                },
              ]),
              200,
            );
          }
          if (path.endsWith('/summary')) {
            return http.Response(
              jsonEncode({
                'summary': {
                  'headline': 'Patient stabilized during the check-in.',
                  'overallAssessment':
                      'Mood improved steadily after reassurance and breathing prompts.',
                  'keyConcerns': ['Initial anxiety', 'Shortness of breath'],
                  'recommendedActions': [
                    'Repeat breathing exercise tonight',
                    'Follow up tomorrow morning',
                  ],
                },
              }),
              200,
            );
          }
          if (path.endsWith('/transcript/segments')) {
            return http.Response(
              jsonEncode([
                {
                  'speakerLabel': 'CAREGIVER',
                  'text': 'Let us slow down your breathing together.',
                  'startMs': 0,
                  'endMs': 4000,
                  'occurredAt': '2026-03-12T15:00:30Z',
                },
                {
                  'speakerLabel': 'PATIENT',
                  'text': 'Feeling much calmer now.',
                  'startMs': 5000,
                  'endMs': 8000,
                  'occurredAt': '2026-03-12T15:00:35Z',
                },
              ]),
              200,
            );
          }
          if (path.endsWith('/recording')) {
            return http.Response(
              jsonEncode({
                'status': 'STOPPED',
                'concatenationStatus': 'READY',
                'durationSeconds': 305,
                'startedAt': '2026-03-12T15:00:00Z',
                'playbackReady': true,
              }),
              200,
            );
          }
          return http.Response('', 404);
        }),
      );

      await tester.pumpWidget(
        _wrap(
          PostCallTelemetrySummaryScreen(
            callId: 'call-rich',
            recipientName: 'Sam Patient',
            onCallAgain: () => callAgainTapped += 1,
            onSendMessage: () => sendMessageTapped += 1,
          ),
        ),
      );
      await _pumpLoaded(tester);

      expect(find.text('Call summary'), findsOneWidget);
      expect(
        find.text('Patient stabilized during the check-in.'),
        findsOneWidget,
      );
      expect(
          find.textContaining('Key concerns: Initial anxiety'), findsOneWidget);
      expect(
        find.textContaining('Actions: Repeat breathing exercise tonight'),
        findsOneWidget,
      );
      expect(find.text('Call Again'), findsOneWidget);
      expect(find.text('Send Message'), findsOneWidget);

      await tester.tap(find.text('Call Again'));
      await tester.pump();
      await tester.tap(find.text('Send Message'));
      await tester.pump();

      expect(callAgainTapped, 1);
      expect(sendMessageTapped, 1);
    });

    testWidgets(
        'timeline tap loads inline clip player when playback is ready',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var playbackFetchCount = 0;

      ApiService.debugSetHttpClient(
        MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/telemetry')) {
            return _richTelemetryResponse();
          }
          if (path.endsWith('/summary')) {
            return http.Response('', 404);
          }
          if (path.endsWith('/transcript/segments')) {
            return http.Response(jsonEncode(<Map<String, dynamic>>[]), 200);
          }
          if (path.endsWith('/recording') &&
              !path.endsWith('/recording/playback-url')) {
            return http.Response(
              jsonEncode({
                'status': 'STOPPED',
                'concatenationStatus': 'READY',
                'durationSeconds': 305,
                'startedAt': '2026-03-12T15:00:00Z',
                'playbackReady': true,
                'initiatedByUserId': 42,
              }),
              200,
            );
          }
          if (path.contains('/recording/playback-url')) {
            playbackFetchCount += 1;
            return http.Response(
              jsonEncode({
                'playbackUrl': 'https://example.com/recording.mp4',
                'recordingStartedAt': '2026-03-12T15:00:00Z',
                'expiresInMinutes': 15,
                'playbackReady': true,
              }),
              200,
            );
          }
          return http.Response('', 404);
        }),
      );

      await tester.pumpWidget(
        _wrap(
          const PostCallTelemetrySummaryScreen(
            callId: 'call-clip-ready',
            recipientName: 'Sam Patient',
          ),
        ),
      );
      await _pumpLoaded(tester);

      expect(find.byType(SentimentClipPlayerWidget), findsNothing);

      await _tapTimelineNearFirstVoiceSample(tester);
      await _pumpClipLoaded(tester);

      expect(playbackFetchCount, 1);
      expect(find.byType(SentimentClipPlayerWidget), findsOneWidget);
      expect(find.text(kSentimentClipRecordingStatusAvailable), findsOneWidget);
      expect(find.textContaining('Selected sample:'), findsOneWidget);

      await _tapTimelineNearSecondVoiceSample(tester);
      await _pumpClipLoaded(tester);

      expect(playbackFetchCount, 1);
      expect(find.byType(SentimentClipPlayerWidget), findsOneWidget);
    });

    testWidgets('dismiss button hides sentiment clip panel', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      ApiService.debugSetHttpClient(
        MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/telemetry')) {
            return _richTelemetryResponse();
          }
          if (path.endsWith('/summary')) {
            return http.Response('', 404);
          }
          if (path.endsWith('/transcript/segments')) {
            return http.Response(jsonEncode(<Map<String, dynamic>>[]), 200);
          }
          if (path.endsWith('/recording') &&
              !path.endsWith('/recording/playback-url')) {
            return http.Response(
              jsonEncode({
                'status': 'STOPPED',
                'concatenationStatus': 'READY',
                'playbackReady': true,
                'initiatedByUserId': 42,
              }),
              200,
            );
          }
          if (path.contains('/recording/playback-url')) {
            return http.Response(
              jsonEncode({
                'playbackUrl': 'https://example.com/recording.mp4',
                'recordingStartedAt': '2026-03-12T15:00:00Z',
                'playbackReady': true,
              }),
              200,
            );
          }
          return http.Response('', 404);
        }),
      );

      await tester.pumpWidget(
        _wrap(
          const PostCallTelemetrySummaryScreen(
            callId: 'call-clip-dismiss',
            recipientName: 'Sam Patient',
          ),
        ),
      );
      await _pumpLoaded(tester);
      await _tapTimelineNearFirstVoiceSample(tester);
      await _pumpClipLoaded(tester);

      expect(find.byType(SentimentClipPlayerWidget), findsOneWidget);

      await tester.tap(find.byKey(const Key('dismiss_sentiment_clip')));
      await tester.pump();

      expect(find.byType(SentimentClipPlayerWidget), findsNothing);
      expect(find.text('Sentiment clip'), findsNothing);
    });

    testWidgets('timeline tap does not load clip when playback is not ready',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      ApiService.debugSetHttpClient(
        MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/telemetry')) {
            return _richTelemetryResponse();
          }
          if (path.endsWith('/summary')) {
            return http.Response('', 404);
          }
          if (path.endsWith('/transcript/segments')) {
            return http.Response(jsonEncode(<Map<String, dynamic>>[]), 200);
          }
          if (path.endsWith('/recording') &&
              !path.endsWith('/recording/playback-url')) {
            return http.Response(
              jsonEncode({
                'status': 'STOPPED',
                'concatenationStatus': 'PROCESSING',
                'durationSeconds': 305,
                'startedAt': '2026-03-12T15:00:00Z',
                'playbackReady': false,
                'initiatedByUserId': 42,
              }),
              200,
            );
          }
          if (path.endsWith('/recording/playback-url')) {
            fail('playback-url should not be fetched when playbackReady is false');
          }
          return http.Response('', 404);
        }),
      );

      await tester.pumpWidget(
        _wrap(
          const PostCallTelemetrySummaryScreen(
            callId: 'call-clip-pending',
            recipientName: 'Sam Patient',
          ),
        ),
      );
      await _pumpLoaded(tester);

      expect(find.text(kSentimentClipRecordingStatusProcessing), findsOneWidget);

      await _tapTimelineNearFirstVoiceSample(tester);
      await _pumpClipLoaded(tester);

      expect(find.byType(SentimentClipPlayerWidget), findsNothing);
      expect(find.text(kSentimentClipRecordingProcessingSnackBar), findsOneWidget);
    });

    testWidgets(
        'system-only recording shows unavailable status and silent dot tap',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      ApiService.debugSetHttpClient(
        MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/telemetry')) {
            return _richTelemetryResponse();
          }
          if (path.endsWith('/summary')) {
            return http.Response('', 404);
          }
          if (path.endsWith('/transcript/segments')) {
            return http.Response(jsonEncode(<Map<String, dynamic>>[]), 200);
          }
          if (path.endsWith('/recording') &&
              !path.endsWith('/recording/playback-url')) {
            return http.Response(
              jsonEncode({
                'status': 'STOPPED',
                'concatenationStatus': 'READY',
                'playbackReady': false,
                'initiatedByUserId': null,
              }),
              200,
            );
          }
          if (path.contains('/recording/playback-url')) {
            fail('playback-url should not be fetched for system-only recording');
          }
          return http.Response('', 404);
        }),
      );

      await tester.pumpWidget(
        _wrap(
          const PostCallTelemetrySummaryScreen(
            callId: 'call-system-only',
            recipientName: 'Sam Patient',
          ),
        ),
      );
      await _pumpLoaded(tester);

      expect(find.text(kSentimentClipRecordingStatusUnavailable), findsOneWidget);

      await _tapTimelineNearFirstVoiceSample(tester);
      await _pumpClipLoaded(tester);

      expect(find.byType(SentimentClipPlayerWidget), findsNothing);
      expect(find.text(kSentimentClipRecordingProcessingSnackBar), findsNothing);
    });
  });
}
