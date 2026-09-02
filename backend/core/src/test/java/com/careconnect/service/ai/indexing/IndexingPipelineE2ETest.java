package com.careconnect.service.ai.indexing;

import com.careconnect.indexing.IndexingEventType;
import com.careconnect.indexing.SummaryCreatedPayload;
import com.careconnect.indexing.TranscriptIndexedPayload;
import com.careconnect.model.CallSummary;
import com.careconnect.model.CallSession;
import com.careconnect.model.CallTranscriptSegment;
import com.careconnect.service.CallTranscriptService;
import com.careconnect.model.indexing.IndexingOutboxRow;
import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.repository.CallSummaryRepository;
import com.careconnect.repository.CallSessionRepository;
import com.careconnect.repository.CallTranscriptSegmentRepository;
import com.careconnect.repository.PatientNoteRepository;
import com.careconnect.repository.UserFileRepository;
import com.careconnect.repository.UspsMailpieceRepository;
import com.careconnect.repository.VisitSummaryRepository;
import com.careconnect.repository.indexing.IndexingOutboxRepository;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import com.careconnect.service.ai.indexing.chunker.ClinicalNoteChunker;
import com.careconnect.service.ai.indexing.chunker.DocumentChunker;
import com.careconnect.service.ai.indexing.chunker.MailpieceChunker;
import com.careconnect.service.ai.embedding.ChunkEmbeddingService;
import com.careconnect.service.ai.indexing.chunker.SummaryChunker;
import com.careconnect.service.ai.indexing.chunker.TranscriptSegmentChunker;
import com.careconnect.util.ContentHashUtil;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
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
import java.util.Optional;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * End-to-end coverage for the Task 4.1 PR test plan: outbox envelope → IndexWorker →
 * RetrievalIndexService → chunkers → retrieval_index_chunk writes (repositories mocked).
 */
@ExtendWith(MockitoExtension.class)
class IndexingPipelineE2ETest {

    private final AtomicReference<List<RetrievalIndexChunk>> indexedChunks =
            new AtomicReference<>(List.of());
    @Mock
    private IndexingOutboxRepository outboxRepository;
    @Mock
    private CallSummaryRepository callSummaryRepository;
    @Mock
    private VisitSummaryRepository visitSummaryRepository;
    @Mock
    private CallSessionRepository callSessionRepository;
    @Mock
    private CallTranscriptSegmentRepository transcriptSegmentRepository;
    @Mock
    private CallTranscriptService callTranscriptService;
    @Mock
    private UspsMailpieceRepository uspsMailpieceRepository;
    @Mock
    private PatientNoteRepository patientNoteRepository;
    @Mock
    private UserFileRepository userFileRepository;
    @Mock
    private RetrievalIndexChunkRepository chunkRepository;
    @Mock
    private ChunkEmbeddingService chunkEmbeddingService;
    private ObjectMapper objectMapper;
    private IndexWorker worker;

    @BeforeEach
    void setUp() {
        objectMapper = new ObjectMapper().registerModule(new JavaTimeModule());
        final RetrievalIndexService retrievalIndexService = new RetrievalIndexService(
                callSummaryRepository,
                visitSummaryRepository,
                callSessionRepository,
                callTranscriptService,
                uspsMailpieceRepository,
                patientNoteRepository,
                userFileRepository,
                chunkRepository,
                new SummaryChunker(objectMapper),
                new TranscriptSegmentChunker(),
                new MailpieceChunker(),
                new ClinicalNoteChunker(),
                new DocumentChunker(),
                objectMapper,
                chunkEmbeddingService);
        worker = new IndexWorker(
                outboxRepository,
                retrievalIndexService,
                objectMapper,
                new ImmediateTransactionManager(),
                10,
                5,
                2,
                6);

        lenient().when(outboxRepository.saveAll(anyList())).thenAnswer(inv -> inv.getArgument(0));
        lenient().when(chunkRepository.saveAll(anyList())).thenAnswer(inv -> {
            @SuppressWarnings("unchecked") final List<RetrievalIndexChunk> saved = inv.getArgument(0);
            indexedChunks.set(List.copyOf(saved));
            return saved;
        });
    }

