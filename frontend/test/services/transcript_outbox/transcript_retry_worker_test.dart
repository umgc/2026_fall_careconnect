import 'dart:async';

import 'package:care_connect_app/services/transcript_outbox/encrypted_transcript_outbox.dart';
import 'package:care_connect_app/services/transcript_outbox/pending_transcript_segment.dart';
import 'package:care_connect_app/services/transcript_outbox/transcript_retry_worker.dart';
import 'package:care_connect_app/services/transcript_outbox/transcript_upload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _QueuedUploader implements TranscriptSegmentUploader {
  _QueuedUploader(this.outcomes);

  final List<TranscriptUploadOutcome> outcomes;
  final List<String> uploadedIds = <String>[];

  @override
  Future<TranscriptUploadOutcome> upload(
    PendingTranscriptSegment segment,
    String jwtToken,
  ) async {
    uploadedIds.add(segment.clientSegmentId);
    return outcomes.removeAt(0);
  }
}

PendingTranscriptSegment _segment() {
  final now = DateTime.utc(2026, 7, 19);
  return PendingTranscriptSegment(
    clientSegmentId: 'fba0d581-2145-4201-9b0a-360a878253cc',
    ownerUserId: '7',
    callId: 'call-1',
    speakerLabel: 'PATIENT',
    text: 'persist across restart',
    startMs: 0,
    endMs: 1000,
    source: 'test',
    createdAt: now,
    nextAttemptAt: now,
  );
}

void main() {
  test('classifies response policy and Retry-After', () {
    expect(
      classifyTranscriptUploadResponse(http.Response('{}', 401)),
      isA<TranscriptUploadAuthPaused>(),
    );
    for (final status in <int>[400, 403, 404, 410, 422]) {
      expect(
        classifyTranscriptUploadResponse(http.Response('{}', status)),
        isA<TranscriptUploadTerminal>(),
      );
    }
    final retry = classifyTranscriptUploadResponse(
      http.Response('{}', 429, headers: {'retry-after': '17'}),
    ) as TranscriptUploadRetryable;
    expect(retry.retryAfter, const Duration(seconds: 17));
    expect(
      parseRetryAfter(
        'Sun, 19 Jul 2026 16:00:10 GMT',
        now: DateTime.utc(2026, 7, 19, 16),
      ),
      const Duration(seconds: 10),
    );
    for (final status in <int>[408, 425, 500, 503]) {
      expect(
        classifyTranscriptUploadResponse(http.Response('{}', status)),
        isA<TranscriptUploadRetryable>(),
      );
    }
    expect(
      classifyTranscriptUploadResponse(
        http.Response('{"savedSegments":0}', 200),
      ),
      isA<TranscriptUploadSucceeded>()
          .having((outcome) => outcome.duplicate, 'duplicate', isTrue),
    );
  });

  test('401 pauses until authentication is refreshed', () async {
    final outbox = MemoryTranscriptOutbox();
    await outbox.add(_segment());
    final uploader = _QueuedUploader(<TranscriptUploadOutcome>[
      const TranscriptUploadAuthPaused(),
      const TranscriptUploadSucceeded(),
    ]);
    final worker = TranscriptRetryWorker(
      outbox: outbox,
      uploader: uploader,
      jwtToken: 'expired',
      clock: () => DateTime.utc(2026, 7, 19),
    );

    await worker.wake();
    expect(worker.isAuthPaused, isTrue);
    expect(await outbox.all(), hasLength(1));

    await worker.updateAuth('fresh');
    expect(await outbox.all(), isEmpty);
    expect(uploader.uploadedIds,
        [_segment().clientSegmentId, _segment().clientSegmentId]);
    await worker.dispose();
  });

  test('restart and forced hang-up retry preserve client UUID', () async {
    final outbox = MemoryTranscriptOutbox();
    await outbox.add(_segment());
    final firstUploader = _QueuedUploader(<TranscriptUploadOutcome>[
      const TranscriptUploadRetryable(),
    ]);
    final firstWorker = TranscriptRetryWorker(
      outbox: outbox,
      uploader: firstUploader,
      jwtToken: 'token',
      clock: () => DateTime.utc(2026, 7, 19),
      randomDouble: () => 0.5,
    );
    await firstWorker.wake();
    await firstWorker.dispose();

    final restartedUploader = _QueuedUploader(<TranscriptUploadOutcome>[
      const TranscriptUploadSucceeded(),
    ]);
    final restartedWorker = TranscriptRetryWorker(
      outbox: outbox,
      uploader: restartedUploader,
      jwtToken: 'token',
      clock: () => DateTime.utc(2026, 7, 19),
    );
    await restartedWorker.wake(force: true);

    expect(await outbox.all(), isEmpty);
    expect(firstUploader.uploadedIds.single, _segment().clientSegmentId);
    expect(restartedUploader.uploadedIds.single, _segment().clientSegmentId);
    await restartedWorker.dispose();
  });

  test('retry uses capped jittered exponential backoff', () async {
    final now = DateTime.utc(2026, 7, 19);
    final outbox = MemoryTranscriptOutbox();
    await outbox.add(_segment());
    final worker = TranscriptRetryWorker(
      outbox: outbox,
      uploader: _QueuedUploader(<TranscriptUploadOutcome>[
        const TranscriptUploadRetryable(),
      ]),
      jwtToken: 'token',
      clock: () => now,
      randomDouble: () => 0.25,
    );

    await worker.wake();

    final pending = (await outbox.all()).single;
    expect(pending.attemptCount, 1);
    expect(
      pending.nextAttemptAt,
      now.add(const Duration(milliseconds: 1500)),
    );
    await worker.dispose();
  });

  test('connectivity wake drains a due segment', () async {
    final outbox = MemoryTranscriptOutbox();
    await outbox.add(_segment());
    final connectivity = StreamController<bool>.broadcast();
    final uploader = _QueuedUploader(<TranscriptUploadOutcome>[
      const TranscriptUploadSucceeded(),
    ]);
    final worker = TranscriptRetryWorker(
      outbox: outbox,
      uploader: uploader,
      jwtToken: 'token',
      connectivityChanges: connectivity.stream,
      clock: () => DateTime.utc(2026, 7, 19),
    );

    connectivity.add(true);
    await Future<void>.delayed(Duration.zero);
    await worker.wake();
    expect(await outbox.all(), isEmpty);
    await connectivity.close();
    await worker.dispose();
  });
}
