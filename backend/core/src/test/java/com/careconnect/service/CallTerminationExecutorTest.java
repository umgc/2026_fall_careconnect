package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.careconnect.model.CallTelemetryEvent;
import com.careconnect.model.TerminationStep;
import com.careconnect.service.BedrockSentimentService.SentimentResult;
import com.careconnect.service.CallSessionService.TerminationProgress;
import com.careconnect.service.RecordingStopResult.Status;
import com.careconnect.service.conditiondetection.ConditionDetectionService;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InOrder;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.slf4j.LoggerFactory;

@ExtendWith(MockitoExtension.class)
class CallTerminationExecutorTest {

    @Mock
    private BedrockSentimentService sentimentService;
    @Mock
    private CallTelemetryService telemetryService;
    @Mock
    private CallSummaryService summaryService;
    @Mock
    private CallRecordingService recordingService;
    @Mock
    private ChimeService chimeService;
    @Mock
    private CallSessionService sessionService;
    @Mock
    private ConditionDetectionService conditionDetectionService;

    private CallTerminationExecutor executor;

    private static TerminationProgress noneDone() {
        return new TerminationProgress(false, false, false, false);
    }

    @BeforeEach
    void setUp() {
        executor = new CallTerminationExecutor(
                sentimentService,
                telemetryService,
                summaryService,
                recordingService,
                chimeService,
                sessionService,
                conditionDetectionService);
    }

    @Test
    void execute_recoversArtifactsBeforeFencedEnd() {
        final UUID claimId = UUID.randomUUID();
        final CallTelemetryEvent voice = new CallTelemetryEvent();
        voice.setEventType("SENTIMENT_VOICE");
        voice.setChannel("VOICE");
        voice.setSentimentScore(0.6);
        voice.setSentimentLabel("CALM");
        voice.setTargetUserId(1L);
        final SentimentResult finalResult =
                SentimentResult.neutral("COMBINED", "call-1", "Recovered");
        when(sessionService.renewTerminationOwnership("call-1", claimId))
                .thenReturn(noneDone());
        when(sessionService.verifyTerminationOwnership("call-1", claimId))
                .thenReturn(noneDone());
        when(sessionService.advanceTerminationStep(eq("call-1"), eq(claimId), any()))
                .thenReturn(true);
        when(sessionService.requireSession("call-1"))
                .thenThrow(new IllegalStateException("session unavailable in unit test"));
        when(telemetryService.getTelemetryForCall("call-1")).thenReturn(List.of(voice));
        when(telemetryService.getLatestSentimentByChannel("call-1"))
                .thenReturn(Map.of("VOICE", voice));
        when(sentimentService.analyzeFinalOverallSentiment(eq("call-1"), any()))
                .thenReturn(finalResult);
        when(recordingService.stopRecordingTyped("call-1"))
                .thenReturn(new RecordingStopResult(
                        Status.STOPPED, "call-1", "pipe", "STOPPED", null, null, null));
        when(sessionService.completeTermination("call-1", claimId)).thenReturn(true);

        assertThat(executor.execute("call-1", null, claimId)).isTrue();

        verify(summaryService).generateAndStoreSummary("call-1", null, Map.of("VOICE", voice));
        final InOrder order = inOrder(
                telemetryService, summaryService, recordingService, chimeService, sessionService);
        order.verify(telemetryService).recordSentimentEvent(
                eq("call-1"),
                eq("SENTIMENT_FINAL"),
                eq("COMBINED"),
                eq(null),
                eq(1L),
                eq("END_CALL"),
                eq(finalResult),
                any(),
                eq("SUCCESS"),
                eq(null));
        order.verify(summaryService).generateAndStoreSummary(
                "call-1", null, Map.of("VOICE", voice));
        order.verify(recordingService).stopRecordingTyped("call-1");
        order.verify(chimeService).endMeeting("call-1");
        order.verify(sessionService).completeTermination("call-1", claimId);
    }

