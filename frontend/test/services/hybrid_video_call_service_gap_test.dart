// Gap-filling tests for HybridVideoCallService.
//
// Under flutter_test kIsWeb is false and initialize() never assigns a mobile
// service (the platform wiring is commented out in production), so every
// delegation target is null. That makes the failure and cleanup behavior of
// startCall/joinCall and the null-safe toggles/dispose observable without any
// platform plugin.

import 'package:care_connect_app/services/hybrid_video_call_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = HybridVideoCallService();

  setUp(() async {
    await service.endCall();
  });

  group('startCall', () {
    test('fails when no mobile service is available and clears call state',
        () async {
      await expectLater(
        service.startCall(callId: 'c1', recipientId: 'r1'),
        throwsA(isA<NoSuchMethodError>()),
      );

      expect(service.isInCall, isFalse);
      expect(service.currentCallId, isNull);
    });

    test('can be retried after a failure (no stuck "Already in a call")',
        () async {
      await expectLater(
        service.startCall(callId: 'c1', recipientId: 'r1'),
        throwsA(isA<NoSuchMethodError>()),
      );
      // A second attempt reaches the delegate again instead of throwing the
      // "Already in a call" guard exception.
      await expectLater(
        service.startCall(
          callId: 'c2',
          recipientId: 'r1',
          isVideoEnabled: false,
          isAudioEnabled: false,
        ),
        throwsA(isA<NoSuchMethodError>()),
      );
      expect(service.currentCallId, isNull);
    });
  });

  group('joinCall', () {
    test('fails when no mobile service is available and clears call state',
        () async {
      await expectLater(
        service.joinCall(callId: 'c9'),
        throwsA(isA<NoSuchMethodError>()),
      );

      expect(service.isInCall, isFalse);
      expect(service.currentCallId, isNull);
    });

    test('forwards audio/video flags without tripping the in-call guard',
        () async {
      await expectLater(
        service.joinCall(
          callId: 'c9',
          isVideoEnabled: false,
          isAudioEnabled: false,
        ),
        throwsA(isA<NoSuchMethodError>()),
      );
      expect(service.isInCall, isFalse);
    });
  });

  group('toggles and teardown without a mobile service', () {
    test('toggleVideo completes and leaves call state untouched', () async {
      await service.toggleVideo(true);
      await service.toggleVideo(false);
      expect(service.isInCall, isFalse);
    });

    test('toggleAudio completes and leaves call state untouched', () async {
      await service.toggleAudio(true);
      await service.toggleAudio(false);
      expect(service.isInCall, isFalse);
    });

    test('dispose ends the call and completes', () async {
      await service.dispose();
      expect(service.isInCall, isFalse);
      expect(service.currentCallId, isNull);
    });
  });

  group('initialize', () {
    test('accepts callbacks and does not start a call', () async {
      await service.initialize(
        userId: 'u1',
        onRemoteStreamReceived: (_) {},
        onCallEnded: () {},
      );
      expect(service.isInCall, isFalse);
    });
  });
}
