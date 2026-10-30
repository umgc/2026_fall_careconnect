// Flow tests for VideoCallService (lib/services/video_call_service.dart):
// sentiment posting, recording and conference endpoints, safe error
// messages, and sentiment/recording/decline/end events pushed through
// CallNotificationService (FakeWebSocketChannel). HTTP is mocked with
// http.runWithClient.

import 'dart:convert';

import 'package:care_connect_app/services/call_notification_service.dart';
import 'package:care_connect_app/services/transcript_outbox/encrypted_transcript_outbox.dart';
import 'package:care_connect_app/services/video_call_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../test_support/fake_web_socket_channel.dart';

final _joinBody = jsonEncode({
  'meetingId': 'meeting-1',
  'attendeeId': 'attendee-1',
  'joinToken': 'token-1',
  'mediaPlacement': <String, dynamic>{},
  'mediaRegion': 'us-east-1',
  'externalUserId': 'ext-7',
});

/// Routes by path suffix; [status] maps a suffix to a status code.
MockClient _client({
  Map<String, int> status = const {},
  Map<String, String> bodies = const {},
  bool throwAll = false,
}) =>
    MockClient((req) async {
      if (throwAll) throw http.ClientException('offline');
      final path = req.url.path;
      for (final entry in status.entries) {
        if (path.endsWith(entry.key)) {
          return http.Response(bodies[entry.key] ?? '{}', entry.value);
        }
      }
      if (path.endsWith('/join')) return http.Response(_joinBody, 200);
      for (final entry in bodies.entries) {
        if (path.endsWith(entry.key)) return http.Response(entry.value, 200);
      }
      return http.Response('{}', 200);
    });

Future<VideoCallService> _joined(String callId,
    {bool patientSource = true}) async {
  final service = VideoCallService(transcriptOutbox: MemoryTranscriptOutbox());
  await service.initialize(
    userId: '7',
    jwtToken: 'jwt',
    enablePatientSentimentCapture: patientSource,
  );
  final session = await service.joinCall(
    callId: callId,
    otherPartyId: '2',
    isVideoEnabled: true,
    isAudioEnabled: true,
    callContextMetadata: {'callKind': 'GENERAL'},
    patientUserId: '7',
    inviteeUserId: '2',
    scheduledVisitId: 'visit-1',
  );
  expect(session.mediaRegion, 'us-east-1');
  return service;
}

