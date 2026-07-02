import 'dart:math' as math;

/// ±15 s window around a sentiment sample relative to recording start (UTC).
class SentimentClipWindow {
  const SentimentClipWindow({
    required this.offsetSec,
    required this.clipStartSec,
    required this.clipEndSec,
  });

  final double offsetSec;
  final double clipStartSec;
  final double clipEndSec;
}

/// Half-width of the sentiment clip window (total clip ≈ 2× this value).
const double sentimentClipPaddingSec = 15;

/// Clip bounds for Option A client seek on the full composited MP4.
SentimentClipWindow computeSentimentClipWindow({
  required DateTime sentimentOccurredAt,
  required DateTime recordingStartedAt,
  double paddingSec = sentimentClipPaddingSec,
}) {
  final offsetSec = sentimentOccurredAt
          .toUtc()
          .difference(recordingStartedAt.toUtc())
          .inMilliseconds /
      1000.0;
  final clipStartSec = math.max(0.0, offsetSec - paddingSec);
  final clipEndSec = offsetSec + paddingSec;
  return SentimentClipWindow(
    offsetSec: offsetSec,
    clipStartSec: clipStartSec,
    clipEndSec: clipEndSec,
  );
}

Duration sentimentClipSeekPosition(double clipStartSec) {
  return Duration(milliseconds: (clipStartSec * 1000).round());
}

bool sentimentClipShouldPause({
  required Duration position,
  required double clipEndSec,
}) {
  return position.inMilliseconds >= (clipEndSec * 1000).round();
}
