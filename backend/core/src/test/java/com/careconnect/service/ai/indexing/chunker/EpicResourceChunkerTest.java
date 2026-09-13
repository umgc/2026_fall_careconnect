package com.careconnect.service.ai.indexing.chunker;

import com.careconnect.model.ehr.EhrResource;
import com.careconnect.service.ai.indexing.IndexingChunkDraft;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class EpicResourceChunkerTest {

    private final EpicResourceChunker chunker = new EpicResourceChunker(new ObjectMapper());

    @Test
    void recordTypeFor_mapsClinicalTypes() {
        assertEquals(Optional.of(RetrievalRecordType.EPIC_CONDITION),
                EpicResourceChunker.recordTypeFor("Condition"));
        assertEquals(Optional.of(RetrievalRecordType.EPIC_MEDICATION),
                EpicResourceChunker.recordTypeFor("MedicationRequest"));
        assertEquals(Optional.of(RetrievalRecordType.EPIC_OBSERVATION),
                EpicResourceChunker.recordTypeFor("Observation"));
    }

    @Test
    void recordTypeFor_nonIndexableIsEmpty() {
        assertTrue(EpicResourceChunker.recordTypeFor("Patient").isEmpty());
        assertTrue(EpicResourceChunker.recordTypeFor("Practitioner").isEmpty());
        assertTrue(EpicResourceChunker.recordTypeFor(null).isEmpty());
    }

    @Test
    void chunk_buildsDraftWithProvenanceMetadata() {
        EhrResource resource = EhrResource.builder()
                .userId(7L)
                .source("EPIC")
                .resourceType("Observation")
                .resourceFhirId("obs-123")
                .title("Observation: Hemoglobin A1c")
                .occurredAt("2026-01-15")
                .contentHash("hash-1")
                .payloadJson("{\"resourceType\":\"Observation\",\"status\":\"final\","
                        + "\"code\":{\"text\":\"Hemoglobin A1c\"},"
                        + "\"valueQuantity\":{\"value\":6.1,\"unit\":\"%\"}}")
                .build();

        List<IndexingChunkDraft> drafts = chunker.chunk(resource, "on_consent");
        assertEquals(1, drafts.size());
        IndexingChunkDraft draft = drafts.get(0);
        assertEquals(RetrievalRecordType.EPIC_OBSERVATION, draft.recordType());
        assertEquals("EPIC", draft.metadata().get("sourceSystem"));
        assertEquals("obs-123", draft.metadata().get("fhirResourceId"));
        assertEquals("Observation", draft.metadata().get("fhirResourceType"));
        assertEquals("hash-1", draft.metadata().get("contentHash"));
        assertTrue(draft.chunkText().contains("Hemoglobin A1c"));
        assertTrue(draft.chunkText().contains("6.1"));
    }

    @Test
    void chunk_nonIndexableTypeYieldsNoDrafts() {
        EhrResource patient = EhrResource.builder()
                .userId(7L).source("EPIC").resourceType("Patient").resourceFhirId("p1")
                .payloadJson("{\"resourceType\":\"Patient\"}")
                .build();
        assertFalse(chunker.chunk(patient, null).size() > 0);
    }
}