    @Test
    @DisplayName("E2E: SUCCESS SUMMARY_CREATED is processed into CALL_SUMMARY (+ item) chunks")
    void summaryCreated_success_writesChunksAndMarksOutboxProcessed() throws Exception {
        final CallSummary summary = new CallSummary();
        summary.setId(99L);
        summary.setCallId("call-e2e");
        summary.setPatientId(42L);
        summary.setStatus("SUCCESS");
        summary.setCaregiverVisibility("on_consent");
        summary.setSummarizationEngine("aws_bedrock:test");
        summary.setSummaryJson("""
                {
                  "headline": "Medication review",
                  "overallAssessment": "Patient started metformin.",
                  "actionItems": [{ "text": "Pick up prescription" }],
                  "careInstructions": [{ "type": "medication", "text": "Take with food" }]
                }
                """);
        when(callSummaryRepository.findByIdForUpdate(99L)).thenReturn(Optional.of(summary));
        when(chunkRepository.findCallSummaryChunksForReplacement(
                eq(42L),
                eq("call-summary:99"),
                eq("99"),
                eq(SummarySourceKey.CALL_KIND),
                any()))
                .thenReturn(List.of());

        final SummaryCreatedPayload payload = new SummaryCreatedPayload(
                "call",
                "call_summaries",
                99L,
                "call-e2e",
                42L,
                "SUCCESS",
                LocalDateTime.now(),
                4,
                "on_consent",
                "aws_bedrock:test",
                ContentHashUtil.sha256(summary.getSummaryJson()));
        final IndexingOutboxRow row = outboxRow(
                1001L, IndexingEventType.SUMMARY_CREATED, payload, 0);
        when(outboxRepository.claimUnprocessedForPolling(anyInt(), anyInt())).thenReturn(List.of(row));

        worker.pollAndProcess();

        assertThat(indexedChunks.get())
                .extracting(RetrievalIndexChunk::getRecordType)
                .contains(
                        RetrievalRecordType.CALL_SUMMARY.name(),
                        RetrievalRecordType.SUMMARY_ACTION_ITEM.name(),
                        RetrievalRecordType.SUMMARY_CARE_INSTRUCTION.name());
        assertThat(indexedChunks.get())
                .allMatch(c -> Long.valueOf(42L).equals(c.getPatientId()));
        assertThat(indexedChunks.get())
                .allMatch(c -> "call-summary:99".equals(c.getSourceRecordId()))
                .allMatch(c -> SummarySourceKey.CALL_KIND.equals(c.getSourceKind()));

        final ArgumentCaptor<IndexingOutboxRow> outboxCaptor =
                ArgumentCaptor.forClass(IndexingOutboxRow.class);
        verify(outboxRepository).save(outboxCaptor.capture());
        assertThat(outboxCaptor.getValue().getProcessedAt()).isNotNull();
        assertThat(outboxCaptor.getValue().getLastError()).isNull();
        assertThat(outboxCaptor.getValue().getAttemptCount()).isEqualTo(1);
        verify(chunkRepository).deleteCallSummaryChunksForReplacement(
                eq(42L),
                eq("call-summary:99"),
                eq("99"),
                eq(SummarySourceKey.CALL_KIND),
                any());
    }

