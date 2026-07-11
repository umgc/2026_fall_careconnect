package com.careconnect.service.ai.indexing;

import com.careconnect.indexing.IndexingEventType;
import com.careconnect.indexing.SummaryCreatedPayload;
import com.careconnect.indexing.TranscriptIndexedPayload;
import com.careconnect.model.indexing.IndexingOutboxRow;
import com.careconnect.repository.indexing.IndexingOutboxRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class IndexWorkerTest {

    @Mock
    private IndexingOutboxRepository outboxRepository;
    @Mock
    private RetrievalIndexService retrievalIndexService;

    private ObjectMapper objectMapper;
    private IndexWorker worker;

    @BeforeEach
    void setUp() {
        objectMapper = new ObjectMapper().registerModule(new JavaTimeModule());
        worker = new IndexWorker(
                outboxRepository,
                retrievalIndexService,
                objectMapper,
                10,
                3);
    }

    @Test
    @DisplayName("poll claims rows and dispatches SUMMARY_CREATED")
    void poll_summaryCreated_success() throws Exception {
        final SummaryCreatedPayload payload = new SummaryCreatedPayload(
                "call", "call_summaries", 1L, "c1", 9L, "SUCCESS",
                LocalDateTime.now(), 2, "on_consent", "engine", "sha256:x");
        final IndexingOutboxRow row = IndexingOutboxRow.builder()
                .id(100L)
                .eventType(IndexingEventType.SUMMARY_CREATED)
                .payloadJson(envelope(IndexingEventType.SUMMARY_CREATED, payload))
                .attemptCount(0)
                .build();
        when(outboxRepository.claimUnprocessedForPolling(eq(10)))
                .thenReturn(List.of(row));
        when(retrievalIndexService.ingestSummaryCreated(any())).thenReturn(3);

        worker.pollAndProcess();

        verify(outboxRepository).claimUnprocessedForPolling(10);
        verify(retrievalIndexService).ingestSummaryCreated(any(SummaryCreatedPayload.class));
        final ArgumentCaptor<IndexingOutboxRow> captor =
                ArgumentCaptor.forClass(IndexingOutboxRow.class);
        verify(outboxRepository).save(captor.capture());
        assertThat(captor.getValue().getProcessedAt()).isNotNull();
        assertThat(captor.getValue().getAttemptCount()).isEqualTo(1);
        assertThat(captor.getValue().getLastError()).isNull();
    }

    @Test
    @DisplayName("poll dispatches TRANSCRIPT_INDEXED")
    void poll_transcriptIndexed_success() throws Exception {
        final TranscriptIndexedPayload payload =
                new TranscriptIndexedPayload("call-1", 5L, 4, "CLIENT_TRANSCRIPT");
        final IndexingOutboxRow row = IndexingOutboxRow.builder()
                .id(101L)
                .eventType(IndexingEventType.TRANSCRIPT_INDEXED)
                .payloadJson(envelope(IndexingEventType.TRANSCRIPT_INDEXED, payload))
                .attemptCount(0)
                .build();
        when(outboxRepository.claimUnprocessedForPolling(anyInt()))
                .thenReturn(List.of(row));
        when(retrievalIndexService.ingestTranscriptIndexed(any())).thenReturn(4);

        worker.pollAndProcess();

        verify(retrievalIndexService).ingestTranscriptIndexed(any(TranscriptIndexedPayload.class));
        verify(outboxRepository).save(any(IndexingOutboxRow.class));
    }

    @Test
    @DisplayName("hard failure increments attemptCount and keeps row unprocessed")
    void poll_failure_incrementsAttempts() throws Exception {
        final TranscriptIndexedPayload payload =
                new TranscriptIndexedPayload("call-1", 1L, 1, "CLIENT_TRANSCRIPT");
        final IndexingOutboxRow row = IndexingOutboxRow.builder()
                .id(102L)
                .eventType(IndexingEventType.TRANSCRIPT_INDEXED)
                .payloadJson(envelope(IndexingEventType.TRANSCRIPT_INDEXED, payload))
                .attemptCount(1)
                .build();
        when(outboxRepository.claimUnprocessedForPolling(anyInt()))
                .thenReturn(List.of(row));
        when(retrievalIndexService.ingestTranscriptIndexed(any()))
                .thenThrow(new IllegalArgumentException("CallSummary not found"));

        worker.pollAndProcess();

        final ArgumentCaptor<IndexingOutboxRow> captor =
                ArgumentCaptor.forClass(IndexingOutboxRow.class);
        verify(outboxRepository).save(captor.capture());
        assertThat(captor.getValue().getProcessedAt()).isNull();
        assertThat(captor.getValue().getAttemptCount()).isEqualTo(2);
        assertThat(captor.getValue().getLastError()).contains("CallSummary not found");
    }

    @Test
    @DisplayName("missing patientId defers without burning attempts")
    void poll_deferredPatientId_doesNotIncrementAttempts() throws Exception {
        final TranscriptIndexedPayload payload =
                new TranscriptIndexedPayload("call-1", null, 1, "CLIENT_TRANSCRIPT");
        final IndexingOutboxRow row = IndexingOutboxRow.builder()
                .id(104L)
                .eventType(IndexingEventType.TRANSCRIPT_INDEXED)
                .payloadJson(envelope(IndexingEventType.TRANSCRIPT_INDEXED, payload))
                .attemptCount(1)
                .build();
        when(outboxRepository.claimUnprocessedForPolling(anyInt()))
                .thenReturn(List.of(row));
        when(retrievalIndexService.ingestTranscriptIndexed(any()))
                .thenThrow(new IndexingDeferredException("patientId is required"));

        worker.pollAndProcess();

        verify(outboxRepository, never()).save(any());
        assertThat(row.getAttemptCount()).isEqualTo(1);
        assertThat(row.getProcessedAt()).isNull();
    }

    @Test
    @DisplayName("rows at max attempts are dead-lettered")
    void poll_maxAttempts_deadLetters() {
        final IndexingOutboxRow row = IndexingOutboxRow.builder()
                .id(103L)
                .eventType(IndexingEventType.TRANSCRIPT_INDEXED)
                .payloadJson("{\"eventType\":\"TRANSCRIPT_INDEXED\",\"payload\":{}}")
                .attemptCount(3)
                .lastError("previous")
                .build();
        when(outboxRepository.claimUnprocessedForPolling(anyInt()))
                .thenReturn(List.of(row));

        worker.pollAndProcess();

        verify(retrievalIndexService, never()).ingestTranscriptIndexed(any());
        final ArgumentCaptor<IndexingOutboxRow> captor =
                ArgumentCaptor.forClass(IndexingOutboxRow.class);
        verify(outboxRepository).save(captor.capture());
        assertThat(captor.getValue().getProcessedAt()).isNotNull();
        assertThat(captor.getValue().getLastError()).contains("Exceeded max attempts");
    }

    @Test
    @DisplayName("hard failure at max attempts dead-letters immediately")
    void poll_failureAtMaxAttempts_deadLetters() throws Exception {
        final TranscriptIndexedPayload payload =
                new TranscriptIndexedPayload("call-1", 1L, 1, "CLIENT_TRANSCRIPT");
        final IndexingOutboxRow row = IndexingOutboxRow.builder()
                .id(105L)
                .eventType(IndexingEventType.TRANSCRIPT_INDEXED)
                .payloadJson(envelope(IndexingEventType.TRANSCRIPT_INDEXED, payload))
                .attemptCount(2)
                .build();
        when(outboxRepository.claimUnprocessedForPolling(anyInt()))
                .thenReturn(List.of(row));
        when(retrievalIndexService.ingestTranscriptIndexed(any()))
                .thenThrow(new IllegalStateException("boom"));

        worker.pollAndProcess();

        final ArgumentCaptor<IndexingOutboxRow> captor =
                ArgumentCaptor.forClass(IndexingOutboxRow.class);
        verify(outboxRepository).save(captor.capture());
        assertThat(captor.getValue().getAttemptCount()).isEqualTo(3);
        assertThat(captor.getValue().getProcessedAt()).isNotNull();
        assertThat(captor.getValue().getLastError()).contains("boom");
    }

    private String envelope(final String eventType, final Object payload) throws Exception {
        return objectMapper.writeValueAsString(java.util.Map.of(
                "eventType", eventType,
                "eventId", "evt-1",
                "occurredAt", "2026-07-10T12:00:00Z",
                "schemaVersion", 1,
                "payload", payload));
    }
}