    @Test
    void execute_retriesNoTranscriptOrMissingSummaryWithoutDuplicatingFinalSentiment() {
        final UUID claimId = UUID.randomUUID();
        final CallTelemetryEvent finalEvent = new CallTelemetryEvent();
        finalEvent.setEventType("SENTIMENT_FINAL");
        finalEvent.setStatus("SUCCESS");
        when(sessionService.renewTerminationOwnership("call-1", claimId))
                .thenReturn(noneDone());
        when(sessionService.verifyTerminationOwnership("call-1", claimId))
                .thenReturn(noneDone());
        when(sessionService.advanceTerminationStep(eq("call-1"), eq(claimId), any()))
                .thenReturn(true);
        when(telemetryService.getTelemetryForCall("call-1")).thenReturn(List.of(finalEvent));
        when(telemetryService.getLatestSentimentByChannel("call-1")).thenReturn(Map.of());
        when(recordingService.stopRecordingTyped("call-1"))
                .thenReturn(new RecordingStopResult(
                        Status.NOT_RECORDING, "call-1", null, null, null, null, null));
        when(sessionService.completeTermination("call-1", claimId)).thenReturn(true);

        assertThat(executor.execute("call-1", 2L, claimId)).isTrue();

        verify(sentimentService, never()).analyzeFinalOverallSentiment(any(), any());
        verify(summaryService).generateAndStoreSummary("call-1", 2L, Map.of());
        verify(sessionService).completeTermination("call-1", claimId);
    }

    @Test
    void execute_abortsWithZeroSideEffectsWhenLeaseAlreadyLost() {
        final UUID claimId = UUID.randomUUID();
        when(sessionService.renewTerminationOwnership("call-1", claimId)).thenReturn(null);

        assertThat(executor.execute("call-1", 2L, claimId)).isFalse();

        verify(telemetryService, never()).getTelemetryForCall(any());
        verify(summaryService, never()).generateAndStoreSummary(any(), any(), any());
        verify(recordingService, never()).stopRecordingTyped(any());
        verify(chimeService, never()).endMeeting(any());
        verify(sessionService, never()).recordTerminationFailure(any(), any(), any());
        verify(sessionService, never()).completeTermination(any(), any());
    }

    @Test
    void execute_staleOwnerAfterExternalWorkDoesNotParkOrComplete() {
        final UUID claimId = UUID.randomUUID();
        when(sessionService.renewTerminationOwnership("call-1", claimId))
                .thenReturn(noneDone());
        when(sessionService.verifyTerminationOwnership("call-1", claimId))
                .thenReturn(null);
        when(telemetryService.getTelemetryForCall("call-1")).thenReturn(List.of());
        when(telemetryService.getLatestSentimentByChannel("call-1")).thenReturn(Map.of());
        when(sentimentService.analyzeFinalOverallSentiment(eq("call-1"), any()))
                .thenReturn(SentimentResult.neutral("COMBINED", "call-1", "x"));

        assertThat(executor.execute("call-1", null, claimId)).isFalse();

        verify(sessionService, never()).advanceTerminationStep(any(), any(), any());
        verify(sessionService, never()).recordTerminationFailure(any(), any(), any());
        verify(sessionService, never()).recordTerminationRetry(any(), any(), any());
        verify(sessionService, never()).completeTermination(any(), any());
        verify(summaryService, never()).generateAndStoreSummary(any(), any(), any());
    }

    @Test
    void execute_reclaimResumeSkipsCompletedSteps() {
        final UUID claimId = UUID.randomUUID();
        final TerminationProgress afterSummary = new TerminationProgress(true, true, false, false);
        when(sessionService.renewTerminationOwnership("call-1", claimId))
                .thenReturn(afterSummary);
        when(sessionService.verifyTerminationOwnership("call-1", claimId))
                .thenReturn(afterSummary);
        when(sessionService.advanceTerminationStep(eq("call-1"), eq(claimId), any()))
                .thenReturn(true);
        when(recordingService.stopRecordingTyped("call-1"))
                .thenReturn(new RecordingStopResult(
                        Status.ALREADY_STOPPED, "call-1", "pipe", "STOPPED", null, null, null));
        when(sessionService.completeTermination("call-1", claimId)).thenReturn(true);

        assertThat(executor.execute("call-1", 9L, claimId)).isTrue();

        verify(telemetryService, never()).getTelemetryForCall(any());
        verify(summaryService, never()).generateAndStoreSummary(any(), any(), any());
        verify(recordingService).stopRecordingTyped("call-1");
        verify(chimeService).endMeeting("call-1");
        verify(sessionService).advanceTerminationStep(
                "call-1", claimId, TerminationStep.RECORDING);
        verify(sessionService).advanceTerminationStep(
                "call-1", claimId, TerminationStep.MEETING);
    }