    @Test
    @DisplayName("E2E: TRANSCRIPT_INDEXED with patientId writes TRANSCRIPT_SEGMENT chunks")
    void transcriptIndexed_withPatientId_writesSegmentChunks() throws Exception {
        final CallSession session = new CallSession();
        session.setCallId("call-tx");
        session.setPatientId(55L);
        when(callSessionRepository.findByCallIdForIndexing("call-tx"))
                .thenReturn(Optional.of(session));
        final CallTranscriptSegment segment = new CallTranscriptSegment();
        segment.setId(7L);
        segment.setCallId("call-tx");
        segment.setSpeakerLabel("Patient");
        segment.setText("I started the new medication yesterday.");
        segment.setSource("CLIENT_TRANSCRIPT");
        when(callTranscriptService.captureIndexingSnapshot("call-tx"))
                .thenReturn(new CallTranscriptService.IndexingSnapshot(
                        List.of(segment), "sha256:call-tx"));

        final TranscriptIndexedPayload payload =
                new TranscriptIndexedPayload("call-tx", 55L, 1, "sha256:call-tx");
        final IndexingOutboxRow row = outboxRow(
                1002L, IndexingEventType.TRANSCRIPT_INDEXED, payload, 0);
        when(outboxRepository.claimUnprocessedForPolling(anyInt(), anyInt())).thenReturn(List.of(row));

        worker.pollAndProcess();

        assertThat(indexedChunks.get()).hasSize(1);
        assertThat(indexedChunks.get().get(0).getRecordType())
                .isEqualTo(RetrievalRecordType.TRANSCRIPT_SEGMENT.name());
        assertThat(indexedChunks.get().get(0).getPatientId()).isEqualTo(55L);
        assertThat(indexedChunks.get().get(0).getSourceRecordId()).isEqualTo("call-tx");
        assertThat(indexedChunks.get().get(0).getChunkText())
                .contains("I started the new medication yesterday.");

        verify(chunkRepository).deleteByPatientIdAndSourceRecordIdAndRecordType(
                55L, "call-tx", RetrievalRecordType.TRANSCRIPT_SEGMENT.name());
        verify(outboxRepository).save(any(IndexingOutboxRow.class));
    }

    @Test
    @DisplayName("E2E: re-processing same summary contentHash skips rewrite")
    void summaryCreated_sameContentHash_skipsDeleteAndRewrite() throws Exception {
        final CallSummary summary = new CallSummary();
        summary.setId(99L);
        summary.setCallId("call-e2e");
        summary.setPatientId(42L);
        summary.setStatus("SUCCESS");
        summary.setCaregiverVisibility("on_consent");
        summary.setSummarizationEngine("engine");
        summary.setSummaryJson("{\"headline\":\"already indexed\"}");
        when(callSummaryRepository.findByIdForUpdate(99L)).thenReturn(Optional.of(summary));

        // Build "already indexed" rows from the real chunker so citation metadata stays in sync
        // with RetrievalIndexService.chunksMatchExpected (avoids brittle hand-written JSON).
        final String contentHash = ContentHashUtil.sha256(summary.getSummaryJson());
        final List<IndexingChunkDraft> drafts = new SummaryChunker(objectMapper).chunk(
                "call",
                summary.getSummaryJson(),
                contentHash,
                summary.getCaregiverVisibility(),
                summary.getSummarizationEngine(),
                summary.getCallId(),
                null);
        assertThat(drafts).isNotEmpty();
        final List<RetrievalIndexChunk> existing = new java.util.ArrayList<>(drafts.size());
        for (final IndexingChunkDraft draft : drafts) {
            existing.add(RetrievalIndexChunk.builder()
                    .patientId(42L)
                    .recordType(draft.recordType().name())
                    .sourceRecordId("call-summary:99")
                    .sourceKind(SummarySourceKey.CALL_KIND)
                    .chunkText(draft.chunkText())
                    .consentScope(draft.consentScope())
                    .chunkMetadata(objectMapper.writeValueAsString(draft.metadata()))
                    .build());
        }
        when(chunkRepository.findCallSummaryChunksForReplacement(
                eq(42L),
                eq("call-summary:99"),
                eq("99"),
                eq(SummarySourceKey.CALL_KIND),
                any()))
                .thenReturn(existing);
        when(chunkRepository.countMissingEmbeddingForSummarySources(
                eq(42L), eq(List.of("call-summary:99")), any()))
                .thenReturn(0L);

        final SummaryCreatedPayload payload = new SummaryCreatedPayload(
                "call",
                "call_summaries",
                99L,
                "call-e2e",
                42L,
                "SUCCESS",
                LocalDateTime.now(),
                1,
                "on_consent",
                "engine",
                contentHash);
        final IndexingOutboxRow row = outboxRow(
                1003L, IndexingEventType.SUMMARY_CREATED, payload, 0);
        when(outboxRepository.claimUnprocessedForPolling(anyInt(), anyInt())).thenReturn(List.of(row));

        worker.pollAndProcess();

        verify(callSummaryRepository).findByIdForUpdate(99L);
        verify(chunkRepository, never()).deleteCallSummaryChunksForReplacement(
                any(), anyString(), anyString(), anyString(), any());
        verify(chunkRepository, never()).saveAll(anyList());
        assertThat(indexedChunks.get()).isEmpty();

        final ArgumentCaptor<IndexingOutboxRow> outboxCaptor =
                ArgumentCaptor.forClass(IndexingOutboxRow.class);
        verify(outboxRepository).save(outboxCaptor.capture());
        assertThat(outboxCaptor.getValue().getProcessedAt()).isNotNull();
    }

