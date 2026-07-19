package com.careconnect.service.ai.indexing;

import com.careconnect.indexing.MailpieceIndexedPayload;
import com.careconnect.indexing.SummaryCreatedPayload;
import com.careconnect.indexing.TranscriptIndexedPayload;
import com.careconnect.model.CallSummary;
import com.careconnect.model.CallTranscriptSegment;
import com.careconnect.model.UspsMailpiece;
import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.repository.CallSummaryRepository;
import com.careconnect.repository.CallTranscriptSegmentRepository;
import com.careconnect.repository.UspsMailpieceRepository;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import com.careconnect.service.ai.indexing.chunker.MailpieceChunker;
import com.careconnect.service.ai.embedding.ChunkEmbeddingService;
import com.careconnect.service.ai.indexing.chunker.SummaryChunker;
import com.careconnect.service.ai.indexing.chunker.TranscriptSegmentChunker;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.Collection;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class RetrievalIndexServiceTest {

    @Mock
    private CallSummaryRepository callSummaryRepository;
    @Mock
    private CallTranscriptSegmentRepository transcriptSegmentRepository;
    @Mock
    private UspsMailpieceRepository uspsMailpieceRepository;
    @Mock
    private RetrievalIndexChunkRepository chunkRepository;
    @Mock
    private ChunkEmbeddingService chunkEmbeddingService;

    private RetrievalIndexService service;

    @BeforeEach
    void setUp() {
        final ObjectMapper mapper = new ObjectMapper();
        service = new RetrievalIndexService(
                callSummaryRepository,
                transcriptSegmentRepository,
                uspsMailpieceRepository,
                chunkRepository,
                new SummaryChunker(mapper),
                new TranscriptSegmentChunker(),
                new MailpieceChunker(),
                mapper,
                chunkEmbeddingService);
        lenient().when(chunkRepository.saveAll(anyList())).thenAnswer(inv -> inv.getArgument(0));
    }

    @Test
    @DisplayName("ingestSummaryCreated writes CALL_SUMMARY chunks and replaces prior source rows")
    void ingestSummaryCreated_writesChunks() {
        final CallSummary summary = new CallSummary();
        summary.setId(99L);
        summary.setCallId("call-9");
        summary.setPatientId(42L);
        summary.setStatus("SUCCESS");
        summary.setCaregiverVisibility("on_consent");
        summary.setSummaryJson("""
                {"headline":"Hello","overallAssessment":"Stable","actionItems":[{"text":"Rest"}]}
                """);
        when(callSummaryRepository.findByIdForUpdate(99L)).thenReturn(Optional.of(summary));
        when(chunkRepository.findCallSummaryChunksForReplacement(
                eq(42L), eq("call-summary:99"), eq("99"),
                eq(SummarySourceKey.CALL_KIND), anyCollection()))
                .thenReturn(List.of());

        final SummaryCreatedPayload payload = new SummaryCreatedPayload(
                "call",
                "call_summaries",
                99L,
                "call-9",
                42L,
                "SUCCESS",
                LocalDateTime.now(),
                3,
                "on_consent",
                "aws_bedrock:test",
                "sha256:new");

        final int written = service.ingestSummaryCreated(payload);

        assertThat(written).isGreaterThanOrEqualTo(2);
        verify(chunkRepository).deleteCallSummaryChunksForReplacement(
                eq(42L), eq("call-summary:99"), eq("99"),
                eq(SummarySourceKey.CALL_KIND), anyCollection());
        @SuppressWarnings("unchecked")
        final ArgumentCaptor<List<RetrievalIndexChunk>> captor = ArgumentCaptor.forClass(List.class);
        verify(chunkRepository).saveAll(captor.capture());
        verify(chunkEmbeddingService).embedAndPersist(anyList());
        assertThat(captor.getValue())
                .extracting(RetrievalIndexChunk::getRecordType)
                .contains(RetrievalRecordType.CALL_SUMMARY.name(),
                        RetrievalRecordType.SUMMARY_ACTION_ITEM.name());
        assertThat(captor.getValue().get(0).getPatientId()).isEqualTo(42L);
    }

    @Test
    @DisplayName("ingestSummaryCreated skips when contentHash already indexed (exact match)")
    void ingestSummaryCreated_skipsUnchangedHash() {
        final RetrievalIndexChunk existing = RetrievalIndexChunk.builder()
                .patientId(42L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId(SummarySourceKey.call(99L))
                .sourceKind(SummarySourceKey.CALL_KIND)
                .chunkText("old")
                .consentScope("on_consent")
                .chunkMetadata(
                        "{\"contentHash\":\"sha256:same\","
                                + "\"citationMetadataVersion\":1,\"chunkIndex\":0,"
                                + "\"summarizationEngine\":\"engine\","
                                + "\"section\":\"overview\",\"title\":\"old\","
                                + "\"episodeType\":\"call\",\"callId\":\"call-9\"}")
                .build();
        final CallSummary summary = new CallSummary();
        summary.setId(99L);
        summary.setCallId("call-9");
        summary.setPatientId(42L);
        summary.setStatus("SUCCESS");
        summary.setCaregiverVisibility("on_consent");
        summary.setSummaryJson("{\"headline\":\"old\"}");
        when(callSummaryRepository.findByIdForUpdate(99L)).thenReturn(Optional.of(summary));
        when(chunkRepository.findCallSummaryChunksForReplacement(
                eq(42L), eq("call-summary:99"), eq("99"),
                eq(SummarySourceKey.CALL_KIND), anyCollection()))
                .thenReturn(List.of(existing));
        when(chunkRepository.countMissingEmbeddingForSummarySources(
                eq(42L), eq(summarySources(99L)), anyCollection())).thenReturn(0L);

        final SummaryCreatedPayload payload = new SummaryCreatedPayload(
                "call",
                "call_summaries",
                99L,
                "call-9",
                42L,
                "SUCCESS",
                LocalDateTime.now(),
                1,
                "on_consent",
                "engine",
                "sha256:same");

        assertThat(service.ingestSummaryCreated(payload)).isZero();
        verify(callSummaryRepository).findByIdForUpdate(99L);
        verify(chunkRepository, never()).saveAll(anyList());
        verify(chunkRepository, never()).deleteCallSummaryChunksForReplacement(
                any(), any(), any(), any(), anyCollection());
        verify(chunkEmbeddingService, never()).embedAndPersist(anyList());
    }

    @Test
    @DisplayName("unchanged content rebuilds when authoritative caregiver visibility changes")
    void ingestSummaryCreated_visibilityChanged_rebuildsWithAuthoritativeScope() {
        final CallSummary summary = new CallSummary();
        summary.setId(99L);
        summary.setCallId("call-9");
        summary.setPatientId(42L);
        summary.setStatus("SUCCESS");
        summary.setCaregiverVisibility("hidden");
        summary.setSummaryJson("{\"headline\":\"old\"}");
        when(callSummaryRepository.findByIdForUpdate(99L)).thenReturn(Optional.of(summary));

        final RetrievalIndexChunk existing = RetrievalIndexChunk.builder()
                .patientId(42L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId(SummarySourceKey.call(99L))
                .sourceKind(SummarySourceKey.CALL_KIND)
                .chunkText("old")
                .consentScope("on_consent")
                .chunkMetadata(
                        "{\"contentHash\":\"sha256:same\","
                                + "\"citationMetadataVersion\":1,\"chunkIndex\":0,"
                                + "\"summarizationEngine\":\"engine\","
                                + "\"section\":\"overview\",\"title\":\"old\","
                                + "\"episodeType\":\"call\",\"callId\":\"call-9\"}")
                .build();
        when(chunkRepository.findCallSummaryChunksForReplacement(
                eq(42L), eq("call-summary:99"), eq("99"),
                eq(SummarySourceKey.CALL_KIND), anyCollection()))
                .thenReturn(List.of(existing));

        final int written = service.ingestSummaryCreated(new SummaryCreatedPayload(
                "call", "call_summaries", 99L, "call-9", 42L, "SUCCESS",
                LocalDateTime.now(), 1, "on_consent", "engine", "sha256:same"));

        assertThat(written).isEqualTo(1);
        @SuppressWarnings("unchecked")
        final ArgumentCaptor<List<RetrievalIndexChunk>> captor = ArgumentCaptor.forClass(List.class);
        verify(chunkRepository).saveAll(captor.capture());
        assertThat(captor.getValue().get(0).getConsentScope()).isEqualTo("hidden");
        assertThat(captor.getValue().get(0).getSourceRecordId())
                .isEqualTo("call-summary:99");
    }

    @Test
    @DisplayName("stale event patient scope is rejected before retrieval chunks are touched")
    void ingestSummaryCreated_patientScopeMismatch_isRejected() {
        final CallSummary summary = new CallSummary();
        summary.setId(99L);
        summary.setPatientId(43L);
        summary.setStatus("SUCCESS");
        summary.setSummaryJson("{\"headline\":\"old\"}");
        when(callSummaryRepository.findByIdForUpdate(99L)).thenReturn(Optional.of(summary));

        assertThatThrownBy(() -> service.ingestSummaryCreated(new SummaryCreatedPayload(
                "call", "call_summaries", 99L, "call-9", 42L, "SUCCESS",
                LocalDateTime.now(), 1, "auto", "engine", "sha256:same")))
                .isInstanceOf(IndexingDeferredException.class)
                .satisfies(ex -> assertThat(((IndexingDeferredException) ex).burnsAttempt())
                        .isTrue());

        verify(chunkRepository, never()).findCallSummaryChunksForReplacement(
                any(), any(), any(), any(), anyCollection());
    }

    @Test
    @DisplayName("summary row is locked before scoped chunks are inspected")
    void ingestSummaryCreated_locksBeforeReadingChunks() {
        final CallSummary summary = new CallSummary();
        summary.setId(99L);
        summary.setPatientId(42L);
        summary.setStatus("SUCCESS");
        summary.setSummaryJson("{\"headline\":\"Current\"}");
        when(callSummaryRepository.findByIdForUpdate(99L)).thenReturn(Optional.of(summary));
        when(chunkRepository.findCallSummaryChunksForReplacement(
                eq(42L), eq("call-summary:99"), eq("99"),
                eq(SummarySourceKey.CALL_KIND), anyCollection())).thenReturn(List.of());

        service.ingestSummaryCreated(new SummaryCreatedPayload(
                "call", "call_summaries", 99L, "call-9", 42L, "SUCCESS",
                LocalDateTime.now(), 1, "auto", "engine", "hash"));

        final InOrder order = inOrder(callSummaryRepository, chunkRepository);
        order.verify(callSummaryRepository).findByIdForUpdate(99L);
        order.verify(chunkRepository).findCallSummaryChunksForReplacement(
                eq(42L), eq("call-summary:99"), eq("99"),
                eq(SummarySourceKey.CALL_KIND), anyCollection());
    }

    @Test
    @DisplayName("ingestSummaryCreated rebuilds unchanged content when citation metadata is stale")
    void ingestSummaryCreated_sameHash_staleCitationMetadata_rebuilds() {
        final RetrievalIndexChunk existing = RetrievalIndexChunk.builder()
                .patientId(42L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId("99")
                .chunkText("old")
                .chunkMetadata("{\"contentHash\":\"sha256:same\"}")
                .build();
        when(chunkRepository.findCallSummaryChunksForReplacement(
                eq(42L), eq("call-summary:99"), eq("99"),
                eq(SummarySourceKey.CALL_KIND), anyCollection()))
                .thenReturn(List.of(existing));

        final CallSummary summary = new CallSummary();
        summary.setId(99L);
        summary.setCallId("call-9");
        summary.setPatientId(42L);
        summary.setStatus("SUCCESS");
        summary.setCaregiverVisibility("on_consent");
        final LocalDateTime generatedAt = LocalDateTime.of(2026, 7, 17, 12, 0);
        summary.setGeneratedAt(generatedAt);
        summary.setSummaryJson("{\"headline\":\"Stable\"}");
        when(callSummaryRepository.findByIdForUpdate(99L)).thenReturn(Optional.of(summary));

        final SummaryCreatedPayload payload = new SummaryCreatedPayload(
                "call",
                "call_summaries",
                99L,
                "call-9",
                42L,
                "SUCCESS",
                LocalDateTime.now(),
                1,
                "on_consent",
                "engine",
                "sha256:same");

        assertThat(service.ingestSummaryCreated(payload)).isEqualTo(1);
        verify(chunkRepository).deleteCallSummaryChunksForReplacement(
                eq(42L), eq("call-summary:99"), eq("99"),
                eq(SummarySourceKey.CALL_KIND), anyCollection());
        @SuppressWarnings("unchecked")
        final ArgumentCaptor<List<RetrievalIndexChunk>> captor = ArgumentCaptor.forClass(List.class);
        verify(chunkRepository).saveAll(captor.capture());
        assertThat(captor.getValue().get(0).getChunkMetadata())
                .contains("\"citationMetadataVersion\":1")
                .contains("\"callId\":\"call-9\"")
                .contains("\"occurredAt\":\""
                        + generatedAt.toInstant(ZoneOffset.UTC) + "\"");
    }

    @Test
    @DisplayName("unchanged hash rebuilds when an expected typed summary chunk is missing")
    void ingestSummaryCreated_sameHashMissingTypedChunk_rebuilds() {
        final CallSummary summary = new CallSummary();
        summary.setId(99L);
        summary.setCallId("call-9");
        summary.setPatientId(42L);
        summary.setStatus("SUCCESS");
        summary.setSummaryJson("""
                {"headline":"Stable","actionItems":[{"text":"Call clinician"}]}
                """);
        when(callSummaryRepository.findByIdForUpdate(99L)).thenReturn(Optional.of(summary));

        final RetrievalIndexChunk overviewOnly = RetrievalIndexChunk.builder()
                .patientId(42L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId("99")
                .chunkText("Stable")
                .chunkMetadata(
                        "{\"contentHash\":\"same\",\"citationMetadataVersion\":1,"
                                + "\"chunkIndex\":0}")
                .build();
        when(chunkRepository.findCallSummaryChunksForReplacement(
                eq(42L), eq("call-summary:99"), eq("99"),
                eq(SummarySourceKey.CALL_KIND), anyCollection())).thenReturn(List.of(overviewOnly));

        final int written = service.ingestSummaryCreated(new SummaryCreatedPayload(
                "call", "call_summaries", 99L, "call-9", 42L, "SUCCESS",
                LocalDateTime.now(), 1, "auto", "engine", "same"));

        assertThat(written).isEqualTo(2);
        verify(chunkRepository).deleteCallSummaryChunksForReplacement(
                eq(42L), eq("call-summary:99"), eq("99"),
                eq(SummarySourceKey.CALL_KIND), anyCollection());
    }

    @Test
    @DisplayName("ingestSummaryCreated retries embed when contentHash matches but embeddings missing")
    void ingestSummaryCreated_hashMatch_missingEmbeddings_retriesEmbed() {
        final RetrievalIndexChunk existing = RetrievalIndexChunk.builder()
                .id(java.util.UUID.randomUUID())
                .patientId(42L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId(SummarySourceKey.call(99L))
                .sourceKind(SummarySourceKey.CALL_KIND)
                .chunkText("old")
                .consentScope("on_consent")
                .chunkMetadata(
                        "{\"contentHash\":\"sha256:same\","
                                + "\"citationMetadataVersion\":1,\"chunkIndex\":0,"
                                + "\"summarizationEngine\":\"engine\","
                                + "\"section\":\"overview\",\"title\":\"old\","
                                + "\"episodeType\":\"call\",\"callId\":\"call-9\"}")
                .build();
        final CallSummary summary = new CallSummary();
        summary.setId(99L);
        summary.setCallId("call-9");
        summary.setPatientId(42L);
        summary.setStatus("SUCCESS");
        summary.setCaregiverVisibility("on_consent");
        summary.setSummaryJson("{\"headline\":\"old\"}");
        when(callSummaryRepository.findByIdForUpdate(99L)).thenReturn(Optional.of(summary));
        when(chunkRepository.findCallSummaryChunksForReplacement(
                eq(42L), eq("call-summary:99"), eq("99"),
                eq(SummarySourceKey.CALL_KIND), anyCollection()))
                .thenReturn(List.of(existing));
        when(chunkRepository.countMissingEmbeddingForSummarySources(
                eq(42L), eq(summarySources(99L)), anyCollection())).thenReturn(1L);
        when(chunkRepository.findMissingEmbeddingsForSummarySources(
                eq(42L), eq(summarySources(99L)), anyCollection()))
                .thenReturn(List.of(existing));

        final SummaryCreatedPayload payload = new SummaryCreatedPayload(
                "call",
                "call_summaries",
                99L,
                "call-9",
                42L,
                "SUCCESS",
                LocalDateTime.now(),
                1,
                "on_consent",
                "engine",
                "sha256:same");

        assertThat(service.ingestSummaryCreated(payload)).isZero();
        verify(chunkRepository, never()).saveAll(anyList());
        verify(chunkRepository, never()).deleteCallSummaryChunksForReplacement(
                any(), any(), any(), any(), anyCollection());
        verify(chunkEmbeddingService).embedAndPersist(anyList());
    }

    @Test
    @DisplayName("ingestSummaryCreated does not skip when contentHash is only a prefix substring")
    void ingestSummaryCreated_doesNotSkipOnHashPrefix() {
        final RetrievalIndexChunk existing = RetrievalIndexChunk.builder()
                .patientId(42L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId("99")
                .chunkText("old")
                .chunkMetadata("{\"contentHash\":\"sha256:same-but-longer\"}")
                .build();
        when(chunkRepository.findCallSummaryChunksForReplacement(
                eq(42L), eq("call-summary:99"), eq("99"),
                eq(SummarySourceKey.CALL_KIND), anyCollection()))
                .thenReturn(List.of(existing));

        final CallSummary summary = new CallSummary();
        summary.setId(99L);
        summary.setPatientId(42L);
        summary.setSummaryJson("{\"headline\":\"Updated\"}");
        summary.setCaregiverVisibility("on_consent");
        when(callSummaryRepository.findByIdForUpdate(99L)).thenReturn(Optional.of(summary));

        final SummaryCreatedPayload payload = new SummaryCreatedPayload(
                "call",
                "call_summaries",
                99L,
                "call-9",
                42L,
                "SUCCESS",
                LocalDateTime.now(),
                1,
                "on_consent",
                "engine",
                "sha256:same");

        assertThat(service.ingestSummaryCreated(payload)).isGreaterThan(0);
        verify(chunkRepository).deleteCallSummaryChunksForReplacement(
                eq(42L), eq("call-summary:99"), eq("99"),
                eq(SummarySourceKey.CALL_KIND), anyCollection());
        @SuppressWarnings("unchecked")
        final ArgumentCaptor<List<RetrievalIndexChunk>> captor = ArgumentCaptor.forClass(List.class);
        verify(chunkRepository).saveAll(captor.capture());
        assertThat(captor.getValue())
                .extracting(RetrievalIndexChunk::getSourceRecordId)
                .containsOnly(SummarySourceKey.call(99L));
    }

    @Test
    @DisplayName("ingestSummaryCreated does not delete when drafts are empty")
    void ingestSummaryCreated_emptyDrafts_doesNotDelete() {
        final CallSummary summary = new CallSummary();
        summary.setId(8L);
        summary.setPatientId(42L);
        summary.setSummaryJson("{}");
        summary.setCaregiverVisibility("on_consent");
        when(callSummaryRepository.findByIdForUpdate(8L)).thenReturn(Optional.of(summary));
        when(chunkRepository.findCallSummaryChunksForReplacement(
                eq(42L), eq("call-summary:8"), eq("8"),
                eq(SummarySourceKey.CALL_KIND), anyCollection()))
                .thenReturn(List.of());

        final SummaryCreatedPayload payload = new SummaryCreatedPayload(
                "call", "call_summaries", 8L, "c", 42L, "SUCCESS",
                LocalDateTime.now(), 0, "on_consent", null, "sha256:empty");

        // "{}" no longer dumps compact JSON as overview — empty structured fields => no drafts.
        summary.setSummaryJson("{}");

        assertThat(service.ingestSummaryCreated(payload)).isZero();
        verify(chunkRepository, never()).deleteCallSummaryChunksForReplacement(
                any(), any(), any(), any(), anyCollection());
        verify(chunkRepository, never()).saveAll(anyList());
        verify(chunkEmbeddingService, never()).embedAndPersist(anyList());
    }

    @Test
    @DisplayName("ingestSummaryCreated empty drafts still retries missing embeddings")
    void ingestSummaryCreated_emptyDrafts_retriesMissingEmbeddings() {
        final RetrievalIndexChunk orphan = RetrievalIndexChunk.builder()
                .id(java.util.UUID.randomUUID())
                .patientId(42L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId("8")
                .chunkText("prior")
                .chunkMetadata("{\"contentHash\":\"sha256:other\"}")
                .build();
        final CallSummary summary = new CallSummary();
        summary.setId(8L);
        summary.setPatientId(42L);
        summary.setSummaryJson("{}");
        summary.setCaregiverVisibility("on_consent");
        when(callSummaryRepository.findByIdForUpdate(8L)).thenReturn(Optional.of(summary));
        when(chunkRepository.findCallSummaryChunksForReplacement(
                eq(42L), eq("call-summary:8"), eq("8"),
                eq(SummarySourceKey.CALL_KIND), anyCollection()))
                .thenReturn(List.of(orphan));
        when(chunkRepository.countMissingEmbeddingForSummarySources(
                eq(42L), eq(summarySources(8L)), anyCollection())).thenReturn(1L);
        when(chunkRepository.findMissingEmbeddingsForSummarySources(
                eq(42L), eq(summarySources(8L)), anyCollection()))
                .thenReturn(List.of(orphan));

        final SummaryCreatedPayload payload = new SummaryCreatedPayload(
                "call", "call_summaries", 8L, "c", 42L, "SUCCESS",
                LocalDateTime.now(), 0, "on_consent", null, "sha256:empty");

        assertThat(service.ingestSummaryCreated(payload)).isZero();
        verify(chunkRepository, never()).deleteCallSummaryChunksForReplacement(
                any(), any(), any(), any(), anyCollection());
        verify(chunkEmbeddingService).embedAndPersist(anyList());
    }

    @Test
    @DisplayName("ingestSummaryCreated leaves existing chunks when summary text is blank")
    void ingestSummaryCreated_blankSummary_doesNotDelete() {
        final CallSummary summary = new CallSummary();
        summary.setId(9L);
        summary.setPatientId(42L);
        summary.setSummaryJson("   ");
        summary.setCaregiverVisibility("on_consent");
        when(callSummaryRepository.findByIdForUpdate(9L)).thenReturn(Optional.of(summary));
        when(chunkRepository.findCallSummaryChunksForReplacement(
                eq(42L), eq("call-summary:9"), eq("9"),
                eq(SummarySourceKey.CALL_KIND), anyCollection()))
                .thenReturn(List.of());

        final SummaryCreatedPayload payload = new SummaryCreatedPayload(
                "call", "call_summaries", 9L, "c", 42L, "SUCCESS",
                LocalDateTime.now(), 0, "on_consent", null, "sha256:blank");

        assertThat(service.ingestSummaryCreated(payload)).isZero();
        verify(chunkRepository, never()).deleteCallSummaryChunksForReplacement(
                any(), any(), any(), any(), anyCollection());
        verify(chunkRepository, never()).saveAll(anyList());
    }

    @Test
    @DisplayName("ingestSummaryCreated defers visit summaries until Task 1.4")
    void ingestSummaryCreated_defersVisit() {
        final SummaryCreatedPayload payload = new SummaryCreatedPayload(
                "visit",
                "visit_summaries",
                50L,
                null,
                42L,
                "SUCCESS",
                LocalDateTime.now(),
                0,
                "on_consent",
                null,
                "sha256:v");

        assertThatThrownBy(() -> service.ingestSummaryCreated(payload))
                .isInstanceOf(IndexingDeferredException.class)
                .hasMessageContaining("Task 1.4")
                .satisfies(ex -> assertThat(((IndexingDeferredException) ex).burnsAttempt()).isFalse());
        verify(callSummaryRepository, never()).findByIdForUpdate(any());
        verify(chunkRepository, never()).deleteCallSummaryChunksForReplacement(
                any(), any(), any(), any(), anyCollection());
    }

    @Test
    @DisplayName("ingestSummaryCreated defers when patientId is missing")
    void ingestSummaryCreated_defersWithoutPatientId() {
        final CallSummary summary = new CallSummary();
        summary.setId(7L);
        summary.setSummaryJson("{\"headline\":\"x\"}");
        summary.setPatientId(null);
        when(callSummaryRepository.findByIdForUpdate(7L)).thenReturn(Optional.of(summary));

        final SummaryCreatedPayload payload = new SummaryCreatedPayload(
                "call", "call_summaries", 7L, "c", null, "SUCCESS",
                LocalDateTime.now(), 0, null, null, "sha256:x");

        assertThatThrownBy(() -> service.ingestSummaryCreated(payload))
                .isInstanceOf(IndexingDeferredException.class)
                .hasMessageContaining("patientId");
    }

    @Test
    @DisplayName("metadata replay returns NO_DRAFTS for blank authoritative summary")
    void replaySummaryCitationMetadata_blankSummary_returnsNoDrafts() {
        final CallSummary summary = new CallSummary();
        summary.setId(99L);
        summary.setPatientId(42L);
        summary.setStatus("SUCCESS");
        summary.setSummaryJson(" ");
        when(callSummaryRepository.findByIdForUpdate(99L)).thenReturn(Optional.of(summary));

        assertThat(service.replaySummaryCitationMetadata(99L))
                .isEqualTo(SummaryCitationReplayOutcome.NO_DRAFTS);

        verify(chunkRepository, never()).findCallSummaryChunksForReplacement(
                any(), any(), any(), any(), anyCollection());
    }

    @Test
    @DisplayName("metadata replay migrates a current-version legacy numeric source")
    void replaySummaryCitationMetadata_currentLegacySource_isUpdated() {
        final CallSummary summary = new CallSummary();
        summary.setId(99L);
        summary.setCallId("call-9");
        summary.setPatientId(42L);
        summary.setStatus("SUCCESS");
        summary.setCaregiverVisibility("auto");
        summary.setSummaryJson("{\"headline\":\"Stable\"}");
        when(callSummaryRepository.findByIdForUpdate(99L)).thenReturn(Optional.of(summary));

        final RetrievalIndexChunk legacy = RetrievalIndexChunk.builder()
                .patientId(42L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId("99")
                .chunkText("Stable")
                .consentScope("auto")
                .chunkMetadata(
                        "{\"contentHash\":\""
                                + com.careconnect.util.ContentHashUtil.sha256(summary.getSummaryJson())
                                + "\",\"chunkIndex\":0,\"citationMetadataVersion\":1}")
                .build();
        when(chunkRepository.findCallSummaryChunksForReplacement(
                eq(42L), eq("call-summary:99"), eq("99"),
                eq(SummarySourceKey.CALL_KIND), anyCollection()))
                .thenReturn(List.of(legacy));

        assertThat(service.replaySummaryCitationMetadata(99L))
                .isEqualTo(SummaryCitationReplayOutcome.UPDATED);

        @SuppressWarnings("unchecked")
        final ArgumentCaptor<List<RetrievalIndexChunk>> captor = ArgumentCaptor.forClass(List.class);
        verify(chunkRepository).saveAll(captor.capture());
        assertThat(captor.getValue())
                .allSatisfy(chunk -> {
                    assertThat(chunk.getSourceRecordId()).isEqualTo("call-summary:99");
                    assertThat(chunk.getSourceKind()).isEqualTo(SummarySourceKey.CALL_KIND);
                });
    }

    @Test
    @DisplayName("ingestTranscriptIndexed writes one chunk per segment")
    void ingestTranscriptIndexed_writesSegments() {
        final CallTranscriptSegment segment = new CallTranscriptSegment();
        segment.setId(5L);
        segment.setText("Feeling better today");
        segment.setSpeakerLabel("Patient");
        when(transcriptSegmentRepository.findByCallIdOrderByStartMsAscOccurredAtAsc("call-1"))
                .thenReturn(List.of(segment));

        final int written = service.ingestTranscriptIndexed(
                new TranscriptIndexedPayload("call-1", 42L, 1, "CLIENT_TRANSCRIPT"));

        assertThat(written).isEqualTo(1);
        verify(chunkRepository).deleteBySourceRecordIdAndRecordType(
                "call-1", RetrievalRecordType.TRANSCRIPT_SEGMENT.name());
        verify(chunkRepository).saveAll(anyList());
    }

    @Test
    @DisplayName("ingestTranscriptIndexed does not delete when no segment drafts")
    void ingestTranscriptIndexed_emptyDrafts_doesNotDelete() {
        final CallSummary summary = new CallSummary();
        summary.setPatientId(77L);
        when(callSummaryRepository.findTopByCallIdOrderByGeneratedAtDesc("call-2"))
                .thenReturn(Optional.of(summary));
        when(transcriptSegmentRepository.findByCallIdOrderByStartMsAscOccurredAtAsc("call-2"))
                .thenReturn(List.of());

        assertThat(service.ingestTranscriptIndexed(
                new TranscriptIndexedPayload("call-2", null, 0, "CLIENT_TRANSCRIPT")))
                .isZero();
        verify(chunkRepository, never()).deleteBySourceRecordIdAndRecordType(any(), any());
        verify(chunkRepository, never()).saveAll(anyList());
    }

    @Test
    @DisplayName("ingestTranscriptIndexed defers when patientId cannot be resolved")
    void ingestTranscriptIndexed_defersWithoutPatientId() {
        when(callSummaryRepository.findTopByCallIdOrderByGeneratedAtDesc("call-3"))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.ingestTranscriptIndexed(
                new TranscriptIndexedPayload("call-3", null, 1, "CLIENT_TRANSCRIPT")))
                .isInstanceOf(IndexingDeferredException.class)
                .hasMessageContaining("patientId");
        verify(chunkRepository, never()).deleteBySourceRecordIdAndRecordType(any(), any());
    }

    @Test
    @DisplayName("ingestMailpieceIndexed writes USPS_MAIL chunk and replaces prior source rows")
    void ingestMailpieceIndexed_writesChunk() {
        final UspsMailpiece mailpiece = new UspsMailpiece();
        mailpiece.setId(55L);
        mailpiece.setPatientId(42L);
        mailpiece.setSourceKey("2025-03-03|m-1");
        mailpiece.setSender("Acme Bank");
        mailpiece.setSummary("Monthly statement");
        mailpiece.setContentHash("sha-abc");
        mailpiece.setConsentScope("on_consent");
        when(uspsMailpieceRepository.findById(55L)).thenReturn(Optional.of(mailpiece));
        when(chunkRepository.findBySourceRecordIdAndRecordType(eq("55"), any()))
                .thenReturn(List.of());

        final MailpieceIndexedPayload payload = new MailpieceIndexedPayload(
                55L, 42L, "2025-03-03|m-1", "sha-abc",
                "Acme Bank", "Monthly statement",
                java.time.LocalDate.of(2025, 3, 3), "on_consent");

        final int written = service.ingestMailpieceIndexed(payload);

        assertThat(written).isEqualTo(1);
        verify(chunkRepository).deleteBySourceRecordIdAndRecordType(
                "55", RetrievalRecordType.USPS_MAIL.name());
        @SuppressWarnings("unchecked")
        final ArgumentCaptor<List<RetrievalIndexChunk>> captor = ArgumentCaptor.forClass(List.class);
        verify(chunkRepository).saveAll(captor.capture());
        assertThat(captor.getValue()).hasSize(1);
        assertThat(captor.getValue().get(0).getRecordType())
                .isEqualTo(RetrievalRecordType.USPS_MAIL.name());
        assertThat(captor.getValue().get(0).getPatientId()).isEqualTo(42L);
        assertThat(captor.getValue().get(0).getChunkText()).contains("Acme Bank");
    }

    @Test
    @DisplayName("ingestMailpieceIndexed skips when contentHash and importance fingerprint match")
    void ingestMailpieceIndexed_skipsUnchangedHash() {
        final UspsMailpiece mailpiece = new UspsMailpiece();
        mailpiece.setId(55L);
        mailpiece.setPatientId(42L);
        mailpiece.setContentHash("sha-abc");
        when(uspsMailpieceRepository.findById(55L)).thenReturn(Optional.of(mailpiece));

        final RetrievalIndexChunk existing = RetrievalIndexChunk.builder()
                .recordType(RetrievalRecordType.USPS_MAIL.name())
                .sourceRecordId("55")
                .chunkText("old")
                .chunkMetadata("{\"contentHash\":\"sha-abc\"}")
                .build();
        when(chunkRepository.findBySourceRecordIdAndRecordType(
                "55", RetrievalRecordType.USPS_MAIL.name()))
                .thenReturn(List.of(existing));

        final int written = service.ingestMailpieceIndexed(new MailpieceIndexedPayload(
                55L, 42L, "2025-03-03|m-1", "sha-abc",
                "Acme", "Statement", java.time.LocalDate.of(2025, 3, 3), "on_consent"));

        assertThat(written).isZero();
        verify(chunkRepository, never()).saveAll(anyList());
        verify(chunkRepository, never()).deleteBySourceRecordIdAndRecordType(any(), any());
    }

    @Test
    @DisplayName("ingestMailpieceIndexed rebuilds when hash matches but classification is missing from chunk")
    void ingestMailpieceIndexed_rebuildsOnClassificationBackfill() {
        final UspsMailpiece mailpiece = new UspsMailpiece();
        mailpiece.setId(55L);
        mailpiece.setPatientId(42L);
        mailpiece.setSourceKey("2025-03-03|m-1");
        mailpiece.setSender("Acme Bank");
        mailpiece.setSummary("Monthly statement");
        mailpiece.setContentHash("sha-abc");
        mailpiece.setConsentScope("on_consent");
        mailpiece.setImportanceLevel("HIGH");
        mailpiece.setImportanceCategory("FINANCIAL");
        mailpiece.setClassificationMethod("RULES");
        mailpiece.setImportanceReasoning("Matched bank keyword.");
        when(uspsMailpieceRepository.findById(55L)).thenReturn(Optional.of(mailpiece));

        final RetrievalIndexChunk existing = RetrievalIndexChunk.builder()
                .recordType(RetrievalRecordType.USPS_MAIL.name())
                .sourceRecordId("55")
                .chunkText("old without importance")
                .chunkMetadata("{\"contentHash\":\"sha-abc\"}")
                .build();
        when(chunkRepository.findBySourceRecordIdAndRecordType(
                "55", RetrievalRecordType.USPS_MAIL.name()))
                .thenReturn(List.of(existing));

        final int written = service.ingestMailpieceIndexed(new MailpieceIndexedPayload(
                55L, 42L, "2025-03-03|m-1", "sha-abc",
                "Acme Bank", "Monthly statement",
                java.time.LocalDate.of(2025, 3, 3), "on_consent"));

        assertThat(written).isEqualTo(1);
        verify(chunkRepository).deleteBySourceRecordIdAndRecordType(
                "55", RetrievalRecordType.USPS_MAIL.name());
        @SuppressWarnings("unchecked")
        final ArgumentCaptor<List<RetrievalIndexChunk>> captor = ArgumentCaptor.forClass(List.class);
        verify(chunkRepository).saveAll(captor.capture());
        assertThat(captor.getValue().get(0).getChunkText()).contains("Importance: HIGH");
        assertThat(captor.getValue().get(0).getChunkMetadata()).contains("importanceFingerprint");
    }

    private static Collection<String> anyCollection() {
        return any();
    }

    private static List<String> summarySources(final long summaryId) {
        return List.of(
                SummarySourceKey.call(summaryId),
                SummarySourceKey.legacy(summaryId));
    }
}
