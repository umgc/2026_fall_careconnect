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
    void recordTypeFor_mapsEncounterToEpicEncounter() {
        assertEquals(Optional.of(RetrievalRecordType.EPIC_ENCOUNTER),
                EpicResourceChunker.recordTypeFor("Encounter"));
    }

    @Test
    void chunk_encounter_flattensTypeClassAndPeriod() {
        EhrResource encounter = EhrResource.builder()
                .userId(7L)
                .source("EPIC")
                .resourceType("Encounter")
                .resourceFhirId("enc-1")
                .title("Encounter: Office Visit")
                .occurredAt("2026-02-01")
                .contentHash("hash-enc")
                .payloadJson("{\"resourceType\":\"Encounter\",\"status\":\"finished\","
                        + "\"class\":{\"code\":\"AMB\",\"display\":\"ambulatory\"},"
                        + "\"type\":[{\"text\":\"Office Visit\"}],"
                        + "\"period\":{\"start\":\"2026-02-01\",\"end\":\"2026-02-01\"}}")
                .build();

        List<IndexingChunkDraft> drafts = chunker.chunk(encounter, "on_consent");
        assertEquals(1, drafts.size());
        IndexingChunkDraft draft = drafts.get(0);
        assertEquals(RetrievalRecordType.EPIC_ENCOUNTER, draft.recordType());
        assertEquals("Encounter", draft.metadata().get("fhirResourceType"));
        assertTrue(draft.chunkText().contains("Office Visit"));
        assertTrue(draft.chunkText().contains("ambulatory"));
        assertTrue(draft.chunkText().contains("2026-02-01"));
    }

    @Test
    void recordTypeFor_mapsAddedCarePlanningTypes() {
        assertEquals(Optional.of(RetrievalRecordType.EPIC_CARE_PLAN),
                EpicResourceChunker.recordTypeFor("CarePlan"));
        assertEquals(Optional.of(RetrievalRecordType.EPIC_GOAL),
                EpicResourceChunker.recordTypeFor("Goal"));
        assertEquals(Optional.of(RetrievalRecordType.EPIC_CARE_TEAM),
                EpicResourceChunker.recordTypeFor("CareTeam"));
        assertEquals(Optional.of(RetrievalRecordType.EPIC_FAMILY_HISTORY),
                EpicResourceChunker.recordTypeFor("FamilyMemberHistory"));
        assertEquals(Optional.of(RetrievalRecordType.EPIC_COVERAGE),
                EpicResourceChunker.recordTypeFor("Coverage"));
        assertEquals(Optional.of(RetrievalRecordType.EPIC_DEVICE),
                EpicResourceChunker.recordTypeFor("Device"));
    }

    @Test
    void chunk_goal_flattensLifecycleStatusAndDescription() {
        EhrResource goal = EhrResource.builder()
                .userId(7L).source("EPIC").resourceType("Goal").resourceFhirId("goal-1")
                .title("Goal: Lower A1c below 7%")
                .contentHash("hash-goal")
                .payloadJson("{\"resourceType\":\"Goal\",\"lifecycleStatus\":\"active\","
                        + "\"description\":{\"text\":\"Lower A1c below 7%\"},"
                        + "\"startDate\":\"2026-03-01\"}")
                .build();

        List<IndexingChunkDraft> drafts = chunker.chunk(goal, "on_consent");
        assertEquals(1, drafts.size());
        IndexingChunkDraft draft = drafts.get(0);
        assertEquals(RetrievalRecordType.EPIC_GOAL, draft.recordType());
        assertTrue(draft.chunkText().contains("active"));
        assertTrue(draft.chunkText().contains("Lower A1c below 7%"));
        assertTrue(draft.chunkText().contains("2026-03-01"));
    }

    @Test
    void chunk_familyHistory_flattensRelationship() {
        EhrResource fmh = EhrResource.builder()
                .userId(7L).source("EPIC").resourceType("FamilyMemberHistory").resourceFhirId("fmh-1")
                .title("FamilyMemberHistory: Mother")
                .contentHash("hash-fmh")
                .payloadJson("{\"resourceType\":\"FamilyMemberHistory\",\"status\":\"completed\","
                        + "\"relationship\":{\"text\":\"Mother\"}}")
                .build();

        List<IndexingChunkDraft> drafts = chunker.chunk(fmh, "on_consent");
        assertEquals(1, drafts.size());
        assertEquals(RetrievalRecordType.EPIC_FAMILY_HISTORY, drafts.get(0).recordType());
        assertTrue(drafts.get(0).chunkText().contains("Mother"));
    }

    @Test
    void chunk_coverage_flattensPayorDisplay() {
        EhrResource coverage = EhrResource.builder()
                .userId(7L).source("EPIC").resourceType("Coverage").resourceFhirId("cov-1")
                .title("Coverage: PPO")
                .contentHash("hash-cov")
                .payloadJson("{\"resourceType\":\"Coverage\",\"status\":\"active\","
                        + "\"type\":{\"text\":\"PPO\"},"
                        + "\"payor\":[{\"display\":\"Acme Health Plan\"}]}")
                .build();

        List<IndexingChunkDraft> drafts = chunker.chunk(coverage, "on_consent");
        assertEquals(1, drafts.size());
        assertEquals(RetrievalRecordType.EPIC_COVERAGE, drafts.get(0).recordType());
        assertTrue(drafts.get(0).chunkText().contains("Acme Health Plan"));
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
