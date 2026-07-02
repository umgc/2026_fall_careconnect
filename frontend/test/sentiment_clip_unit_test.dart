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
  });

  group('SENT-CLIP-001 recording status + tap policy', () {
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
