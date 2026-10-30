package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.careconnect.model.CallTelemetryEvent;
import com.careconnect.service.BedrockSentimentService.SentimentResult;
import com.careconnect.service.CallSessionService.TerminationProgress;
import com.careconnect.service.conditiondetection.ConditionDetectionService;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * Drives {@link CallTerminationExecutor#execute} with ownership lost at every renew/verify
 * checkpoint in turn, so each stale-owner early return is exercised. All collaborators are mocks.
 */
@DisplayName("CallTerminationExecutor stale ownership checkpoints")
class CallTerminationExecutorStaleOwnershipTest {

    private static final String CALL_ID = "call-term-1";
    private static final UUID CLAIM = UUID.randomUUID();
    private static final TerminationProgress NOTHING_DONE = new TerminationProgress(false, false, false, false);

    private boolean runWithOwnershipLostAfter(final int ownedChecks, final boolean advance) {
        final BedrockSentimentService sentiment = mock(BedrockSentimentService.class);
        final CallTelemetryService telemetry = mock(CallTelemetryService.class);
        final CallRecordingService recording = mock(CallRecordingService.class);
        final CallSessionService sessions = mock(CallSessionService.class);
        final ConditionDetectionService detection = mock(ConditionDetectionService.class);
        final AtomicInteger checks = new AtomicInteger();
        when(sessions.renewTerminationOwnership(CALL_ID, CLAIM))
                .thenAnswer(inv -> checks.incrementAndGet() <= ownedChecks ? NOTHING_DONE : null);
        when(sessions.verifyTerminationOwnership(CALL_ID, CLAIM))
                .thenAnswer(inv -> checks.incrementAndGet() <= ownedChecks ? NOTHING_DONE : null);
        when(sessions.advanceTerminationStep(eq(CALL_ID), eq(CLAIM), any())).thenReturn(advance);
        when(sessions.completeTermination(CALL_ID, CLAIM)).thenReturn(true);
        when(sessions.requireSession(CALL_ID)).thenThrow(new RuntimeException("no session"));
        final CallTelemetryEvent voice = new CallTelemetryEvent();
        voice.setSentimentScore(0.4);
        voice.setTargetUserId(7L);
        final CallTelemetryEvent blank = new CallTelemetryEvent();
        when(telemetry.getLatestSentimentByChannel(CALL_ID)).thenReturn(Map.of("voice ", voice, "TEXT", blank));
        when(sentiment.analyzeFinalOverallSentiment(eq(CALL_ID), any()))
                .thenReturn(new SentimentResult(0.4, "ANXIOUS", "", "COMBINED", CALL_ID, 1L, false));
        when(recording.stopRecordingTyped(CALL_ID))
                .thenReturn(new RecordingStopResult(RecordingStopResult.Status.STOPPED, CALL_ID, null, null, null, null, null));
        doThrow(new RuntimeException("queue down")).when(detection).enqueueForCall(anyString());
        final CallTerminationExecutor executor = new CallTerminationExecutor(
                sentiment, telemetry, mock(CallSummaryService.class), recording, mock(ChimeService.class),
                sessions, detection);
        return executor.execute(CALL_ID, 1L, CLAIM);
    }

    @Test
    @DisplayName("losing ownership at any checkpoint aborts; keeping it to the end completes")
    void everyCheckpoint() {
        for (int owned = 0; owned < 22; owned++) {
            runWithOwnershipLostAfter(owned, true);
        }
        assertThat(runWithOwnershipLostAfter(100, true)).isTrue();
    }

    @Test
    @DisplayName("steps that do not advance and are not already done abort termination")
    void stepsNotAdvanced() {
        for (int owned = 0; owned < 22; owned++) {
            runWithOwnershipLostAfter(owned, false);
        }
        assertThat(runWithOwnershipLostAfter(100, false)).isFalse();
    }

    @Test
    @DisplayName("a recording stop that is not yet durable parks the termination for retry")
    void recordingDeferred() {
        final CallSessionService sessions = mock(CallSessionService.class);
        final CallRecordingService recording = mock(CallRecordingService.class);
        final TerminationProgress textDone = new TerminationProgress(true, true, false, false);
        when(sessions.renewTerminationOwnership(CALL_ID, CLAIM)).thenReturn(textDone);
        when(sessions.verifyTerminationOwnership(CALL_ID, CLAIM)).thenReturn(textDone).thenReturn(null);
        when(recording.stopRecordingTyped(CALL_ID))
                .thenReturn(new RecordingStopResult(RecordingStopResult.Status.RETRYABLE_FAILURE, CALL_ID, null,
                        null, null, null, null));
        final CallTerminationExecutor executor = new CallTerminationExecutor(
                mock(BedrockSentimentService.class), mock(CallTelemetryService.class), mock(CallSummaryService.class),
                recording, mock(ChimeService.class), sessions, mock(ConditionDetectionService.class));

        assertThat(executor.execute(CALL_ID, 1L, CLAIM)).isFalse();
        assertThat(executor.execute(CALL_ID, 1L, CLAIM)).isFalse();
    }
}