void main() {
  group('sentiment posting', () {
    test('text, voice and video samples post while in a call', () async {
      await http.runWithClient(() async {
        final service = await _joined('flows-sent-ok');
        expect(await service.sendTextForAnalysis('feeling ok'), isTrue);
        expect(
          await service.sendVoiceMetricsForAnalysis(
              averageLevel: 0.4, speechRatio: 0.5, variability: 0.1),
          isTrue,
        );
        expect(await service.sendVideoFrameForAnalysis('abcd'), isTrue);
        expect(service.meetingCredentials?['meetingId'], 'meeting-1');
        service.dispose();
      }, () => _client());
    });

    test('sentiment endpoints report failure statuses and errors', () async {
      await http.runWithClient(() async {
        final service = await _joined('flows-sent-fail');
        expect(await service.sendTextForAnalysis('x'), isFalse);
        expect(
          await service.sendVoiceMetricsForAnalysis(
              averageLevel: 0, speechRatio: 0, variability: 0),
          isFalse,
        );
        expect(await service.sendVideoFrameForAnalysis('x'), isFalse);
        service.dispose();
      }, () => _client(status: {
            '/sentiment/text': 500,
            '/sentiment/voice': 500,
            '/sentiment/video': 500,
          }));

      final throwing = VideoCallService(transcriptOutbox: MemoryTranscriptOutbox());
      await http.runWithClient(() async {
        await throwing.initialize(
            userId: '7', jwtToken: 'jwt', enablePatientSentimentCapture: true);
        await throwing.joinCall(
          callId: 'flows-sent-throw',
          otherPartyId: '2',
          isVideoEnabled: false,
          isAudioEnabled: true,
        );
      }, () => _client());
      await http.runWithClient(() async {
        expect(await throwing.sendTextForAnalysis('x'), isFalse);
        expect(
          await throwing.sendVoiceMetricsForAnalysis(
              averageLevel: 0, speechRatio: 0, variability: 0),
          isFalse,
        );
        expect(await throwing.sendVideoFrameForAnalysis('x'), isFalse);
        expect(await throwing.getRecordingStatus('flows-sent-throw'), isNull);
        expect(await throwing.getEligibleInvitees('flows-sent-throw'), isEmpty);
        expect(
            await throwing.inviteParticipant('flows-sent-throw', '3'), 'error');
        expect(await throwing.getRecordingPlaybackUrl('flows-sent-throw'),
            isNull);
      }, () => _client(throwAll: true));
      throwing.dispose();
    });

    test('non-source or idle services do not post', () async {
      final idle = VideoCallService(transcriptOutbox: MemoryTranscriptOutbox());
      expect(await idle.sendTextForAnalysis('x'), isFalse);
      expect(
        await idle.sendVoiceMetricsForAnalysis(
            averageLevel: 0, speechRatio: 0, variability: 0),
        isFalse,
      );
      expect(await idle.sendVideoFrameForAnalysis('x'), isFalse);
      expect(
          await idle.updateSentimentChannelState(
              channel: 'voice', muted: true),
          isFalse);
      expect(await idle.sendTranscriptSegment(text: 'hi'), isFalse);
      idle.trackParticipant('  ');
      idle.setPatientSentimentSourceEnabled(true);
      await idle.updateTranscriptAuthentication('new-jwt');
      await idle.endCall();
    });

    test('transcript segments estimate timings and reject blanks', () async {
      await http.runWithClient(() async {
        final service = await _joined('flows-transcript');
        expect(await service.sendTranscriptSegment(text: '   '), isFalse);
        expect(
          await service.sendTranscriptSegment(
              text: 'one two three four five six seven', speakerLabel: 'CG'),
          isTrue,
        );
        expect(
          await service.sendTranscriptSegment(
              text: 'later words', startMs: -5, endMs: -1, source: 'manual'),
          isTrue,
        );
        expect(
          await service.sendTranscriptSegment(
              text: List.filled(40, 'word').join(' '), endMs: 50000),
          isTrue,
        );
        await service.updateTranscriptAuthentication('refreshed');
        service.dispose();
      }, () => _client());
    });
  });

  group('recording and conference', () {
    test('recording start/stop/status and invitees succeed', () async {
      await http.runWithClient(() async {
        final service = await _joined('flows-rec');
        final started = await service.startRecording('flows-rec');
        expect(started['status'], 'STARTED');
        final stopped = await service.stopRecording('flows-rec');
        expect(stopped['status'], 'STOPPED');
        expect(await service.getRecordingStatus('flows-rec'),
            containsPair('state', 'ACTIVE'));
        expect(await service.getEligibleInvitees('flows-rec'), hasLength(1));
        expect(await service.inviteParticipant('flows-rec', '3'), 'ringing');
        expect(await service.getRecordingPlaybackUrl('flows-rec'),
            'https://example.test/rec.mp4');
        expect(await service.getRecordingStatus('other-call'), isNull);
        service.dispose();
      }, () => _client(bodies: {
            '/recording/start': jsonEncode({'status': 'STARTED'}),
            '/recording/stop': jsonEncode({'status': 'STOPPED'}),
            '/recording': jsonEncode({'state': 'ACTIVE'}),
            '/eligible-invitees': jsonEncode([
              {'userId': '3', 'name': 'Bea'}
            ]),
            '/invite': jsonEncode({'status': 'ringing'}),
            '/playback-url':
                jsonEncode({'url': 'https://example.test/rec.mp4'}),
          }));
    });

    test('recording rejections and failures surface safe messages', () async {
      await http.runWithClient(() async {
        final service = await _joined('flows-rec-fail');
        await expectLater(
          service.startRecording('flows-rec-fail'),
          throwsA(predicate(
              (e) => e.toString().contains('Unable to start recording'))),
        );
        await expectLater(
          service.stopRecording('flows-rec-fail'),
          throwsA(predicate((e) => e.toString().contains('permission'))),
        );
        expect(await service.getRecordingStatus('flows-rec-fail'), isNull);
        expect(await service.getEligibleInvitees('flows-rec-fail'), isEmpty);
        expect(await service.inviteParticipant('flows-rec-fail', '3'), 'error');
        expect(
            await service.getRecordingPlaybackUrl('flows-rec-fail'), isNull);
        expect(() => service.startRecording('wrong-call'), throwsStateError);
        service.dispose();
      }, () => _client(status: {
            '/recording/stop': 403,
            '/recording': 404,
            '/eligible-invitees': 500,
            '/invite': 500,
            '/playback-url': 500,
          }, bodies: {
            '/recording/start': jsonEncode({'status': 'FAILED'}),
          }));

      await http.runWithClient(() async {
        final service = await _joined('flows-rec-5xx');
        await expectLater(
          service.startRecording('flows-rec-5xx'),
          throwsA(predicate(
              (e) => e.toString().contains('temporarily unavailable'))),
        );
        service.dispose();
      }, () => _client(status: {'/recording/start': 503}));
    });

    test('create session and join map status codes to safe messages',
        () async {
      final cases = <int, String>{
        401: 'session expired',
        403: 'do not have permission',
        404: 'was not found',
        500: 'temporarily unavailable',
        400: 'check the call details',
      };
      for (final entry in cases.entries) {
        final service =
            VideoCallService(transcriptOutbox: MemoryTranscriptOutbox());
        await http.runWithClient(() async {
          await service.initialize(
              userId: '7', jwtToken: 'jwt', enablePatientSentimentCapture: false);
          await expectLater(
            service.createCallSession(
              callId: 'c-${entry.key}',
              patientUserId: '7',
              inviteeUserId: '2',
              scheduledVisitId: 'v1',
            ),
            throwsA(predicate((e) => e.toString().contains(entry.value))),
          );
        }, () => _client(status: {'/sessions': entry.key}));
        service.dispose();
      }

      final service = VideoCallService(transcriptOutbox: MemoryTranscriptOutbox());
      await http.runWithClient(() async {
        await service.initialize(
            userId: '7', jwtToken: 'jwt', enablePatientSentimentCapture: false);
        await expectLater(
          service.joinCall(
            callId: 'flows-join-404',
            otherPartyId: '2',
            isVideoEnabled: true,
            isAudioEnabled: true,
          ),
          throwsA(predicate((e) => e.toString().contains('Meeting gone'))),
        );
        expect(service.isInCall, isFalse);
      }, () => _client(
          status: {'/join': 404},
          bodies: {'/join': jsonEncode({'error': 'Meeting gone'})}));
      service.dispose();
    });

    test('ending a call blocks rejoining the same call id', () async {
      await http.runWithClient(() async {
        final service = await _joined('flows-end');
        await service.endCall();
        expect(service.isInCall, isFalse);
        await expectLater(
          service.joinCall(
            callId: 'flows-end',
            otherPartyId: '2',
            isVideoEnabled: true,
            isAudioEnabled: true,
          ),
          throwsA(predicate((e) => e.toString().contains('already ended'))),
        );
        service.dispose();
      }, () => _client());
    });
  });

  group('events from the notification socket', () {
    late List<FakeWebSocketChannel> sockets;

    setUp(() {
      final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
      FlutterSecureStorage.setMockInitialValues({
        'jwt_token': 'test-jwt',
        'token_expiry': '$expiry',
      });
      sockets = [];
      CallNotificationService.connectChannel = (_) {
        final socket = FakeWebSocketChannel();
        sockets.add(socket);
        return socket;
      };
    });

    tearDown(() {
      CallNotificationService.dispose();
      CallNotificationService.connectChannel = WebSocketChannel.connect;
      CallNotificationService.resetTestState();
    });

    testWidgets('sentiment, channel-state, recording, decline and end events',
        (tester) async {
      late BuildContext hostContext;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            hostContext = context;
            return const SizedBox();
          }),
        ),
      ));
      await CallNotificationService.initialize(
        userId: '7',
        userRole: 'PATIENT',
        context: hostContext,
      );

      final updates = <Map<String, dynamic>>[];
      final declines = <Map<String, dynamic>>[];
      final recordings = <Map<String, dynamic>>[];
      var ended = 0;
      final service =
          VideoCallService(transcriptOutbox: MemoryTranscriptOutbox());

      await http.runWithClient(() async {
        await service.initialize(
          userId: '7',
          jwtToken: 'jwt',
          enablePatientSentimentCapture: true,
          onCallEnded: () => ended++,
          onSentimentUpdate: updates.add,
          onCallDeclined: declines.add,
          onRecordingState: recordings.add,
        );
        await service.joinCall(
          callId: 'flows-events',
          otherPartyId: '2',
          isVideoEnabled: true,
          isAudioEnabled: true,
        );
      }, () => _client());

      final socket = sockets.single;
      Future<void> send(Map<String, dynamic> m) async {
        socket.serverSend(m);
        await tester.pump();
      }

      final old =
          DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      await send({
        'type': 'sentiment-update',
        'callId': 'flows-events',
        'captureMode': 'live',
        'sentiment': {
          'channel': 'voice',
          'score': 0.8,
          'label': 'POSITIVE',
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        },
      });
      await send({
        'type': 'sentiment-update',
        'callId': 'flows-events',
        'sentiment': {
          'voice': {'score': 0.2, 'label': 'NEGATIVE', 'timestamp': 1000},
          'video': {
            'score': 0.5,
            'label': 'NEUTRAL',
            'notes': 'analysis unavailable',
            'updatedAt': old.toIso8601String(),
          },
          'text': {'label': 'odd'},
          'overall': {'score': 0.4},
        },
      });
      await send({
        'type': 'sentiment-update',
        'callId': 'flows-events',
        'sentiment': <String, dynamic>{},
      });
      await send({
        'type': 'sentiment-channel-state',
        'callId': 'flows-events',
        'channel': 'voice',
        'muted': true,
        'captureMode': 'live',
      });
      await send({
        'type': 'sentiment-channel-state',
        'callId': 'flows-events',
        'channel': 'video',
        'status': 'quiet',
      });
      await send({
        'type': 'sentiment-channel-state',
        'callId': 'flows-events',
        'channel': 'text',
        'notes': 'typing',
      });
      await send({
        'type': 'sentiment-channel-state',
        'callId': 'flows-events',
        'channel': 'smell',
      });
      // Events for another call are ignored.
      await send({
        'type': 'sentiment-update',
        'callId': 'other',
        'sentiment': {'channel': 'voice', 'score': 0.1},
      });
      await send({
        'type': 'recording-state',
        'callId': 'flows-events',
        'state': 'RECORDING',
      });
      await send({'type': 'call-declined', 'callId': 'flows-events'});

      expect(updates, hasLength(7));
      expect(updates.first['voice']['label'], 'CALM');
      expect(updates.first['_captureMode'], 'LIVE');
      expect(updates[1]['video']['status'], 'DEGRADED');
      expect(updates[3]['voice']['status'], 'MUTED');
      expect(updates[4]['video']['status'], 'QUIET');
      expect(recordings.single['state'], 'RECORDING');
      expect(declines, hasLength(1));

      expect(
        await service.updateSentimentChannelState(
            channel: 'voice', muted: false),
        isA<bool>(),
      );

      await http.runWithClient(() async {
        await send({'type': 'call-ended', 'callId': 'flows-events'});
        await tester.pump(const Duration(milliseconds: 100));
      }, () => _client());
      expect(ended, 1);
      expect(service.isInCall, isFalse);
      service.dispose();
    });
  });
}
