import 'package:flutter/widgets.dart';

import 'chime_meeting_embed_stub.dart'
    if (dart.library.html) 'chime_meeting_embed_web.dart'
    if (dart.library.io) 'chime_meeting_embed_mobile.dart' as platform;

Widget buildChimeMeetingEmbed({
  required String meetingId,
  required String attendeeId,
  required String joinToken,
  required Map<String, dynamic> mediaPlacement,
  String? mediaRegion,
  String? externalUserId,
  required bool videoEnabled,
  required bool audioEnabled,
  bool enableAutoSentimentCapture = false,
  int sentimentCaptureIntervalMs = 15000,
  VoidCallback? onEndCallRequested,
  void Function(Map<String, dynamic> transcriptSample)? onTranscriptSample,
  void Function(String status, String? detail)? onTranscriptStatus,
  void Function(double averageLevel, double speechRatio, double variability)?
      onVoiceMetricsSample,
  void Function(String imageBase64)? onVideoSample,
  void Function(String channel, bool muted)? onSentimentChannelState,
}) {
  return platform.buildChimeMeetingEmbed(
    meetingId: meetingId,
    attendeeId: attendeeId,
    joinToken: joinToken,
    mediaPlacement: mediaPlacement,
    mediaRegion: mediaRegion,
    externalUserId: externalUserId,
    videoEnabled: videoEnabled,
    audioEnabled: audioEnabled,
    enableAutoSentimentCapture: enableAutoSentimentCapture,
    sentimentCaptureIntervalMs: sentimentCaptureIntervalMs,
    onEndCallRequested: onEndCallRequested,
    onTranscriptSample: onTranscriptSample,
    onTranscriptStatus: onTranscriptStatus,
    onVoiceMetricsSample: onVoiceMetricsSample,
    onVideoSample: onVideoSample,
    onSentimentChannelState: onSentimentChannelState,
  );
}

Future<bool> requestChimeAudioToggle({required bool muted, String? meetingId}) {
  return platform.requestChimeAudioToggle(muted: muted, meetingId: meetingId);
}

Future<bool> requestChimeVideoToggle({required bool muted, String? meetingId}) {
  return platform.requestChimeVideoToggle(muted: muted, meetingId: meetingId);
}

Future<bool> requestChimeCameraSwitch({String? meetingId}) {
  return platform.requestChimeCameraSwitch(meetingId: meetingId);
}

Future<bool> requestChimeSentimentChannelRestart({
  required String channel,
  String? meetingId,
}) {
  return platform.requestChimeSentimentChannelRestart(
    channel: channel,
    meetingId: meetingId,
  );
}
