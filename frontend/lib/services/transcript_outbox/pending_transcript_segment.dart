class PendingTranscriptSegment {
  const PendingTranscriptSegment({
    required this.clientSegmentId,
    required this.ownerUserId,
    required this.callId,
    required this.speakerLabel,
    required this.text,
    required this.startMs,
    required this.endMs,
    required this.source,
    required this.createdAt,
    required this.nextAttemptAt,
    this.attemptCount = 0,
  });

  final String clientSegmentId;
  final String ownerUserId;
  final String callId;
  final String speakerLabel;
  final String text;
  final int? startMs;
  final int? endMs;
  final String source;
  final DateTime createdAt;
  final DateTime nextAttemptAt;
  final int attemptCount;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'clientSegmentId': clientSegmentId,
        'ownerUserId': ownerUserId,
        'callId': callId,
        'speakerLabel': speakerLabel,
        'text': text,
        'startMs': startMs,
        'endMs': endMs,
        'source': source,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'nextAttemptAt': nextAttemptAt.toUtc().toIso8601String(),
        'attemptCount': attemptCount,
      };

  Map<String, dynamic> toUploadJson() => <String, dynamic>{
        'clientSegmentId': clientSegmentId,
        'speakerLabel': speakerLabel,
        'text': text,
        'startMs': startMs,
        'endMs': endMs,
        'source': source,
      };

  factory PendingTranscriptSegment.fromJson(Map<dynamic, dynamic> json) {
    return PendingTranscriptSegment(
      clientSegmentId: json['clientSegmentId'] as String,
      ownerUserId: json['ownerUserId'] as String,
      callId: json['callId'] as String,
      speakerLabel: json['speakerLabel'] as String,
      text: json['text'] as String,
      startMs: (json['startMs'] as num?)?.toInt(),
      endMs: (json['endMs'] as num?)?.toInt(),
      source: json['source'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      nextAttemptAt: DateTime.parse(json['nextAttemptAt'] as String).toUtc(),
      attemptCount: (json['attemptCount'] as num?)?.toInt() ?? 0,
    );
  }

  PendingTranscriptSegment scheduleRetry(DateTime nextAttempt) {
    return PendingTranscriptSegment(
      clientSegmentId: clientSegmentId,
      ownerUserId: ownerUserId,
      callId: callId,
      speakerLabel: speakerLabel,
      text: text,
      startMs: startMs,
      endMs: endMs,
      source: source,
      createdAt: createdAt,
      nextAttemptAt: nextAttempt.toUtc(),
      attemptCount: attemptCount + 1,
    );
  }
}
