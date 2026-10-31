// Coverage-focused PostCallTelemetrySummaryScreen flows:
//   * timeline sample selection with transcript segments (badges, nearest
//     segment fallback, segment range formats) in light and dark themes,
//   * timeline window dropdown (first/last N min, custom range slider),
//   * channel filter with no samples / call with no sentiment samples,
//   * distressed time-in-state breakdown and label normalisation,
//   * auto-dismiss cancelled by user interaction and pull-to-refresh.

import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/utils/sentiment_clip_recording_status.dart';
import 'package:care_connect_app/widgets/post_call_telemetry_summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// 5 minute call. Samples are all distressed and come from mixed channel
/// encodings so channel resolution falls back on the event type.
final List<Map<String, dynamic>> _mixedTelemetry = [
  {'eventType': 'CALL_STARTED', 'occurredAt': '2026-03-12T15:00:00Z'},
  {
    'eventType': 'SENTIMENT_TEXT',
    'sentimentScore': 0.1,
    'sentimentLabel': 'POSITIVE',
    'occurredAt': '2026-03-12T15:00:30Z',
  },
  {
    'eventType': 'SENTIMENT_AUDIO',
    'sentimentScore': 0.2,
    'sentimentLabel': 'NEGATIVE',
    'occurredAt': '2026-03-12T15:01:00Z',
  },
  {
    'eventType': 'SENTIMENT_VIDEO',
    'channel': 'VIDEO',
    'sentimentScore': 0.15,
    'sentimentLabel': 'odd',
    'occurredAt': '2026-03-12T15:02:00Z',
  },
  {
    'eventType': 'SENTIMENT_COMBINED',
    'sentimentScore': 0.12,
    'occurredAt': '2026-03-12T15:03:00Z',
  },
  {
    'eventType': 'SENTIMENT_VIDEO',
    'channel': 'VIDEO',
    'sentimentScore': 0.1,
    'occurredAt': '2026-03-12T15:00:35Z',
  },
  {'eventType': 'CALL_ENDED', 'occurredAt': '2026-03-12T15:05:00Z'},
];

final List<Map<String, dynamic>> _segments = [
  {
    'speakerLabel': 'CAREGIVER',
    'text': 'How are you feeling today?',
    'startMs': 25000,
    'endMs': 40000,
    'occurredAt': '2026-03-12T15:00:25Z',
  },
  {
    'speakerLabel': 'PATIENT',
    'text': 'Not great honestly.',
    'startMs': 55000,
    'occurredAt': '2026-03-12T15:00:55Z',
  },
  {
    'text': 'Only an end marker here.',
    'endMs': '130000',
    'occurredAt': '2026-03-12T15:02:10Z',
  },
  {
    'speakerLabel': 'CAREGIVER',
    'text': 'No offsets on this one.',
    'occurredAt': '2026-03-12T15:03:00Z',
  },
  {'speakerLabel': 'PATIENT', 'text': '   ', 'startMs': 1, 'endMs': 2},
];

MockClient _client({
  required List<Map<String, dynamic>> telemetry,
  List<Map<String, dynamic>> segments = const [],
}) =>
    MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/telemetry')) {
        return http.Response(jsonEncode(telemetry), 200);
      }
      if (path.endsWith('/transcript/segments')) {
        return http.Response(jsonEncode(segments), 200);
      }
      return http.Response('', 404);
    });

Future<void> _settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(
  WidgetTester tester,
  MockClient client, {
  ThemeData? theme,
  bool autoDismiss = false,
}) async {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  ApiService.debugSetHttpClient(client);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PostCallTelemetrySummaryScreen(
        callId: 'call-cov',
        recipientName: 'Pat',
        autoDismiss: autoDismiss,
        autoDismissSeconds: 30,
      ),
    ),
  );
  await tester.pump();
  await _settle(tester);
}

final _canvas = find.byKey(const Key('sentiment_timeline_canvas'));

/// Taps the plot where a sample at [minute] (of a [duration]-minute window)
/// with [score] is drawn, using the painter's padding constants.
Future<void> _tapSample(
  WidgetTester tester, {
  required double minute,
  required double score,
  double duration = 5,
}) async {
  final box = tester.renderObject<RenderBox>(_canvas);
  final w = box.size.width;
  final h = box.size.height;
  final x = 72 + (minute / duration) * (w - 92);
  final y = 20 + (1 - score) * (h - 64);
  await tester.tapAt(box.localToGlobal(Offset(x, y)));
  await tester.pump();
  await _settle(tester, frames: 5);
}