    @Test
    void execute_duplicateExecutionIsIdempotentWhenStepsAlreadyFenced() {
        final UUID claimId = UUID.randomUUID();
        final TerminationProgress allDone = new TerminationProgress(true, true, true, true);
        when(sessionService.renewTerminationOwnership("call-1", claimId)).thenReturn(allDone);
        when(sessionService.completeTermination("call-1", claimId)).thenReturn(true);

        assertThat(executor.execute("call-1", 2L, claimId)).isTrue();

        verify(recordingService, never()).stopRecordingTyped(any());
        verify(chimeService, never()).endMeeting(any());
        verify(summaryService, never()).generateAndStoreSummary(any(), any(), any());
        verify(sessionService, never()).advanceTerminationStep(any(), any(), any());
        verify(sessionService).completeTermination("call-1", claimId);
    }

    @Test
    void execute_retryableRecordingParksBeforeMeetingShutdown() {
        final UUID claimId = UUID.randomUUID();
        when(sessionService.renewTerminationOwnership("call-1", claimId))
                .thenReturn(noneDone());
        when(sessionService.verifyTerminationOwnership("call-1", claimId))
                .thenReturn(noneDone());
        when(sessionService.advanceTerminationStep(eq("call-1"), eq(claimId), any()))
                .thenReturn(true);
        when(telemetryService.getTelemetryForCall("call-1")).thenReturn(List.of());
        when(telemetryService.getLatestSentimentByChannel("call-1")).thenReturn(Map.of());
        when(sentimentService.analyzeFinalOverallSentiment(eq("call-1"), any()))
                .thenReturn(SentimentResult.neutral("COMBINED", "call-1", "x"));
        when(recordingService.stopRecordingTyped("call-1"))
                .thenReturn(new RecordingStopResult(
                        Status.RETRYABLE_FAILURE, "call-1", "pipe", "STOP_RETRYABLE",
                        null, null, "AWS unavailable"));

        assertThat(executor.execute("call-1", 2L, claimId)).isFalse();

        verify(chimeService, never()).endMeeting(any());
        verify(sessionService, never()).advanceTerminationStep(
                "call-1", claimId, TerminationStep.MEETING);
        verify(sessionService, never()).advanceTerminationStep(
                "call-1", claimId, TerminationStep.RECORDING);
        verify(sessionService).recordTerminationRetry(
                "call-1", claimId, "Recording stop remains retryable");
        verify(sessionService, never()).completeTermination(any(), any());
    }

    @Test
    void execute_recordsFailureOnlyWhileClaimStillOwned() {
        final UUID claimId = UUID.randomUUID();
        when(sessionService.renewTerminationOwnership("call-1", claimId))
                .thenReturn(noneDone());
        when(sessionService.verifyTerminationOwnership("call-1", claimId))
                .thenReturn(null);
        when(telemetryService.getTelemetryForCall("call-1")).thenReturn(List.of());
        when(telemetryService.getLatestSentimentByChannel("call-1")).thenReturn(Map.of());
        when(sentimentService.analyzeFinalOverallSentiment(eq("call-1"), any()))
                .thenThrow(new IllegalStateException("bedrock down"));

        assertThatThrownBy(() -> executor.execute("call-1", null, claimId))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("bedrock");

        verify(sessionService, never()).recordTerminationFailure(any(), any(), any());
    }

