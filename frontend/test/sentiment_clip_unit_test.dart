// Feature traceability — Sentiment Clip Feature (SENT-CLIP-001..003 unit coverage).
//
// Widget / integration cases:
//   SENT-CLIP-004..006 → post_call_telemetry_summary_screen_test.dart
// Backend:
//   SENT-CLIP-002 → CallRecordingServiceTest.generatePlaybackUrl_withRecording_returnsUrl

import 'package:care_connect_app/utils/sentiment_clip_recording_status.dart';
import 'package:care_connect_app/utils/sentiment_clip_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SENT-CLIP-001 computeSentimentClipWindow', () {
    test('UTC offset with default ±15 s padding', () {
      final window = computeSentimentClipWindow(
        sentimentOccurredAt: DateTime.utc(2026, 6, 20, 12, 1, 45),
        recordingStartedAt: DateTime.utc(2026, 6, 20, 12, 0, 0),
      );

      expect(window.offsetSec, 105);
      expect(window.clipStartSec, 90);
      expect(window.clipEndSec, 120);
    });

    test('post-call offset at 60 s → 45–75 s clip', () {
      final window = computeSentimentClipWindow(
        sentimentOccurredAt: DateTime.parse('2026-03-12T15:01:00Z'),
        recordingStartedAt: DateTime.parse('2026-03-12T15:00:00Z'),
      );

      expect(window.offsetSec, 60);
      expect(window.clipStartSec, 45);
      expect(window.clipEndSec, 75);
    });

    test('clamps clip start at zero for early sentiment', () {
      final window = computeSentimentClipWindow(
        sentimentOccurredAt: DateTime.utc(2026, 6, 20, 12, 0, 10),
        recordingStartedAt: DateTime.utc(2026, 6, 20, 12, 0, 0),
      );

      expect(window.offsetSec, 10);
      expect(window.clipStartSec, 0);
      expect(window.clipEndSec, 25);
    });

    test('normalizes local timestamps to UTC', () {
      final window = computeSentimentClipWindow(
        sentimentOccurredAt:
            DateTime.parse('2026-06-20T08:02:00-04:00').toUtc(),
        recordingStartedAt:
            DateTime.parse('2026-06-20T08:00:00-04:00').toUtc(),
      );

      expect(window.offsetSec, 120);
      expect(window.clipStartSec, 105);
      expect(window.clipEndSec, 135);
    });

    test('honors custom paddingSec', () {
      final window = computeSentimentClipWindow(
        sentimentOccurredAt: DateTime.utc(2026, 6, 20, 12, 1, 0),
        recordingStartedAt: DateTime.utc(2026, 6, 20, 12, 0, 0),
        paddingSec: 10,
      );

      expect(window.clipStartSec, 50);
      expect(window.clipEndSec, 70);
    });

    test('default padding matches sentimentClipPaddingSec', () {
      final window = computeSentimentClipWindow(
        sentimentOccurredAt: DateTime.utc(2026, 6, 20, 12, 0, 20),
        recordingStartedAt: DateTime.utc(2026, 6, 20, 12, 0, 0),
      );

      expect(sentimentClipPaddingSec, 15);
      expect(window.clipStartSec, 5);
      expect(window.clipEndSec, 35);
    });

    test('Instant Z recordingStartedAt aligns clip window with UTC sentiment', () {
      // Mirrors backend R1 emit: LocalDateTime UTC wall-clock → Instant ...Z
      final recordingStartedAt =
          DateTime.parse('2026-07-07T22:07:12Z').toUtc();
      final sentimentOccurredAt =
          DateTime.parse('2026-07-07T22:08:12.000Z').toUtc();

      final window = computeSentimentClipWindow(
        sentimentOccurredAt: sentimentOccurredAt,
        recordingStartedAt: recordingStartedAt,
      );

      expect(window.offsetSec, 60);
      expect(window.clipStartSec, 45);
      expect(window.clipEndSec, 75);
    });

    test('naive telemetry occurredAt + Z recordingStartedAt stays aligned', () {
      // Production bug: recording emits ...Z, telemetry emits naive ISO. Flutter
      // DateTime.parse treats naive as local and shifts the clip by UTC offset.
      final recordingStartedAt = parseCallUtcDateTime('2026-07-25T04:29:50.103811Z');
      final sentimentOccurredAt =
          parseCallUtcDateTime('2026-07-25T04:30:02.299377');

      final window = computeSentimentClipWindow(
        sentimentOccurredAt: sentimentOccurredAt,
        recordingStartedAt: recordingStartedAt,
      );

      expect(window.offsetSec, closeTo(12.195566, 0.001));
      expect(window.clipStartSec, 0);
      expect(window.clipEndSec, closeTo(27.195566, 0.001));
    });

    test('mis-tagged local wall-clock as Z shifts clip by hours (regression guard)',
        () {
      // What broke after labeling LocalDateTime.now() (Eastern) as UTC Instant.
      final falselyUtcLabeledEasternWall =
          DateTime.parse('2026-07-07T18:07:12Z').toUtc();
      final trueUtcSentiment =
          DateTime.parse('2026-07-07T22:08:12Z').toUtc();

      final window = computeSentimentClipWindow(
        sentimentOccurredAt: trueUtcSentiment,
        recordingStartedAt: falselyUtcLabeledEasternWall,
      );

      expect(window.offsetSec, greaterThan(3 * 3600));
    });
  });

  group('parseCallUtcDateTime', () {
    test('treats naive ISO as UTC wall-clock', () {
      final parsed = parseCallUtcDateTime('2026-07-25T04:29:50.103811');
      expect(parsed.isUtc, isTrue);
      expect(parsed.toIso8601String(), startsWith('2026-07-25T04:29:50'));
    });

    test('preserves explicit offsets', () {
      final parsed = parseCallUtcDateTime('2026-07-25T00:29:50.103811Z');
      expect(parsed.toUtc().hour, 0);
    });
  });

  group('transcript highlight call-start skew', () {
    test('prefers call-join when transcript anchor is ~4h skewed', () {
      final join = DateTime.utc(2026, 7, 24, 20, 47, 37);
      final skewedRecordingAnchor = DateTime.utc(2026, 7, 24, 16, 48, 14);
      expect(
        resolveTranscriptHighlightCallStart(
          fromTranscriptSegments: skewedRecordingAnchor,
          callJoinStart: join,
        ),
        join,
      );
    });

    test('keeps transcript anchor when clocks agree', () {
      final join = DateTime.utc(2026, 7, 24, 20, 47, 37);
      final recordingAnchor = DateTime.utc(2026, 7, 24, 20, 48, 14);
      expect(
        resolveTranscriptHighlightCallStart(
          fromTranscriptSegments: recordingAnchor,
          callJoinStart: join,
        ),
        recordingAnchor,
      );
    });
  });

  group('SENT-CLIP-001 playback helpers', () {
    test('sentimentClipSeekPosition rounds to milliseconds', () {
      expect(
        sentimentClipSeekPosition(42.5),
        const Duration(milliseconds: 42500),
      );
    });

    test('sentimentClipShouldPause at clip end boundary', () {
      expect(
        sentimentClipShouldPause(
          position: const Duration(seconds: 59, milliseconds: 999),
          clipEndSec: 60,
        ),
        isFalse,
      );
      expect(
        sentimentClipShouldPause(
          position: const Duration(seconds: 60),
          clipEndSec: 60,
        ),
        isTrue,
      );
    });

    test('effectiveSentimentClipEndSec clamps to video duration', () {
      expect(
        effectiveSentimentClipEndSec(
          clipEndSec: 120,
          videoDuration: const Duration(seconds: 90),
        ),
        90,
      );
      expect(
        effectiveSentimentClipEndSec(
          clipEndSec: 45,
          videoDuration: const Duration(seconds: 90),
        ),
        45,
      );
      expect(
        effectiveSentimentClipEndSec(
          clipEndSec: 45,
          videoDuration: Duration.zero,
        ),
        45,
      );
    });
  });

  group('SENT-CLIP-001 recording status + tap policy', () {
    test('isUserInitiatedCallRecording treats numeric and non-empty string ids', () {
      expect(isUserInitiatedCallRecording({'initiatedByUserId': 42}), isTrue);
      expect(isUserInitiatedCallRecording({'initiatedByUserId': '2'}), isTrue);
      expect(isUserInitiatedCallRecording({'initiatedByUserId': null}), isFalse);
      expect(isUserInitiatedCallRecording({'initiatedByUserId': ''}), isFalse);
      expect(isUserInitiatedCallRecording({'initiatedByUserId': 'null'}), isFalse);
      expect(isUserInitiatedCallRecording(null), isFalse);
    });

    test('status messages for available / processing / unavailable', () {
      expect(
        sentimentClipRecordingStatusMessage({
          'initiatedByUserId': 42,
          'playbackReady': true,
        }),
        kSentimentClipRecordingStatusAvailable,
      );
      expect(
        sentimentClipRecordingStatusMessage({
          'initiatedByUserId': 42,
          'playbackReady': false,
        }),
        kSentimentClipRecordingStatusProcessing,
      );
      expect(
        sentimentClipRecordingStatusMessage({
          'initiatedByUserId': null,
          'playbackReady': false,
        }),
        kSentimentClipRecordingStatusUnavailable,
      );
      expect(sentimentClipRecordingStatusMessage(null), isNull);
    });

    test('dot tap hints follow recording availability', () {
      expect(
        sentimentChartDotTapHint({
          'initiatedByUserId': 42,
          'playbackReady': true,
        }),
        kSentimentChartDotTapHintWithVideo,
      );
      expect(
        sentimentChartDotTapHint({
          'initiatedByUserId': 42,
          'playbackReady': false,
        }),
        kSentimentChartDotTapHintProcessing,
      );
      expect(
        sentimentChartDotTapHint(null),
        kSentimentChartDotTapHintTranscriptOnly,
      );
    });

    test('load clip only for user-initiated + playbackReady', () {
      expect(
        shouldLoadSentimentClipOnDotTap({
          'initiatedByUserId': 42,
          'playbackReady': true,
        }),
        isTrue,
      );
      expect(
        shouldLoadSentimentClipOnDotTap({
          'initiatedByUserId': 42,
          'playbackReady': false,
        }),
        isFalse,
      );
      expect(
        shouldLoadSentimentClipOnDotTap({
          'initiatedByUserId': null,
          'playbackReady': true,
        }),
        isFalse,
      );
    });

    test('SnackBar only for user-initiated while processing', () {
      expect(
        shouldShowSentimentClipProcessingSnackBar({
          'initiatedByUserId': 42,
          'playbackReady': false,
        }),
        isTrue,
      );
      expect(
        shouldShowSentimentClipProcessingSnackBar({
          'initiatedByUserId': null,
          'playbackReady': false,
        }),
        isFalse,
      );
      expect(
        shouldShowSentimentClipProcessingSnackBar({
          'initiatedByUserId': 42,
          'playbackReady': true,
        }),
        isFalse,
      );
    });
  });
}
