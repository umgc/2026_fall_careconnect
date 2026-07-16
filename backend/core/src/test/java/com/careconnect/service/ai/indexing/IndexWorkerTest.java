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
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionException;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.SimpleTransactionStatus;

import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyList;
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
                new ImmediateTransactionManager(),
                10,
                3,
                2,
                6);
        when(outboxRepository.saveAll(anyList())).thenAnswer(inv -> inv.getArgument(0));
    }

    @Test
    @DisplayName("poll claims rows with lease and dispatches SUMMARY_CREATED")
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
        when(outboxRepository.claimUnprocessedForPolling(eq(10), eq(2)))
                .thenReturn(List.of(row));
        when(retrievalIndexService.ingestSummaryCreated(any())).thenReturn(3);

        worker.pollAndProcess();

        verify(outboxRepository).claimUnprocessedForPolling(10, 2);
        verify(outboxRepository).saveAll(anyList());
        verify(retrievalIndexService).ingestSummaryCreated(any(SummaryCreatedPayload.class));
        final ArgumentCaptor<IndexingOutboxRow> captor =
                ArgumentCaptor.forClass(IndexingOutboxRow.class);
        verify(outboxRepository).save(captor.capture());
        assertThat(captor.getValue().getProcessedAt()).isNotNull();
        assertThat(captor.getValue().getClaimedAt()).isNull();
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
        when(outboxRepository.claimUnprocessedForPolling(anyInt(), anyInt()))
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
                .claimedAt(LocalDateTime.now())
                .build();
        when(outboxRepository.claimUnprocessedForPolling(anyInt(), anyInt()))
                .thenReturn(List.of(row));
        when(retrievalIndexService.ingestTranscriptIndexed(any()))
                .thenThrow(new IllegalArgumentException("CallSummary not found"));

        worker.pollAndProcess();

        final ArgumentCaptor<IndexingOutboxRow> captor =
                ArgumentCaptor.forClass(IndexingOutboxRow.class);
        verify(outboxRepository).save(captor.capture());
        assertThat(captor.getValue().getProcessedAt()).isNull();
        assertThat(captor.getValue().getClaimedAt()).isNotNull();
        assertThat(captor.getValue().getAttemptCount()).isEqualTo(2);
        assertThat(captor.getValue().getLastError()).contains("CallSummary not found");
    }

    @Test
    @DisplayName("missing patientId defers, burns attempt, leaves unprocessed")
    void poll_deferredPatientId_incrementsAttemptsAndLeavesUnprocessed() throws Exception {
        final TranscriptIndexedPayload payload =
                new TranscriptIndexedPayload("call-1", null, 1, "CLIENT_TRANSCRIPT");
        final IndexingOutboxRow row = IndexingOutboxRow.builder()
                .id(104L)
                .eventType(IndexingEventType.TRANSCRIPT_INDEXED)
                .payloadJson(envelope(IndexingEventType.TRANSCRIPT_INDEXED, payload))
                .attemptCount(1)
                .build();
        when(outboxRepository.claimUnprocessedForPolling(anyInt(), anyInt()))
                .thenReturn(List.of(row));
        when(retrievalIndexService.ingestTranscriptIndexed(any()))
                .thenThrow(new IndexingDeferredException("patientId is required"));

        worker.pollAndProcess();

        final ArgumentCaptor<IndexingOutboxRow> captor =
                ArgumentCaptor.forClass(IndexingOutboxRow.class);
        verify(outboxRepository).save(captor.capture());
        assertThat(captor.getValue().getAttemptCount()).isEqualTo(2);
        assertThat(captor.getValue().getProcessedAt()).isNull();
        assertThat(captor.getValue().getClaimedAt()).isNotNull();
        assertThat(captor.getValue().getLastError()).contains("patientId is required");
    }

    @Test
    @DisplayName("visit deferral parks row without burning attempts")
    void poll_visitDeferred_doesNotBurnAttempts() throws Exception {
        final SummaryCreatedPayload payload = new SummaryCreatedPayload(
                "visit", "visit_summaries", 50L, null, 42L, "SUCCESS",
                LocalDateTime.now(), 0, "on_consent", null, "sha256:v");
        final IndexingOutboxRow row = IndexingOutboxRow.builder()
                .id(107L)
                .eventType(IndexingEventType.SUMMARY_CREATED)
                .payloadJson(envelope(IndexingEventType.SUMMARY_CREATED, payload))
                .attemptCount(1)
                .claimedAt(LocalDateTime.now())
                .build();
        when(outboxRepository.claimUnprocessedForPolling(anyInt(), anyInt()))
                .thenReturn(List.of(row));
        when(retrievalIndexService.ingestSummaryCreated(any()))
                .thenThrow(new IndexingDeferredException("Visit summary indexing not implemented yet (Task 1.4)", false));

        worker.pollAndProcess();

        final ArgumentCaptor<IndexingOutboxRow> captor =
                ArgumentCaptor.forClass(IndexingOutboxRow.class);
        verify(outboxRepository).save(captor.capture());
        assertThat(captor.getValue().getAttemptCount()).isEqualTo(1);
        assertThat(captor.getValue().getProcessedAt()).isNull();
        // Future claimed_at parks until Task 1.4 so polls do not reclaim every 15s.
        assertThat(captor.getValue().getClaimedAt()).isAfter(LocalDateTime.now().plusHours(5));
        assertThat(captor.getValue().getLastError()).contains("Task 1.4");
    }

    @Test
    @DisplayName("burn-attempt deferral refreshes soft lease (claimed_at=now, not cleared)")
    void poll_deferredMidAttempts_refreshesLease() throws Exception {
        final TranscriptIndexedPayload payload =
                new TranscriptIndexedPayload("call-1", null, 1, "CLIENT_TRANSCRIPT");
        final IndexingOutboxRow row = IndexingOutboxRow.builder()
                .id(108L)
                .eventType(IndexingEventType.TRANSCRIPT_INDEXED)
                .payloadJson(envelope(IndexingEventType.TRANSCRIPT_INDEXED, payload))
                .attemptCount(0)
                .claimedAt(LocalDateTime.now().minusMinutes(1))
                .build();
        when(outboxRepository.claimUnprocessedForPolling(anyInt(), anyInt()))
                .thenReturn(List.of(row));
        when(retrievalIndexService.ingestTranscriptIndexed(any()))
                .thenThrow(new IndexingDeferredException("patientId is required"));

        final LocalDateTime before = LocalDateTime.now().minusSeconds(1);
        worker.pollAndProcess();

        final ArgumentCaptor<IndexingOutboxRow> captor =
                ArgumentCaptor.forClass(IndexingOutboxRow.class);
        verify(outboxRepository).save(captor.capture());
        assertThat(captor.getValue().getAttemptCount()).isEqualTo(1);
        assertThat(captor.getValue().getProcessedAt()).isNull();
        // Soft lease: claimed_at=now() is age 0, so claim SQL
        // (claimed_at < NOW() - make_interval(mins => lease)) will not reclaim until
        // claim-lease-minutes elapse — not on the next 15s poll.
        assertThat(captor.getValue().getClaimedAt()).isAfter(before);
        assertThat(captor.getValue().getClaimedAt())
                .isBefore(LocalDateTime.now().plusSeconds(5));
        assertThat(captor.getValue().getLastError()).contains("patientId is required");
    }

    @Test
    @DisplayName("deferred rows eventually dead-letter at max attempts")
    void poll_deferredAtMaxAttempts_deadLetters() throws Exception {
        final TranscriptIndexedPayload payload =
                new TranscriptIndexedPayload("call-1", null, 1, "CLIENT_TRANSCRIPT");
        final IndexingOutboxRow row = IndexingOutboxRow.builder()
                .id(106L)
                .eventType(IndexingEventType.TRANSCRIPT_INDEXED)
                .payloadJson(envelope(IndexingEventType.TRANSCRIPT_INDEXED, payload))
                .attemptCount(2)
                .build();
        when(outboxRepository.claimUnprocessedForPolling(anyInt(), anyInt()))
                .thenReturn(List.of(row));
        when(retrievalIndexService.ingestTranscriptIndexed(any()))
                .thenThrow(new IndexingDeferredException("patientId is required"));

        worker.pollAndProcess();

        final ArgumentCaptor<IndexingOutboxRow> captor =
                ArgumentCaptor.forClass(IndexingOutboxRow.class);
        verify(outboxRepository).save(captor.capture());
        assertThat(captor.getValue().getAttemptCount()).isEqualTo(3);
        assertThat(captor.getValue().getProcessedAt()).isNotNull();
        assertThat(captor.getValue().getClaimedAt()).isNull();
        assertThat(captor.getValue().getLastError()).contains("patientId is required");
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
        when(outboxRepository.claimUnprocessedForPolling(anyInt(), anyInt()))
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
        when(outboxRepository.claimUnprocessedForPolling(anyInt(), anyInt()))
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

    private static final class ImmediateTransactionManager implements PlatformTransactionManager {
        @Override
        public TransactionStatus getTransaction(final TransactionDefinition definition)
                throws TransactionException {
            return new SimpleTransactionStatus();
        }

        @Override
        public void commit(final TransactionStatus status) throws TransactionException {
            // no-op
        }

        @Override
        public void rollback(final TransactionStatus status) throws TransactionException {
            // no-op
        }
    }
}