    @Test
    void execute_renewsOwnershipAroundEachExternalStep() {
        final UUID claimId = UUID.randomUUID();
        when(sessionService.renewTerminationOwnership("call-1", claimId))
                .thenReturn(noneDone());
        when(sessionService.verifyTerminationOwnership("call-1", claimId))
                .thenReturn(noneDone());
        when(sessionService.advanceTerminationStep(eq("call-1"), eq(claimId), any()))
                .thenReturn(true);
        when(telemetryService.getTelemetryForCall("call-1")).thenReturn(List.of());
        when(telemetryService.getLatestSentimentByChannel("call-1")).thenReturn(Map.of());
        when(sentimentService.analyzeFinalOverallSentiment(eq("call-1"), any()))
                .thenReturn(SentimentResult.neutral("COMBINED", "call-1", "x"));
        when(recordingService.stopRecordingTyped("call-1"))
                .thenReturn(new RecordingStopResult(
                        Status.NOT_RECORDING, "call-1", null, null, null, null, null));
        when(sessionService.completeTermination("call-1", claimId)).thenReturn(true);

        assertThat(executor.execute("call-1", null, claimId)).isTrue();

        verify(sessionService, times(9)).renewTerminationOwnership("call-1", claimId);
        verify(sessionService).advanceTerminationStep(
                "call-1", claimId, TerminationStep.SENTIMENT);
        verify(sessionService).advanceTerminationStep(
                "call-1", claimId, TerminationStep.SUMMARY);
        verify(sessionService).advanceTerminationStep(
                "call-1", claimId, TerminationStep.RECORDING);
        verify(sessionService).advanceTerminationStep(
                "call-1", claimId, TerminationStep.MEETING);
    }

    // ------------------------------------------------ condition detection hook

    /**
     * Shared arrangement: sentiment and summary are already done, so the run goes straight to
     * the RECORDING step.
     */
    private UUID arrangeAfterSummary() {
        final UUID claimId = UUID.randomUUID();
        final TerminationProgress afterSummary = new TerminationProgress(true, true, false, false);
        when(sessionService.renewTerminationOwnership("call-1", claimId)).thenReturn(afterSummary);
        return claimId;
    }

    private void stubRecordingStopped(final UUID claimId) {
        when(sessionService.verifyTerminationOwnership(eq("call-1"), eq(claimId)))
                .thenReturn(noneDone());
        when(sessionService.advanceTerminationStep(eq("call-1"), eq(claimId), any())).thenReturn(true);
        when(recordingService.stopRecordingTyped("call-1"))
                .thenReturn(new RecordingStopResult(
                        Status.STOPPED, "call-1", "pipe", "STOPPED", null, null, null));
        when(sessionService.completeTermination("call-1", claimId)).thenReturn(true);
    }

    /**
     * Scenario: recording stops cleanly. Screening must be queued exactly once, after the
     * recording is finalized and before the Chime meeting is torn down.
     */
    @Test
    void execute_enqueuesConditionDetectionOnceAfterRecordingAndBeforeMeetingEnd() {
        // Arrange
        final UUID claimId = arrangeAfterSummary();
        stubRecordingStopped(claimId);

        // Act
        final boolean done = executor.execute("call-1", 9L, claimId);

        // Assert
        assertThat(done).isTrue();
        verify(conditionDetectionService, times(1)).enqueueForCall("call-1");
        final InOrder order = inOrder(recordingService, sessionService, conditionDetectionService, chimeService);
        order.verify(recordingService).stopRecordingTyped("call-1");
        order.verify(sessionService).advanceTerminationStep("call-1", claimId, TerminationStep.RECORDING);
        order.verify(conditionDetectionService).enqueueForCall("call-1");
        order.verify(chimeService).endMeeting("call-1");
        order.verify(sessionService).completeTermination("call-1", claimId);
    }

    /**
     * Scenario: the enqueue throws (for example a DB outage). Screening is best-effort, so the
     * meeting is still ended and termination still completes without recording a failure.
     */
    @Test
    void execute_enqueueFailureDoesNotStopTermination() {
        // Arrange
        final UUID claimId = arrangeAfterSummary();
        stubRecordingStopped(claimId);
        org.mockito.Mockito.doThrow(new IllegalStateException("db down"))
                .when(conditionDetectionService).enqueueForCall("call-1");

        // Act
        final boolean done = executor.execute("call-1", 9L, claimId);

        // Assert
        assertThat(done).isTrue();
        verify(chimeService).endMeeting("call-1");
        verify(sessionService).advanceTerminationStep("call-1", claimId, TerminationStep.MEETING);
        verify(sessionService).completeTermination("call-1", claimId);
        verify(sessionService, never()).recordTerminationFailure(any(), any(), any());
    }

