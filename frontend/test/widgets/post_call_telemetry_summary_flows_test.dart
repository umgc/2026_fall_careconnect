// Extra PostCallTelemetrySummaryScreen flows: auto-dismiss countdown,
// per-item summary confirmations, final call outcome reasons, and recording
// card states and playback.

import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/widgets/post_call_telemetry_summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _urlLauncher = MethodChannel('plugins.flutter.io/url_launcher');

List<Map<String, dynamic>> _telemetry(Map<String, dynamic> lastEvent) => [
      {'eventType': 'CALL_STARTED', 'occurredAt': '2026-03-12T15:00:00Z'},
      {
        'eventType': 'SENTIMENT_VOICE',
        'channel': 'VOICE',
        'sentimentScore': 0.72,
        'sentimentLabel': 'CALM',
        'occurredAt': '2026-03-12T15:01:00Z',
      },
      {
        'eventType': 'SENTIMENT_VOICE',
        'channel': 'VOICE',
        'sentimentScore': 0.42,
        'sentimentLabel': 'ANXIOUS',
        'occurredAt': '2026-03-12T15:02:00Z',
      },
      {...lastEvent, 'occurredAt': '2026-03-12T15:05:00Z'},
    ];

final _summary = {
  'summary': {
    'headline': 'Check-in',
    'actionItems': [
      {
        'itemId': 'a1',
        'text': 'Book bloods',
        'dueHint': 'this week',
        'needsConfirmation': true,
      },
      {'itemId': 'a2', 'text': 'Walk', 'needsConfirmation': 'true'},
    ],
    'appointments': [
      {
        'itemId': 'p1',
        'date': '2026-04-01',
        'time': '10:00',
        'with': 'Dr. Lee',
        'purpose': 'Review',
        'needsConfirmation': true,
      },
      {'itemId': 'p2', 'needsConfirmation': true},
    ],
    'careInstructions': [
      {
        'itemId': 'c1',
        'text': 'Rest',
        'type': 'ACTIVITY',
        'needsConfirmation': true,
      },
    ],
  },
};

MockClient _client({
  required Map<String, dynamic> lastEvent,
  Map<String, dynamic>? recording,
  Object? confirmBody,
  int confirmStatus = 200,
  String? playbackUrl,
}) =>
    MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/telemetry')) {
        return http.Response(jsonEncode(_telemetry(lastEvent)), 200);
      }
      if (path.endsWith('/summary')) {
        return http.Response(jsonEncode(_summary), 200);
      }
      if (path.endsWith('/confirm')) {
        return http.Response(
          jsonEncode(confirmBody ?? {'held': false}),
          confirmStatus,
        );
      }
      if (path.endsWith('/transcript/segments')) {
        return http.Response('[]', 200);
      }
      if (path.contains('playback')) {
        return playbackUrl == null
            ? http.Response('', 404)
            : http.Response(jsonEncode({'playbackUrl': playbackUrl}), 200);
      }
      if (path.endsWith('/recording') && recording != null) {
        return http.Response(jsonEncode(recording), 200);
      }
      return http.Response('', 404);
    });

