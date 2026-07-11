package com.careconnect.repository.retrieval;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.UUID;

/**
 * Persistence access for Ask AI retrieval index chunks (Task 1.5).
 *
 * <p>Vector and FTS columns are populated by the indexing pipeline via Flyway DDL
 * and native SQL helpers in Task 4.1+.
 */
@Repository
public interface RetrievalIndexChunkRepository extends JpaRepository<RetrievalIndexChunk, UUID> {

    List<RetrievalIndexChunk> findByPatientId(Long patientId);

    List<RetrievalIndexChunk> findByPatientIdAndRecordType(Long patientId, String recordType);

    List<RetrievalIndexChunk> findBySourceRecordIdAndRecordType(String sourceRecordId, String recordType);

    long countByPatientId(Long patientId);

    void deleteBySourceRecordIdAndRecordType(String sourceRecordId, String recordType);

    /**
     * Deletes all chunks for a source record (all record types). Used when re-indexing
     * a summary that emits overview + typed item chunks under the same source id.
     */
    void deleteBySourceRecordId(String sourceRecordId);

    /**
     * Writes a pgvector embedding for an indexed chunk (Task 4.3).
     *
     * @param id        chunk primary key
     * @param embedding pgvector literal, e.g. {@code [0.1,0.2,...]} with
     *                  {@link com.careconnect.model.retrieval.RetrievalIndexSchema#EMBEDDING_DIMENSION} values
     */
    @Modifying
    @Query(
            value = "UPDATE retrieval_index_chunk SET embedding = CAST(:embedding AS vector) WHERE id = :id",
            nativeQuery = true)
    void updateEmbedding(@Param("id") UUID id, @Param("embedding") String embedding);
}
