package com.careconnect.repository.retrieval;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
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
}