    @Test
    @DisplayName("E2E: missing authoritative CallSession parks transcript without burning")
    void transcriptIndexed_missingSessionDefersWithoutBurning() throws Exception {
        when(callSessionRepository.findByCallIdForIndexing("call-pending"))
                .thenReturn(Optional.empty());

        final TranscriptIndexedPayload payload =
                new TranscriptIndexedPayload("call-pending", null, 2, "sha256:pending");
        final IndexingOutboxRow row = outboxRow(
                1004L, IndexingEventType.TRANSCRIPT_INDEXED, payload, 1);
        when(outboxRepository.claimUnprocessedForPolling(anyInt(), anyInt())).thenReturn(List.of(row));

        worker.pollAndProcess();

        verify(chunkRepository, never()).saveAll(anyList());
        final ArgumentCaptor<IndexingOutboxRow> outboxCaptor =
                ArgumentCaptor.forClass(IndexingOutboxRow.class);
        verify(outboxRepository).save(outboxCaptor.capture());
        assertThat(outboxCaptor.getValue().getAttemptCount()).isEqualTo(1);
        assertThat(outboxCaptor.getValue().getProcessedAt()).isNull();
        assertThat(outboxCaptor.getValue().getLastError()).contains("CallSession");
    }

    @Test
    @DisplayName("E2E: blank summary drafts do not wipe existing chunks")
    void summaryCreated_emptyDrafts_doesNotDeleteExisting() throws Exception {
        final CallSummary summary = new CallSummary();
        summary.setId(88L);
        summary.setPatientId(42L);
        summary.setStatus("SUCCESS");
        summary.setSummaryJson("   ");
        summary.setCaregiverVisibility("on_consent");
        when(callSummaryRepository.findByIdForUpdate(88L)).thenReturn(Optional.of(summary));
        when(chunkRepository.findCallSummaryChunksForReplacement(
                eq(42L),
                eq("call-summary:88"),
                eq("88"),
                eq(SummarySourceKey.CALL_KIND),
                any()))
                .thenReturn(List.of());

        final SummaryCreatedPayload payload = new SummaryCreatedPayload(
                "call",
                "call_summaries",
                88L,
                "call-blank",
                42L,
                "SUCCESS",
                LocalDateTime.now(),
                0,
                "on_consent",
                null,
                ContentHashUtil.sha256(summary.getSummaryJson()));
        final IndexingOutboxRow row = outboxRow(
                1005L, IndexingEventType.SUMMARY_CREATED, payload, 0);
        when(outboxRepository.claimUnprocessedForPolling(anyInt(), anyInt())).thenReturn(List.of(row));

        worker.pollAndProcess();

        verify(chunkRepository, never()).deleteCallSummaryChunksForReplacement(
                any(), anyString(), anyString(), anyString(), any());
        verify(chunkRepository, never()).saveAll(anyList());
        verify(outboxRepository, atLeastOnce()).save(any(IndexingOutboxRow.class));
    }

    private IndexingOutboxRow outboxRow(
            final Long id,
            final String eventType,
            final Object payload,
            final int attemptCount) throws Exception {
        return IndexingOutboxRow.builder()
                .id(id)
                .eventType(eventType)
                .payloadJson(objectMapper.writeValueAsString(java.util.Map.of(
                        "eventType", eventType,
                        "eventId", "evt-" + id,
                        "occurredAt", "2026-07-11T12:00:00Z",
                        "schemaVersion", 1,
                        "payload", payload)))
                .attemptCount(attemptCount)
                .createdAt(LocalDateTime.now())
                .build();
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
