// Additional coverage for HybridVideoCallService on non-web platforms.
//
// With no platform service attached, startCall/joinCall fail when they
// delegate to the (null) mobile service; the service must then reset its
// in-call state and rethrow. Toggle/dispose calls are null-safe no-ops.
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/services/hybrid_video_call_service.dart';

void main() {
  final service = HybridVideoCallService();

  setUp(() async {
    await service.endCall();
  });

  test('initialize completes on non-web platforms', () async {
    await service.initialize(
      userId: 'u1',
      onRemoteStreamReceived: (_) {},
      onCallEnded: () {},
    );
    expect(service.isInCall, isFalse);
  });

  test('startCall rethrows and resets state when mobile service is missing',
      () async {
    await expectLater(
      service.startCall(callId: 'c1', recipientId: 'r1'),
      throwsA(anything),
    );
    expect(service.isInCall, isFalse);
    expect(service.currentCallId, isNull);
  });

  test('startCall with audio/video disabled still resets on failure', () async {
    await expectLater(
      service.startCall(
        callId: 'c2',
        recipientId: 'r2',
        isVideoEnabled: false,
        isAudioEnabled: false,
      ),
      throwsA(anything),
    );
    expect(service.isInCall, isFalse);
  });

  test('joinCall rethrows and resets state when mobile service is missing',
      () async {
    await expectLater(
      service.joinCall(callId: 'j1'),
      throwsA(anything),
    );
    expect(service.isInCall, isFalse);
    expect(service.currentCallId, isNull);
  });

  test('toggleVideo / toggleAudio are no-ops without a mobile service',
      () async {
    await service.toggleVideo(true);
    await service.toggleVideo(false);
    await service.toggleAudio(true);
    await service.toggleAudio(false);
    expect(service.isInCall, isFalse);
  });

  test('dispose ends the call and completes', () async {
    await service.dispose();
    expect(service.isInCall, isFalse);
    expect(service.currentCallId, isNull);
  });
}