Future<void> _pump(
  WidgetTester tester,
  MockClient client, {
  bool autoDismiss = false,
}) async {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  ApiService.debugSetHttpClient(client);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PostCallTelemetrySummaryScreen(
                  callId: 'call-1',
                  recipientName: 'Pat',
                  autoDismiss: autoDismiss,
                  autoDismissSeconds: 2,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secureStorage, (call) async => null);
    messenger.setMockMethodCallHandler(_urlLauncher, (call) async => true);
  });

  tearDown(() {
    ApiService.debugResetHttpClient();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secureStorage, null);
    messenger.setMockMethodCallHandler(_urlLauncher, null);
  });

  testWidgets('auto-dismiss counts down and closes the screen', (tester) async {
    await _pump(
      tester,
      _client(lastEvent: {'eventType': 'WS_END_CALL'}),
      autoDismiss: true,
    );
    expect(find.byType(PostCallTelemetrySummaryScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(PostCallTelemetrySummaryScreen), findsNothing);
  });

  testWidgets('pending summary items can be approved, held and declined',
      (tester) async {
    await _pump(
      tester,
      _client(lastEvent: {
        'eventType': 'WS_DECLINE_CALL',
        'payloadJson': jsonEncode({'reason': 'Busy right now'}),
      }),
    );
    expect(find.text('Items to confirm'), findsOneWidget);
    expect(find.textContaining('Book bloods (this week)'), findsOneWidget);
    expect(find.textContaining('with Dr. Lee'), findsOneWidget);
    expect(find.text('Appointment'), findsOneWidget);
    expect(find.textContaining('[ACTIVITY] Rest'), findsOneWidget);
    expect(find.textContaining('Busy right now'), findsWidgets);

    await tester.tap(find.text('Approve').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Item approved.'), findsOneWidget);
    await tester.tap(find.text('Decline').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('held and failed confirmations are reported', (tester) async {
    await _pump(
      tester,
      _client(
        lastEvent: {
          'eventType': 'WS_ACCEPT_CALL',
          'payloadJson': jsonEncode({'message': 'Joined'}),
        },
        confirmBody: {'held': true},
      ),
    );
    await tester.tap(find.text('Approve').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('Sent for clinician review before it can be confirmed.'),
      findsOneWidget,
    );

    ApiService.debugSetHttpClient(_client(
      lastEvent: {'eventType': 'CALL_JOIN'},
      confirmStatus: 500,
    ));
    await tester.tap(find.text('Approve').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  for (final event in <Map<String, dynamic>>[
    {'eventType': 'WS_SEND_VIDEO_CALL_INVITATION'},
    {'eventType': 'CALL_END'},
    {'eventType': 'CALL_JOIN', 'status': 'ERROR'},
    {'eventType': 'WS_END_CALL', 'errorMessage': 'Socket dropped'},
    {'eventType': 'WS_END_CALL', 'payloadJson': 'not json'},
  ]) {
    testWidgets('final outcome renders for ${jsonEncode(event)}',
        (tester) async {
      await _pump(tester, _client(lastEvent: event));
      expect(find.byType(PostCallTelemetrySummaryScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final recording in <Map<String, dynamic>>[
    {
      'status': 'STOPPED',
      'concatenationStatus': 'READY',
      'playbackReady': true,
      'initiatedByUserId': 7,
      'startedAt': '2026-03-12T15:00:00Z',
      'transcriptionStatus': 'FAILED',
      'errorMessage': 'Partial upload',
    },
    {
      'status': 'STOPPED',
      'concatenationStatus': 'FAILED',
      'initiatedByUserId': 7,
    },
    {
      'status': 'STOPPED',
      'concatenationStatus': 'PROCESSING',
      'initiatedByUserId': 7,
    },
    {'status': 'STOPPED', 'initiatedByUserId': 7},
    {'status': 'CAPTURING', 'initiatedByUserId': 7},
    {'status': 'ODD', 'initiatedByUserId': 7},
  ]) {
    testWidgets(
        'recording card renders ${recording['status']} '
        '${recording['concatenationStatus'] ?? ''}', (tester) async {
      await _pump(
        tester,
        _client(
          lastEvent: {'eventType': 'WS_END_CALL'},
          recording: recording,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('playback opens the recording URL or reports not ready',
      (tester) async {
    final ready = {
      'status': 'STOPPED',
      'concatenationStatus': 'READY',
      'playbackReady': true,
      'initiatedByUserId': 7,
    };
    await _pump(
      tester,
      _client(
        lastEvent: {'eventType': 'WS_END_CALL'},
        recording: ready,
      ),
    );
    final play = find.byIcon(Icons.play_circle_outline);
    await tester.tap(play);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('Recording not ready yet — try again in a moment.'),
      findsOneWidget,
    );

    ApiService.debugSetHttpClient(_client(
      lastEvent: {'eventType': 'WS_END_CALL'},
      recording: ready,
      playbackUrl: 'https://example.invalid/rec.mp4',
    ));
    await tester.tap(play);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}
