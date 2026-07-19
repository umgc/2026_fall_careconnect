package com.careconnect.service;

import com.careconnect.model.CallTelemetryEvent;
import com.careconnect.service.BedrockSentimentService.SentimentResult;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/** Executes every durable, UUID-fenced call termination step in a retry-safe order. */
@Service
@RequiredArgsConstructor
public class CallTerminationExecutor {

  private static final String FINAL_SENTIMENT_EVENT = "SENTIMENT_FINAL";
  private static final String SUCCESS = "SUCCESS";

  private final BedrockSentimentService sentimentService;
  private final CallTelemetryService callTelemetryService;
  private final CallSummaryService callSummaryService;
  private final CallRecordingService callRecordingService;
  private final ChimeService chimeService;
  private final CallSessionService callSessionService;

  /**
   * Completes all post-call artifacts and external cleanup before fencing the session as ended.
   *
   * @param callId durable call identifier
   * @param actorUserId user that initiated termination, or {@code null} for recovery
   * @param claimId current termination ownership fence
   * @return whether this claim completed the durable transition to ended
   */
  public boolean execute(
      final String callId, final Long actorUserId, final UUID claimId) {
    try {
      ensureFinalSentiment(callId, actorUserId);
      final Map<String, CallTelemetryEvent> latestByChannel =
          callTelemetryService.getLatestSentimentByChannel(callId);
      callSummaryService.generateAndStoreSummary(callId, actorUserId, latestByChannel);
      callRecordingService.stopRecording(callId);
      chimeService.endMeeting(callId);
      return callSessionService.completeTermination(callId, claimId);
    } catch (RuntimeException failure) {
      callSessionService.recordTerminationFailure(callId, claimId, failure);
      throw failure;
    }
  }

  private void ensureFinalSentiment(final String callId, final Long actorUserId) {
    final boolean alreadyRecorded = callTelemetryService.getTelemetryForCall(callId).stream()
        .anyMatch(event -> FINAL_SENTIMENT_EVENT.equalsIgnoreCase(event.getEventType())
            && SUCCESS.equalsIgnoreCase(event.getStatus()));
    if (alreadyRecorded) {
      return;
    }

    final Map<String, CallTelemetryEvent> latestByChannel =
        callTelemetryService.getLatestSentimentByChannel(callId);
    final Map<String, SentimentResult> channelResults = new LinkedHashMap<>();
    for (final Map.Entry<String, CallTelemetryEvent> entry : latestByChannel.entrySet()) {
      final CallTelemetryEvent event = entry.getValue();
      if (event == null || event.getSentimentScore() == null) {
        continue;
      }
      final String channel = entry.getKey().trim().toUpperCase(Locale.ROOT);
      channelResults.put(
          channel,
          new SentimentResult(
              event.getSentimentScore(),
              event.getSentimentLabel() == null ? "ANXIOUS" : event.getSentimentLabel(),
              event.getSentimentNotes() == null ? "" : event.getSentimentNotes(),
              channel,
              callId,
              event.getAnalysisTimestamp() == null
                  ? System.currentTimeMillis()
                  : event.getAnalysisTimestamp(),
              false));
    }

    final SentimentResult finalResult =
        sentimentService.analyzeFinalOverallSentiment(callId, channelResults);
    callTelemetryService.recordSentimentEvent(
        callId,
        FINAL_SENTIMENT_EVENT,
        "COMBINED",
        actorUserId,
        null,
        "END_CALL",
        finalResult,
        Map.of(
            "overallScore", finalResult.score(),
            "overallLabel", finalResult.label(),
            "status", "FINAL_END_CALL"),
        SUCCESS,
        null);
  }
}
