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
import com.careconnect.service.ai.indexing.chunker.SummaryChunker;
import com.careconnect.service.ai.indexing.chunker.TranscriptSegmentChunker;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
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
                mapper);
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
        when(callSummaryRepository.findById(99L)).thenReturn(Optional.of(summary));
        when(chunkRepository.findBySourceRecordIdAndRecordType(eq("99"), any()))
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
        verify(chunkRepository).deleteBySourceRecordId("99");
        @SuppressWarnings("unchecked")
        final ArgumentCaptor<List<RetrievalIndexChunk>> captor = ArgumentCaptor.forClass(List.class);
        verify(chunkRepository).saveAll(captor.capture());
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
                .patientId(1L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId("99")
                .chunkText("old")
                .chunkMetadata("{\"contentHash\":\"sha256:same\"}")
                .build();
        when(chunkRepository.findBySourceRecordIdAndRecordType("99", "CALL_SUMMARY"))
                .thenReturn(List.of(existing));
        when(chunkRepository.findBySourceRecordIdAndRecordType("99", "VISIT_SUMMARY"))
                .thenReturn(List.of());

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
        verify(callSummaryRepository, never()).findById(any());
        verify(chunkRepository, never()).saveAll(anyList());
        verify(chunkRepository, never()).deleteBySourceRecordId(any());
    }

    @Test
    @DisplayName("ingestSummaryCreated does not skip when contentHash is only a prefix substring")
    void ingestSummaryCreated_doesNotSkipOnHashPrefix() {
        final RetrievalIndexChunk existing = RetrievalIndexChunk.builder()
                .patientId(1L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId("99")
                .chunkText("old")
                .chunkMetadata("{\"contentHash\":\"sha256:same-but-longer\"}")
                .build();
        when(chunkRepository.findBySourceRecordIdAndRecordType("99", "CALL_SUMMARY"))
                .thenReturn(List.of(existing));
        when(chunkRepository.findBySourceRecordIdAndRecordType("99", "VISIT_SUMMARY"))
                .thenReturn(List.of());

        final CallSummary summary = new CallSummary();
        summary.setId(99L);
        summary.setPatientId(42L);
        summary.setSummaryJson("{\"headline\":\"Updated\"}");
        summary.setCaregiverVisibility("on_consent");
        when(callSummaryRepository.findById(99L)).thenReturn(Optional.of(summary));

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
        verify(chunkRepository).deleteBySourceRecordId("99");
        verify(chunkRepository).saveAll(anyList());
    }

    @Test
    @DisplayName("ingestSummaryCreated does not delete when drafts are empty")
    void ingestSummaryCreated_emptyDrafts_doesNotDelete() {
        final CallSummary summary = new CallSummary();
        summary.setId(8L);
        summary.setPatientId(42L);
        summary.setSummaryJson("{}");
        summary.setCaregiverVisibility("on_consent");
        when(callSummaryRepository.findById(8L)).thenReturn(Optional.of(summary));
        when(chunkRepository.findBySourceRecordIdAndRecordType(eq("8"), any()))
                .thenReturn(List.of());

        final SummaryCreatedPayload payload = new SummaryCreatedPayload(
                "call", "call_summaries", 8L, "c", 42L, "SUCCESS",
                LocalDateTime.now(), 0, "on_consent", null, "sha256:empty");

        // "{}" no longer dumps compact JSON as overview — empty structured fields => no drafts.
        summary.setSummaryJson("{}");

        assertThat(service.ingestSummaryCreated(payload)).isZero();
        verify(chunkRepository, never()).deleteBySourceRecordId(any());
        verify(chunkRepository, never()).saveAll(anyList());
    }

    @Test
    @DisplayName("ingestSummaryCreated leaves existing chunks when summary text is blank")
    void ingestSummaryCreated_blankSummary_doesNotDelete() {
        final CallSummary summary = new CallSummary();
        summary.setId(9L);
        summary.setPatientId(42L);
        summary.setSummaryJson("   ");
        summary.setCaregiverVisibility("on_consent");
        when(callSummaryRepository.findById(9L)).thenReturn(Optional.of(summary));
        when(chunkRepository.findBySourceRecordIdAndRecordType(eq("9"), any()))
                .thenReturn(List.of());

        final SummaryCreatedPayload payload = new SummaryCreatedPayload(
                "call", "call_summaries", 9L, "c", 42L, "SUCCESS",
                LocalDateTime.now(), 0, "on_consent", null, "sha256:blank");

        assertThat(service.ingestSummaryCreated(payload)).isZero();
        verify(chunkRepository, never()).deleteBySourceRecordId(any());
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
        verify(callSummaryRepository, never()).findById(any());
        verify(chunkRepository, never()).deleteBySourceRecordId(any());
    }

    @Test
    @DisplayName("ingestSummaryCreated defers when patientId is missing")
    void ingestSummaryCreated_defersWithoutPatientId() {
        final CallSummary summary = new CallSummary();
        summary.setId(7L);
        summary.setSummaryJson("{\"headline\":\"x\"}");
        summary.setPatientId(null);
        when(callSummaryRepository.findById(7L)).thenReturn(Optional.of(summary));
        when(chunkRepository.findBySourceRecordIdAndRecordType(eq("7"), any()))
                .thenReturn(List.of());

        final SummaryCreatedPayload payload = new SummaryCreatedPayload(
                "call", "call_summaries", 7L, "c", null, "SUCCESS",
                LocalDateTime.now(), 0, null, null, "sha256:x");

        assertThatThrownBy(() -> service.ingestSummaryCreated(payload))
                .isInstanceOf(IndexingDeferredException.class)
                .hasMessageContaining("patientId");
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
    @DisplayName("ingestMailpieceIndexed skips when contentHash matches existing USPS_MAIL chunk")
    void ingestMailpieceIndexed_skipsUnchangedHash() {
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
        verify(uspsMailpieceRepository, never()).findById(any());
        verify(chunkRepository, never()).saveAll(anyList());
    }
}
