package com.careconnect.service;

import com.careconnect.model.CallTelemetryEvent;
import com.careconnect.model.TerminationStep;
import com.careconnect.service.BedrockSentimentService.SentimentResult;
import com.careconnect.service.CallSessionService.TerminationProgress;
import com.careconnect.service.RecordingStopResult.Status;
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
   * <p>Ownership is renewed before and verified after every external/slow operation. Retries
   * resume at the first incomplete step. Stale owners abort with no further side effects.
   *
   * @param callId durable call identifier
   * @param actorUserId user that initiated termination, or {@code null} for recovery
   * @param claimId current termination ownership fence
   * @return whether this claim completed the durable transition to ended
   */
  public boolean execute(
      final String callId, final Long actorUserId, final UUID claimId) {
    try {
      TerminationProgress progress =
          callSessionService.renewTerminationOwnership(callId, claimId);
      if (progress == null) {
        return false;
      }

      if (!progress.isDone(TerminationStep.SENTIMENT)
          && !runSentimentStep(callId, actorUserId, claimId)) {
        return false;
      }

      progress = callSessionService.renewTerminationOwnership(callId, claimId);
      if (progress == null) {
        return false;
      }
      if (!progress.isDone(TerminationStep.SUMMARY)
          && !runSummaryStep(callId, actorUserId, claimId)) {
        return false;
      }

      progress = callSessionService.renewTerminationOwnership(callId, claimId);
      if (progress == null) {
        return false;
      }
      boolean recordingDone = progress.isDone(TerminationStep.RECORDING);
      if (!recordingDone) {
        final RecordingOutcome recording = runRecordingStep(callId, claimId);
        if (recording == RecordingOutcome.STALE) {
          return false;
        }
        recordingDone = recording == RecordingOutcome.DONE;
      }

      progress = callSessionService.renewTerminationOwnership(callId, claimId);
      if (progress == null) {
        return false;
      }
      if (!progress.isDone(TerminationStep.MEETING)
          && !runMeetingStep(callId, claimId)) {
        return false;
      }

      if (!recordingDone) {
        if (callSessionService.verifyTerminationOwnership(callId, claimId) == null) {
          return false;
        }
        callSessionService.recordTerminationRetry(
            callId, claimId, "Recording stop remains retryable");
        return false;
      }

      progress = callSessionService.renewTerminationOwnership(callId, claimId);
      if (progress == null) {
        return false;
      }
      return callSessionService.completeTermination(callId, claimId);
    } catch (RuntimeException failure) {
      if (callSessionService.verifyTerminationOwnership(callId, claimId) != null) {
        callSessionService.recordTerminationFailure(callId, claimId, failure);
      }
      throw failure;
    }
  }

  private boolean runSentimentStep(
      final String callId, final Long actorUserId, final UUID claimId) {
    if (callSessionService.renewTerminationOwnership(callId, claimId) == null) {
      return false;
    }
    ensureFinalSentiment(callId, actorUserId);
    if (callSessionService.verifyTerminationOwnership(callId, claimId) == null) {
      return false;
    }
    return callSessionService.advanceTerminationStep(
        callId, claimId, TerminationStep.SENTIMENT)
        || alreadyDone(callId, claimId, TerminationStep.SENTIMENT);
  }

  private boolean runSummaryStep(
      final String callId, final Long actorUserId, final UUID claimId) {
    if (callSessionService.renewTerminationOwnership(callId, claimId) == null) {
      return false;
    }
    final Map<String, CallTelemetryEvent> latestByChannel =
        callTelemetryService.getLatestSentimentByChannel(callId);
    callSummaryService.generateAndStoreSummary(callId, actorUserId, latestByChannel);
    if (callSessionService.verifyTerminationOwnership(callId, claimId) == null) {
      return false;
    }
    return callSessionService.advanceTerminationStep(
        callId, claimId, TerminationStep.SUMMARY)
        || alreadyDone(callId, claimId, TerminationStep.SUMMARY);
  }

  private RecordingOutcome runRecordingStep(final String callId, final UUID claimId) {
    if (callSessionService.renewTerminationOwnership(callId, claimId) == null) {
      return RecordingOutcome.STALE;
    }
    final RecordingStopResult result = callRecordingService.stopRecordingTyped(callId);
    if (callSessionService.verifyTerminationOwnership(callId, claimId) == null) {
      return RecordingOutcome.STALE;
    }
    if (isRecordingAdvanced(result.status())) {
      if (callSessionService.advanceTerminationStep(
              callId, claimId, TerminationStep.RECORDING)
          || alreadyDone(callId, claimId, TerminationStep.RECORDING)) {
        return RecordingOutcome.DONE;
      }
      return RecordingOutcome.STALE;
    }
    // Keep ownership through meeting shutdown; park for retry only after MEETING.
    return RecordingOutcome.DEFERRED;
  }

  private boolean runMeetingStep(final String callId, final UUID claimId) {
    if (callSessionService.renewTerminationOwnership(callId, claimId) == null) {
      return false;
    }
    chimeService.endMeeting(callId);
    if (callSessionService.verifyTerminationOwnership(callId, claimId) == null) {
      return false;
    }
    return callSessionService.advanceTerminationStep(
        callId, claimId, TerminationStep.MEETING)
        || alreadyDone(callId, claimId, TerminationStep.MEETING);
  }

  private boolean alreadyDone(
      final String callId, final UUID claimId, final TerminationStep step) {
    final TerminationProgress progress =
        callSessionService.verifyTerminationOwnership(callId, claimId);
    return progress != null && progress.isDone(step);
  }

  private static boolean isRecordingAdvanced(final Status status) {
    return status == Status.STOPPED
        || status == Status.ALREADY_STOPPED
        || status == Status.NOT_RECORDING;
  }

  private enum RecordingOutcome {
    DONE,
    DEFERRED,
    STALE
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
