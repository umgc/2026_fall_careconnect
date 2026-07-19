package com.careconnect.repository.retrieval;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.service.ai.indexing.RetrievalMigrationStatus;
import com.careconnect.service.ai.indexing.SummarySourceKey;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.test.autoconfigure.orm.jpa.TestEntityManager;
import org.springframework.test.context.ActiveProfiles;

import static org.assertj.core.api.Assertions.assertThat;

/** Task 1.5 — JPA persistence smoke tests for retrieval_index_chunk (H2 portable columns). */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
class RetrievalIndexChunkRepositoryTest {

    @Autowired
    private TestEntityManager entityManager;

    @Autowired
    private RetrievalIndexChunkRepository repository;

    @Test
    @DisplayName("saves and finds chunks scoped by patient_id")
    void savesAndFindsByPatientId() {
        RetrievalIndexChunk chunk = RetrievalIndexChunk.builder()
                .patientId(42L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId("summary-100")
                .chunkText("Follow up on blood pressure medication.")
                .consentScope("auto")
                .build();

        repository.saveAndFlush(chunk);
        entityManager.clear();

        assertThat(repository.findByPatientId(42L)).hasSize(1);
        assertThat(repository.countByPatientId(42L)).isEqualTo(1);
        assertThat(repository.findByPatientId(99L)).isEmpty();
    }

    @Test
    @DisplayName("finds chunks by patient_id and record_type")
    void findsByPatientIdAndRecordType() {
        repository.save(RetrievalIndexChunk.builder()
                .patientId(7L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId("summary-1")
                .chunkText("Summary text")
                .build());
        repository.save(RetrievalIndexChunk.builder()
                .patientId(7L)
                .recordType(RetrievalRecordType.TRANSCRIPT_SEGMENT.name())
                .sourceRecordId("call-1")
                .chunkText("Transcript text")
                .build());

        assertThat(repository.findByPatientIdAndRecordType(7L, RetrievalRecordType.CALL_SUMMARY.name()))
                .hasSize(1)
                .allSatisfy(row -> assertThat(row.getRecordType()).isEqualTo("CALL_SUMMARY"));
    }

    @Test
    @DisplayName("supports idempotent re-index lookup by source_record_id and record_type")
    void findsBySourceRecordIdAndRecordType() {
        repository.save(RetrievalIndexChunk.builder()
                .patientId(5L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId("summary-55")
                .chunkText("Indexed once")
                .build());

        assertThat(repository.findBySourceRecordIdAndRecordType("summary-55", RetrievalRecordType.CALL_SUMMARY.name()))
                .hasSize(1);
    }

    @Test
    @DisplayName("deleteBySourceRecordIdAndRecordType removes prior chunks for re-indexing")
    void deletesBySourceForReindex() {
        repository.save(RetrievalIndexChunk.builder()
                .patientId(5L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId("summary-77")
                .chunkText("Version 1")
                .build());

        repository.deleteBySourceRecordIdAndRecordType("summary-77", RetrievalRecordType.CALL_SUMMARY.name());
        repository.flush();

        assertThat(repository.findBySourceRecordIdAndRecordType("summary-77", RetrievalRecordType.CALL_SUMMARY.name()))
                .isEmpty();
    }

    @Test
    @DisplayName("summary replacement is scoped by patient, source, and summary type")
    void deletesSummaryChunksWithoutTouchingCollidingRows() {
        repository.save(RetrievalIndexChunk.builder()
                .patientId(5L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId("77")
                .chunkText("target summary")
                .build());
        repository.save(RetrievalIndexChunk.builder()
                .patientId(6L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId("77")
                .chunkText("other patient's summary")
                .build());
        repository.save(RetrievalIndexChunk.builder()
                .patientId(5L)
                .recordType(RetrievalRecordType.TRANSCRIPT_SEGMENT.name())
                .sourceRecordId("77")
                .chunkText("same-patient non-summary")
                .build());

        repository.deleteByPatientIdAndSourceRecordIdAndRecordTypeIn(
                5L, "77", RetrievalRecordType.summaryTypeNames());
        repository.flush();

        assertThat(repository.findByPatientId(5L))
                .extracting(RetrievalIndexChunk::getRecordType)
                .containsExactly(RetrievalRecordType.TRANSCRIPT_SEGMENT.name());
        assertThat(repository.findByPatientId(6L))
                .extracting(RetrievalIndexChunk::getChunkText)
                .containsExactly("other patient's summary");
    }

    @Test
    @DisplayName("namespaced call replacement preserves same-id visit summary")
    void deletesNamespacedCallSummaryWithoutTouchingVisitCollision() {
        repository.save(RetrievalIndexChunk.builder()
                .patientId(5L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId(SummarySourceKey.call(77L))
                .sourceKind(SummarySourceKey.CALL_KIND)
                .chunkText("call summary")
                .build());
        repository.save(RetrievalIndexChunk.builder()
                .patientId(5L)
                .recordType(RetrievalRecordType.VISIT_SUMMARY.name())
                .sourceRecordId(SummarySourceKey.visit(77L))
                .sourceKind(SummarySourceKey.VISIT_KIND)
                .chunkText("visit summary")
                .build());

        repository.deleteCallSummaryChunksForReplacement(
                5L,
                SummarySourceKey.call(77L),
                SummarySourceKey.legacy(77L),
                SummarySourceKey.CALL_KIND,
                RetrievalRecordType.summaryTypeNames());
        repository.flush();

        assertThat(repository.findByPatientId(5L))
                .extracting(RetrievalIndexChunk::getSourceRecordId)
                .containsExactly(SummarySourceKey.visit(77L));
    }

    @Test
    @DisplayName("ambiguous legacy call/visit collision is not destructively migrated")
    void legacyCallVisitCollision_isPreserved() {
        repository.save(RetrievalIndexChunk.builder()
                .patientId(5L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId("77")
                .chunkText("legacy call")
                .build());
        repository.save(RetrievalIndexChunk.builder()
                .patientId(5L)
                .recordType(RetrievalRecordType.VISIT_SUMMARY.name())
                .sourceRecordId("77")
                .chunkText("legacy visit")
                .build());

        final int deleted = repository.deleteCallSummaryChunksForReplacement(
                5L,
                SummarySourceKey.call(77L),
                SummarySourceKey.legacy(77L),
                SummarySourceKey.CALL_KIND,
                RetrievalRecordType.summaryTypeNames());
        repository.flush();

        assertThat(deleted).isZero();
        assertThat(repository.findByPatientId(5L))
                .extracting(RetrievalIndexChunk::getChunkText)
                .containsExactlyInAnyOrder("legacy call", "legacy visit");
    }

    @Test
    @DisplayName("ambiguous legacy call/visit collision is quarantined from retrieval")
    void ambiguousLegacyCollision_isQuarantined() {
        repository.save(RetrievalIndexChunk.builder()
                .patientId(5L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId("77")
                .chunkText("legacy call")
                .build());
        repository.save(RetrievalIndexChunk.builder()
                .patientId(5L)
                .recordType(RetrievalRecordType.VISIT_SUMMARY.name())
                .sourceRecordId("77")
                .chunkText("legacy visit")
                .build());
        repository.flush();

        assertThat(repository.quarantineAmbiguousLegacySummarySources()).isEqualTo(2);
        repository.flush();

        assertThat(repository.findByPatientId(5L))
                .extracting(RetrievalIndexChunk::getMigrationStatus)
                .containsOnly(RetrievalMigrationStatus.QUARANTINED.name());
    }

    @Test
    @DisplayName("legacy quarantine is patient and summary-type scoped")
    void quarantineLegacySummarySource_preservesUnrelatedRows() {
        repository.save(RetrievalIndexChunk.builder()
                .patientId(5L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId("77")
                .chunkText("legacy summary")
                .build());
        repository.save(RetrievalIndexChunk.builder()
                .patientId(5L)
                .recordType(RetrievalRecordType.TRANSCRIPT_SEGMENT.name())
                .sourceRecordId("77")
                .chunkText("unrelated transcript")
                .build());
        repository.save(RetrievalIndexChunk.builder()
                .patientId(6L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId("77")
                .chunkText("other patient")
                .build());
        repository.flush();

        assertThat(repository.quarantineLegacySummarySource(
                5L, "77", RetrievalRecordType.summaryTypeNames())).isEqualTo(1);
        repository.flush();

        assertThat(repository.findByPatientId(5L))
                .filteredOn(chunk -> "unrelated transcript".equals(chunk.getChunkText()))
                .extracting(RetrievalIndexChunk::getMigrationStatus)
                .containsExactly(RetrievalMigrationStatus.ACTIVE.name());
        assertThat(repository.findByPatientId(6L))
                .extracting(RetrievalIndexChunk::getMigrationStatus)
                .containsOnly(RetrievalMigrationStatus.ACTIVE.name());
    }

    @Test
    void crossPatientLegacyQuarantine_removesCallRiskButPreservesTypedVisit() {
        repository.save(RetrievalIndexChunk.builder()
                .patientId(5L)
                .recordType(RetrievalRecordType.CALL_SUMMARY.name())
                .sourceRecordId("77")
                .sourceKind(SummarySourceKey.CALL_KIND)
                .chunkText("wrong patient call")
                .build());
        repository.save(RetrievalIndexChunk.builder()
                .patientId(6L)
                .recordType(RetrievalRecordType.SUMMARY_ACTION_ITEM.name())
                .sourceRecordId("77")
                .chunkText("ambiguous legacy child")
                .build());
        repository.save(RetrievalIndexChunk.builder()
                .patientId(6L)
                .recordType(RetrievalRecordType.VISIT_SUMMARY.name())
                .sourceRecordId("77")
                .sourceKind(SummarySourceKey.VISIT_KIND)
                .chunkText("typed visit")
                .build());
        repository.flush();

        assertThat(repository.quarantineLegacySummarySourceAcrossPatients(
                "77", RetrievalRecordType.summaryTypeNames())).isEqualTo(2);
        repository.flush();

        assertThat(repository.findByPatientId(5L))
                .extracting(RetrievalIndexChunk::getMigrationStatus)
                .containsOnly(RetrievalMigrationStatus.QUARANTINED.name());
        assertThat(repository.findByPatientId(6L))
                .filteredOn(chunk -> "typed visit".equals(chunk.getChunkText()))
                .extracting(RetrievalIndexChunk::getMigrationStatus)
                .containsExactly(RetrievalMigrationStatus.ACTIVE.name());
    }
}
