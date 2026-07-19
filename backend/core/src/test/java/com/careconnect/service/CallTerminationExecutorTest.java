package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.model.CallTelemetryEvent;
import com.careconnect.service.BedrockSentimentService.SentimentResult;
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
    when(telemetryService.getTelemetryForCall("call-1")).thenReturn(List.of(voice));
    when(telemetryService.getLatestSentimentByChannel("call-1"))
        .thenReturn(Map.of("VOICE", voice));
    when(sentimentService.analyzeFinalOverallSentiment(eq("call-1"), any()))
        .thenReturn(finalResult);
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
    order.verify(recordingService).stopRecording("call-1");
    order.verify(chimeService).endMeeting("call-1");
    order.verify(sessionService).completeTermination("call-1", claimId);
  }

  @Test
  void execute_retriesNoTranscriptOrMissingSummaryWithoutDuplicatingFinalSentiment() {
    final UUID claimId = UUID.randomUUID();
    final CallTelemetryEvent finalEvent = new CallTelemetryEvent();
    finalEvent.setEventType("SENTIMENT_FINAL");
    finalEvent.setStatus("SUCCESS");
    when(telemetryService.getTelemetryForCall("call-1")).thenReturn(List.of(finalEvent));
    when(telemetryService.getLatestSentimentByChannel("call-1")).thenReturn(Map.of());
    when(sessionService.completeTermination("call-1", claimId)).thenReturn(true);

    assertThat(executor.execute("call-1", 2L, claimId)).isTrue();

    verify(summaryService).generateAndStoreSummary("call-1", 2L, Map.of());
    verify(sessionService).completeTermination("call-1", claimId);
  }
}