Future<void> _chooseWindow(
    WidgetTester tester, String from, String label) async {
  await tester.tap(find.text(from).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text(label).last);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async => null);
  });

  tearDown(() {
    ApiService.debugResetHttpClient();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });

  for (final dark in [false, true]) {
    testWidgets('selecting samples highlights transcript rows (dark: $dark)',
        (tester) async {
      await _pump(
        tester,
        _client(telemetry: _mixedTelemetry, segments: _segments),
        theme: dark ? ThemeData.dark() : ThemeData.light(),
      );

      // Distressed-only breakdown with sentiment label normalisation.
      expect(find.textContaining('DISTRESSED'), findsWidgets);
      // Segment range formats: start-only, end-only and occurredAt fallback.
      expect(find.textContaining('Not great honestly.'), findsOneWidget);
      expect(find.textContaining('-..:..]'), findsOneWidget);
      expect(find.textContaining('[..:..-'), findsOneWidget);
      expect(find.textContaining('No offsets on this one.'), findsOneWidget);
      expect(
        find.text('Select a plot sample to show matching sentiment badges.'),
        findsOneWidget,
      );

      // Sample at 00:30 sits inside the first transcript segment.
      await _tapSample(tester, minute: 0.5, score: 0.1);
      expect(find.textContaining('Selected sample:'), findsOneWidget);
      expect(
        find.text('Badges show the selected sample context.'),
        findsOneWidget,
      );
      expect(find.textContaining('VIDEO'), findsWidgets);

      // Sample at 01:00 is only near (not inside) the second segment.
      await _tapSample(tester, minute: 1.0, score: 0.2);
      expect(find.textContaining('Selected sample:'), findsOneWidget);

      // Expand / collapse the transcript list.
      await tester.tap(find.byTooltip('Expand'));
      await tester.pump();
      expect(find.byTooltip('Collapse'), findsOneWidget);
      await tester.tap(find.byTooltip('Collapse'));
      await tester.pump();
      expect(find.byTooltip('Expand'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('timeline window dropdown narrows and customises the plot',
      (tester) async {
    await _pump(
      tester,
      _client(telemetry: _mixedTelemetry, segments: _segments),
    );
    expect(find.text('Window: 00:00 - 05:00'), findsOneWidget);

    await _chooseWindow(tester, 'Full call', 'First 5 min');
    expect(find.text('Window: 00:00 - 05:00'), findsOneWidget);
    await _chooseWindow(tester, 'First 5 min', 'First 15 min');
    expect(find.text('Window: 00:00 - 05:00'), findsOneWidget);
    await _chooseWindow(tester, 'First 15 min', 'Last 5 min');
    expect(find.text('Window: 00:00 - 05:00'), findsOneWidget);
    await _chooseWindow(tester, 'Last 5 min', 'Last 15 min');
    expect(find.text('Window: 00:00 - 05:00'), findsOneWidget);

    await _chooseWindow(tester, 'Last 15 min', 'Custom range');
    final slider = find.byType(RangeSlider);
    expect(slider, findsOneWidget);
    final rect = tester.getRect(slider);
    // Drag the start thumb to the right to shrink the window.
    final gesture = await tester.startGesture(
      Offset(rect.left + 24, rect.center.dy),
    );
    await gesture.moveBy(Offset(rect.width / 3, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(find.text('Window: 00:00 - 05:00'), findsNothing);
    expect(find.textContaining('Window: '), findsOneWidget);

    // Back to the full call.
    await _chooseWindow(tester, 'Custom range', 'Full call');
    expect(find.text('Window: 00:00 - 05:00'), findsOneWidget);
    expect(find.byType(RangeSlider), findsNothing);
  });

  testWidgets('channel filter without samples shows a hint', (tester) async {
    await _pump(
      tester,
      _client(telemetry: [
        {'eventType': 'CALL_STARTED', 'occurredAt': '2026-03-12T15:00:00Z'},
        {
          'eventType': 'SENTIMENT_VOICE',
          'channel': 'AUDIO',
          'sentimentScore': 0.9,
          'occurredAt': '2026-03-12T15:01:00Z',
        },
        {
          'eventType': 'SENTIMENT_VOICE',
          'channel': 'VOICE',
          'sentimentScore': 0.3,
          'occurredAt': '2026-03-12T15:02:00Z',
        },
        {'eventType': 'CALL_JOIN', 'occurredAt': '2026-03-12T15:03:00Z'},
      ]),
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Video'));
    await tester.pump();
    expect(
      find.text('No samples for Video. Select another channel.'),
      findsOneWidget,
    );
    expect(find.textContaining('Participant joined'), findsWidgets);
  });

  testWidgets('long single-sample call with pending items in dark mode',
      (tester) async {
    await _pump(
      tester,
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
                'eventType': 'SENTIMENT_FINAL',
                'channel': 'COMBINED',
                'sentimentScore': 0.5,
                'occurredAt': '2026-03-12T15:30:00Z',
              },
              {
                'eventType': 'CALL_ENDED',
                'occurredAt': '2026-03-12T16:10:00Z',
              },
            ]),
            200,
          );
        }
        if (path.endsWith('/summary')) {
          return http.Response(
            jsonEncode({
              'summary': {
                'headline': 'H' * 150,
                'actionItems': [
                  {
                    'itemId': 'a1',
                    'text': 'Book bloods',
                    'needsConfirmation': true,
                  },
                ],
              },
            }),
            200,
          );
        }
        if (path.endsWith('/transcript/segments')) {
          return http.Response('[]', 200);
        }
        return http.Response('', 404);
      }),
      theme: ThemeData.dark(),
    );
    expect(find.text('Window: 00:00 - 1:10:00'), findsOneWidget);
    expect(find.text('${'H' * 100}...'), findsOneWidget);
    expect(find.text('Items to confirm'), findsOneWidget);
    expect(
      find.text(
          'Based on final assessment only — not enough readings for a full timeline.'),
      findsOneWidget,
    );
  });

  testWidgets('clip load reports playback data without a start time',
      (tester) async {
    await _pump(
      tester,
      MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/telemetry')) {
          return http.Response(jsonEncode(_mixedTelemetry), 200);
        }
        if (path.endsWith('/transcript/segments')) {
          return http.Response('[]', 200);
        }
        if (path.endsWith('/recording/playback-url')) {
          return http.Response(
            jsonEncode({'playbackUrl': 'https://example.invalid/rec.mp4'}),
            200,
          );
        }
        if (path.endsWith('/recording')) {
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
        return http.Response('', 404);
      }),
    );
    await _tapSample(tester, minute: 0.5, score: 0.1);
    expect(find.text(kSentimentClipLoadFailedSnackBar), findsOneWidget);
  });

  testWidgets('call without sentiment samples or start event', (tester) async {
    await _pump(
      tester,
      _client(telemetry: [
        {
          'eventType': 'WS_SEND_VIDEO_CALL_INVITATION',
          'occurredAt': '2026-03-12T15:00:00Z',
        },
        {'eventType': 'WS_END_CALL', 'occurredAt': '2026-03-12T15:02:00Z'},
      ]),
    );
    expect(
      find.text('No score-based sentiment samples captured for this call.'),
      findsOneWidget,
    );
  });

  testWidgets('interaction cancels auto-dismiss; pull-to-refresh reloads',
      (tester) async {
    var telemetryCalls = 0;
    await _pump(
      tester,
      MockClient((request) async {
        if (request.url.path.endsWith('/telemetry')) {
          telemetryCalls++;
          return http.Response(jsonEncode(_mixedTelemetry), 200);
        }
        return http.Response('', 404);
      }),
      autoDismiss: true,
    );
    expect(find.textContaining('Closing in'), findsOneWidget);
    await tester.tap(find.text('Call Summary'));
    await tester.pump();
    expect(find.textContaining('Closing in'), findsNothing);

    final before = telemetryCalls;
    unawaited(tester
        .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
        .show());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester, frames: 10);
    expect(telemetryCalls, greaterThan(before));
    expect(find.byType(PostCallTelemetrySummaryScreen), findsOneWidget);
  });
}