    /**
     * Scenario: the swallowed enqueue failure is still visible to operators as a WARN that names
     * the call and the exception type, but not the exception message, which can carry details.
     *
     * <p>The logger level is set here rather than inherited: logback-test.xml turns logging off,
     * and only a Spring context test turns WARN back on, so relying on it made this branch's
     * coverage depend on test-class order (it passed locally and failed in CI).</p>
     */
    @Test
    void execute_enqueueFailure_logsWarningWithoutExceptionMessage() {
        // Arrange
        final UUID claimId = arrangeAfterSummary();
        stubRecordingStopped(claimId);
        org.mockito.Mockito.doThrow(new IllegalStateException("db down at 10.0.0.5"))
                .when(conditionDetectionService).enqueueForCall("call-1");
        final Logger logger = (Logger) LoggerFactory.getLogger(CallTerminationExecutor.class);
        final Level previousLevel = logger.getLevel();
        final ListAppender<ILoggingEvent> appender = new ListAppender<>();
        appender.start();
        logger.addAppender(appender);
        logger.setLevel(Level.WARN);

        try {
            // Act
            executor.execute("call-1", 9L, claimId);

            // Assert
            assertThat(appender.list)
                    .filteredOn(event -> event.getLevel() == Level.WARN)
                    .singleElement()
                    .satisfies(event -> {
                        assertThat(event.getFormattedMessage())
                                .contains("call-1")
                                .contains("IllegalStateException")
                                .doesNotContain("10.0.0.5");
                    });
        } finally {
            logger.detachAppender(appender);
            logger.setLevel(previousLevel);
        }
    }

    /**
     * Scenario: the recording stop is retryable (DEFERRED). The recording is not finalized, so
     * screening must not be queued yet.
     */
    @Test
    void execute_deferredRecordingDoesNotEnqueueConditionDetection() {
        // Arrange
        final UUID claimId = arrangeAfterSummary();
        when(sessionService.verifyTerminationOwnership(eq("call-1"), eq(claimId)))
                .thenReturn(noneDone());
        when(recordingService.stopRecordingTyped("call-1"))
                .thenReturn(new RecordingStopResult(
                        Status.RETRYABLE_FAILURE, "call-1", "pipe", "STOP_RETRYABLE",
                        null, null, "AWS unavailable"));

        // Act
        final boolean done = executor.execute("call-1", 9L, claimId);

        // Assert
        assertThat(done).isFalse();
        verify(conditionDetectionService, never()).enqueueForCall(any());
    }

    /**
     * Scenario: ownership is lost right after the recording stop (verify returns null, STALE).
     * Another owner will finish the job, so this one must not enqueue.
     */
    @Test
    void execute_staleRecordingDoesNotEnqueueConditionDetection() {
        // Arrange
        final UUID claimId = arrangeAfterSummary();
        when(sessionService.verifyTerminationOwnership(eq("call-1"), eq(claimId))).thenReturn(null);
        when(recordingService.stopRecordingTyped("call-1"))
                .thenReturn(new RecordingStopResult(
                        Status.STOPPED, "call-1", "pipe", "STOPPED", null, null, null));

        // Act
        final boolean done = executor.execute("call-1", 9L, claimId);

        // Assert
        assertThat(done).isFalse();
        verify(conditionDetectionService, never()).enqueueForCall(any());
        verify(chimeService, never()).endMeeting(any());
    }

    /**
     * Scenario: a reclaimed termination whose RECORDING step was already recorded. The enqueue
     * is idempotent, so it is attempted again rather than skipped (the first attempt may have
     * been lost); the recording itself is not stopped twice.
     */
    @Test
    void execute_resumeWithRecordingAlreadyDone_stillAttemptsIdempotentEnqueue() {
        // Arrange
        final UUID claimId = UUID.randomUUID();
        final TerminationProgress recordingDone = new TerminationProgress(true, true, true, false);
        when(sessionService.renewTerminationOwnership("call-1", claimId)).thenReturn(recordingDone);
        when(sessionService.verifyTerminationOwnership(eq("call-1"), eq(claimId))).thenReturn(recordingDone);
        when(sessionService.advanceTerminationStep(eq("call-1"), eq(claimId), any())).thenReturn(true);
        when(sessionService.completeTermination("call-1", claimId)).thenReturn(true);

        // Act
        final boolean done = executor.execute("call-1", 9L, claimId);

        // Assert
        assertThat(done).isTrue();
        verify(recordingService, never()).stopRecordingTyped(any());
        verify(conditionDetectionService).enqueueForCall("call-1");
    }
}
