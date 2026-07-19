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

import com.careconnect.model.CallTelemetryEvent;
import com.careconnect.model.TerminationStep;
import com.careconnect.service.BedrockSentimentService.SentimentResult;
import com.careconnect.service.CallSessionService.TerminationProgress;
import com.careconnect.service.RecordingStopResult.Status;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InOrder;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class CallTerminationExecutorTest {

  @Mock private BedrockSentimentService sentimentService;
  @Mock private CallTelemetryService telemetryService;
  @Mock private CallSummaryService summaryService;
  @Mock private CallRecordingService recordingService;
  @Mock private ChimeService chimeService;
  @Mock private CallSessionService sessionService;

  private CallTerminationExecutor executor;

  @BeforeEach
  void setUp() {
    executor = new CallTerminationExecutor(
        sentimentService,
        telemetryService,
        summaryService,
        recordingService,
        chimeService,
        sessionService);
  }

  @Test
  void execute_recoversArtifactsBeforeFencedEnd() {
    final UUID claimId = UUID.randomUUID();
    final CallTelemetryEvent voice = new CallTelemetryEvent();
    voice.setEventType("SENTIMENT_VOICE");
    voice.setChannel("VOICE");
    voice.setSentimentScore(0.6);
    voice.setSentimentLabel("CALM");
    final SentimentResult finalResult =
        SentimentResult.neutral("COMBINED", "call-1", "Recovered");
    when(sessionService.renewTerminationOwnership("call-1", claimId))
        .thenReturn(noneDone());
    when(sessionService.verifyTerminationOwnership("call-1", claimId))
        .thenReturn(noneDone());
    when(sessionService.advanceTerminationStep(eq("call-1"), eq(claimId), any()))
        .thenReturn(true);
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
        eq(null),
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
  void execute_retryableRecordingLeavesTerminatingAfterMeetingShutdown() {
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

    verify(chimeService).endMeeting("call-1");
    verify(sessionService).advanceTerminationStep(
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

  private static TerminationProgress noneDone() {
    return new TerminationProgress(false, false, false, false);
  }
}
