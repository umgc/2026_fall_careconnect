/// Call-level recording status copy for sentiment clip playback (M8).
const String kSentimentClipRecordingStatusAvailable =
    'Video recording is available for this call.';

const String kSentimentClipRecordingStatusProcessing =
    'Video recording is processing.';

const String kSentimentClipRecordingStatusUnavailable =
    'Video playback unavailable.';

/// SnackBar when user-initiated recording is not ready yet (M19).
const String kSentimentClipRecordingProcessingSnackBar =
    'Video recording is still processing. Try again in a moment.';

const String kSentimentClipLoadFailedSnackBar =
    'Could not load video for this moment. Try again shortly.';

const String kSentimentChartDotTapHintWithVideo =
    'Tap a dot to play that moment in the video and jump to the transcript.';

const String kSentimentChartDotTapHintProcessing =
    'Tap a dot to jump to that moment in the transcript. Video will be available once processing finishes.';

const String kSentimentChartDotTapHintTranscriptOnly =
    'Tap a dot to jump to that moment in the transcript.';

bool isUserInitiatedCallRecording(Map<String, dynamic>? recording) {
  if (recording == null) {
    return false;
  }
  return recording['initiatedByUserId'] != null;
}

String? sentimentClipRecordingStatusMessage(Map<String, dynamic>? recording) {
  if (recording == null) {
    return null;
  }
  if (!isUserInitiatedCallRecording(recording)) {
    return kSentimentClipRecordingStatusUnavailable;
  }
  if (recording['playbackReady'] == true) {
    return kSentimentClipRecordingStatusAvailable;
  }
  return kSentimentClipRecordingStatusProcessing;
}

bool shouldLoadSentimentClipOnDotTap(Map<String, dynamic>? recording) {
  return isUserInitiatedCallRecording(recording) &&
      recording?['playbackReady'] == true;
}

bool shouldShowSentimentClipProcessingSnackBar(
  Map<String, dynamic>? recording,
) {
  return isUserInitiatedCallRecording(recording) &&
      recording?['playbackReady'] != true;
}

String sentimentChartDotTapHint(Map<String, dynamic>? recording) {
  if (shouldLoadSentimentClipOnDotTap(recording)) {
    return kSentimentChartDotTapHintWithVideo;
  }
  if (shouldShowSentimentClipProcessingSnackBar(recording)) {
    return kSentimentChartDotTapHintProcessing;
  }
  return kSentimentChartDotTapHintTranscriptOnly;
}
