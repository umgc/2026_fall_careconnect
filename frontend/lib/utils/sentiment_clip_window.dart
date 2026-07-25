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

/// Parses call telemetry / recording timestamps as UTC wall-clock.
///
/// Backend stores UTC in `timestamp without time zone`. Jackson often emits
/// those as naive ISO strings (no `Z`). Flutter's [DateTime.parse] treats naive
/// values as *local*, which shifts clip seeks by the browser UTC offset
/// whenever [recordingStartedAt] is emitted with an explicit `Z`.
DateTime parseCallUtcDateTime(dynamic input) {
  if (input is DateTime) {
    return input.toUtc();
  }
  if (input is! String) {
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
  final raw = input.trim();
  if (raw.isEmpty) {
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
  final hasOffset = raw.endsWith('Z') ||
      raw.endsWith('z') ||
      RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(raw) ||
      RegExp(r'[+-]\d{4}$').hasMatch(raw);
  final normalized = hasOffset ? raw : '${raw}Z';
  return DateTime.tryParse(normalized)?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

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

/// Caps clip end to known video duration so late-call samples pause at EOF.
double effectiveSentimentClipEndSec({
  required double clipEndSec,
  required Duration videoDuration,
}) {
  final durationSec = videoDuration.inMilliseconds / 1000.0;
  if (durationSec <= 0) {
    return clipEndSec;
  }
  return math.min(clipEndSec, durationSec);
}

/// When transcript/recording anchors diverge from call-join by ~timezone offset,
/// prefer join time so sentiment dots still align with transcript lines.
DateTime? resolveTranscriptHighlightCallStart({
  required DateTime? fromTranscriptSegments,
  required DateTime? callJoinStart,
  Duration skewThreshold = const Duration(minutes: 50),
}) {
  if (fromTranscriptSegments == null) {
    return callJoinStart;
  }
  if (callJoinStart == null) {
    return fromTranscriptSegments;
  }
  final skew = fromTranscriptSegments.difference(callJoinStart).abs();
  if (skew >= skewThreshold) {
    return callJoinStart;
  }
  return fromTranscriptSegments;
}
