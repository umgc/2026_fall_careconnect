package com.careconnect.service.ai.indexing;

import com.careconnect.indexing.ClinicalNoteIndexedPayload;
import com.careconnect.indexing.DocumentIndexedPayload;
import com.careconnect.indexing.EpicFhirIndexedPayload;
import com.careconnect.indexing.MailpieceIndexedPayload;
import com.careconnect.indexing.SummaryCreatedPayload;
import com.careconnect.indexing.TranscriptIndexedPayload;
import com.careconnect.model.ehr.EhrResource;
import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.repository.CallSessionRepository;
import com.careconnect.repository.CallSummaryRepository;
import com.careconnect.repository.PatientNoteRepository;
import com.careconnect.repository.UserFileRepository;
import com.careconnect.repository.UspsMailpieceRepository;
import com.careconnect.repository.VisitSummaryRepository;
import com.careconnect.repository.ehr.EhrResourceRepository;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import com.careconnect.service.CallTranscriptService;
import com.careconnect.service.ai.embedding.ChunkEmbeddingService;
import com.careconnect.service.ai.indexing.chunker.ClinicalNoteChunker;
import com.careconnect.service.ai.indexing.chunker.DocumentChunker;
import com.careconnect.service.ai.indexing.chunker.EpicResourceChunker;
import com.careconnect.service.ai.indexing.chunker.MailpieceChunker;
import com.careconnect.service.ai.indexing.chunker.SummaryChunker;
import com.careconnect.service.ai.indexing.chunker.TranscriptSegmentChunker;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class RetrievalIndexServiceCoverageTest {

    @Mock private CallSummaryRepository callSummaryRepository;
    @Mock private VisitSummaryRepository visitSummaryRepository;
    @Mock private CallSessionRepository callSessionRepository;
    @Mock private CallTranscriptService callTranscriptService;
    @Mock private UspsMailpieceRepository uspsMailpieceRepository;
    @Mock private PatientNoteRepository patientNoteRepository;
    @Mock private UserFileRepository userFileRepository;
    @Mock private RetrievalIndexChunkRepository chunkRepository;
    @Mock private EhrResourceRepository ehrResourceRepository;
    @Mock private ChunkEmbeddingService chunkEmbeddingService;

    private RetrievalIndexService service;

    @BeforeEach
    void setUp() {
        ObjectMapper mapper = new ObjectMapper();
        service = new RetrievalIndexService(callSummaryRepository, visitSummaryRepository, callSessionRepository,
                callTranscriptService, uspsMailpieceRepository, patientNoteRepository, userFileRepository,
                chunkRepository, new SummaryChunker(mapper), new TranscriptSegmentChunker(), new MailpieceChunker(),
                new ClinicalNoteChunker(), new DocumentChunker(), new EpicResourceChunker(mapper),
                ehrResourceRepository, mapper, chunkEmbeddingService);
        when(chunkRepository.saveAll(anyList())).thenAnswer(inv -> inv.getArgument(0));
    }

    private static EhrResource observation(Long userId, String type) {
        return EhrResource.builder().id(3L).userId(userId).source("EPIC").resourceType(type)
                .resourceFhirId("obs-1").title("Observation: A1c").occurredAt("2026-01-15").contentHash("h-1")
                .payloadJson("{\"resourceType\":\"Observation\",\"status\":\"final\","
                        + "\"code\":{\"text\":\"Hemoglobin A1c\"},\"valueQuantity\":{\"value\":6.1,\"unit\":\"%\"}}")
                .build();
    }

    @Test
    void ingestEpicFhirIndexesAndSkips() {
        when(ehrResourceRepository.findById(3L)).thenReturn(Optional.of(observation(7L, "Observation")));
        assertThat(service.ingestEpicFhir(new EpicFhirIndexedPayload(3L, 7L, "h-1", "on_consent"))).isEqualTo(1);
        verify(chunkEmbeddingService).embedAndPersist(anyList());

        RetrievalIndexChunk same = RetrievalIndexChunk.builder().chunkMetadata("{\"contentHash\":\"h-1\"}").build();
        when(chunkRepository.findByPatientIdAndSourceRecordIdAndRecordType(anyLong(), anyString(), anyString()))
                .thenReturn(List.of(same));
        assertThat(service.ingestEpicFhir(new EpicFhirIndexedPayload(3L, null, "h-1", "on_consent"))).isZero();

        RetrievalIndexChunk bad = RetrievalIndexChunk.builder().chunkMetadata("not json").build();
        when(chunkRepository.findByPatientIdAndSourceRecordIdAndRecordType(anyLong(), anyString(), anyString()))
                .thenReturn(List.of(bad));
        assertThat(service.ingestEpicFhir(new EpicFhirIndexedPayload(3L, 7L, "h-1", "on_consent"))).isEqualTo(1);
    }

    @Test
    void ingestEpicFhirGuards() {
        assertThatThrownBy(() -> service.ingestEpicFhir(null)).isInstanceOf(IllegalArgumentException.class);
        when(ehrResourceRepository.findById(1L)).thenReturn(Optional.empty());
        assertThatThrownBy(() -> service.ingestEpicFhir(new EpicFhirIndexedPayload(1L, 7L, null, null)))
                .isInstanceOf(IllegalArgumentException.class);
        when(ehrResourceRepository.findById(2L)).thenReturn(Optional.of(observation(null, "Observation")));
        assertThatThrownBy(() -> service.ingestEpicFhir(new EpicFhirIndexedPayload(2L, 7L, null, null)))
                .isInstanceOf(RuntimeException.class);
        when(ehrResourceRepository.findById(4L)).thenReturn(Optional.of(observation(7L, "Observation")));
        assertThatThrownBy(() -> service.ingestEpicFhir(new EpicFhirIndexedPayload(4L, 8L, null, null)))
                .isInstanceOf(RuntimeException.class);
        when(ehrResourceRepository.findById(5L)).thenReturn(Optional.of(observation(7L, "Patient")));
        assertThat(service.ingestEpicFhir(new EpicFhirIndexedPayload(5L, 7L, null, null))).isZero();
        EhrResource empty = EhrResource.builder().id(6L).userId(7L).resourceType("Observation")
                .resourceFhirId("x").build();
        when(ehrResourceRepository.findById(6L)).thenReturn(Optional.of(empty));
        service.ingestEpicFhir(new EpicFhirIndexedPayload(6L, 7L, null, null));
    }

    @Test
    void ingestMethodsRejectMissingPayloads() {
        assertThatThrownBy(() -> service.ingestSummaryCreated(null)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.ingestVisitSummaryCreated(null)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.ingestTranscriptIndexed(null)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.ingestMailpieceIndexed(null)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.ingestClinicalNoteIndexed(null)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.ingestDocumentIndexed(null)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.replaySummaryCitationMetadata(null, 1L, UUID.randomUUID(), 1000L))
                .isInstanceOf(IllegalArgumentException.class);
        assertThat(service.replaySummaryCitationMetadata(1L, null, null, 1000L).name())
                .isEqualTo("TERMINAL_QUARANTINED");
        assertThatThrownBy(() -> service.removeIndexedSource(null, "s", RetrievalRecordType.EPIC_CONDITION))
                .isInstanceOf(IllegalArgumentException.class);
        service.removeIndexedSource(1L, "s", RetrievalRecordType.EPIC_CONDITION);
        verify(chunkRepository).deleteByPatientIdAndSourceRecordIdAndRecordType(1L, "s", "EPIC_CONDITION");
    }

    @Test
    void ingestMethodsRejectUnknownRecords() {
        when(callSummaryRepository.findById(any())).thenReturn(Optional.empty());
        when(uspsMailpieceRepository.findById(any())).thenReturn(Optional.empty());
        when(patientNoteRepository.findById(any())).thenReturn(Optional.empty());
        when(userFileRepository.findById(any())).thenReturn(Optional.empty());
        SummaryCreatedPayload summary = new SummaryCreatedPayload("CALL", "call_summary", 9L, "c", 1L, "SUCCESS",
                null, 0, null, null, null);
        assertThatThrownBy(() -> service.ingestSummaryCreated(summary)).isInstanceOf(RuntimeException.class);
        SummaryCreatedPayload failed = new SummaryCreatedPayload("CALL", "call_summary", 9L, "c", 1L, "FAILED",
                null, 0, null, null, null);
        assertThat(service.ingestSummaryCreated(failed)).isZero();
        assertThatThrownBy(() -> service.ingestMailpieceIndexed(
                new MailpieceIndexedPayload(1L, 1L, null, null, null, null, null, null)))
                .isInstanceOf(RuntimeException.class);
        assertThatThrownBy(() -> service.ingestClinicalNoteIndexed(new ClinicalNoteIndexedPayload(1L, 1L, null, null)))
                .isInstanceOf(RuntimeException.class);
        assertThatThrownBy(() -> service.ingestDocumentIndexed(
                new DocumentIndexedPayload(1L, 1L, null, null, null, null)))
                .isInstanceOf(RuntimeException.class);
        assertThatThrownBy(() -> service.ingestTranscriptIndexed(new TranscriptIndexedPayload(" ", 1L, 0, null)))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
