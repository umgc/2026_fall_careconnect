package com.careconnect.repository.retrieval;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Collection;
import java.util.List;
import java.util.UUID;

/**
 * Persistence access for Ask AI retrieval index chunks (Task 1.5).
 *
 * <p>{@code search_vector} is maintained by the PostgreSQL trigger on
 * {@code chunk_text} writes (Task 4.2). Embeddings are written via
 * {@link #updateEmbedding} (Task 4.3).
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
     * Patient-scoped full-text search over {@code search_vector} (Task 4.2).
     *
     * <p>Uses {@code plainto_tsquery('english', :query)} and ranks with
     * {@code ts_rank_cd}. Only portable entity columns are selected so Hibernate
     * can map rows without binding {@code search_vector} / {@code embedding}.
     *
     * @param patientId mandatory RBAC scope key (FR-AI-1)
     * @param query     keyword query text (already length-capped by the service)
     * @param limit     max rows to return
     * @return ranked matches for the patient
     */
    @Query(
            value = """
                    SELECT id, patient_id, record_type, source_record_id, chunk_text,
                           chunk_metadata, indexed_at, consent_scope
                    FROM retrieval_index_chunk
                    WHERE patient_id = :patientId
                      AND search_vector @@ plainto_tsquery('english', :query)
                    ORDER BY ts_rank_cd(search_vector, plainto_tsquery('english', :query)) DESC,
                             indexed_at DESC
                    LIMIT :limit
                    """,
            nativeQuery = true)
    List<RetrievalIndexChunk> searchByPatientIdFullText(
            @Param("patientId") Long patientId,
            @Param("query") String query,
            @Param("limit") int limit);

    /**
     * Patient-scoped FTS with an explicit {@code record_type} filter applied
     * <em>before</em> {@code LIMIT} so top-k is filled with allowed types only.
     *
     * @param recordTypes non-empty set of {@link com.careconnect.service.ai.retrieval.RetrievalRecordType}
     *                    names
     */
    @Query(
            value = """
                    SELECT id, patient_id, record_type, source_record_id, chunk_text,
                           chunk_metadata, indexed_at, consent_scope
                    FROM retrieval_index_chunk
                    WHERE patient_id = :patientId
                      AND search_vector @@ plainto_tsquery('english', :query)
                      AND record_type IN (:recordTypes)
                    ORDER BY ts_rank_cd(search_vector, plainto_tsquery('english', :query)) DESC,
                             indexed_at DESC
                    LIMIT :limit
                    """,
            nativeQuery = true)
    List<RetrievalIndexChunk> searchByPatientIdFullTextAndRecordTypes(
            @Param("patientId") Long patientId,
            @Param("query") String query,
            @Param("recordTypes") Collection<String> recordTypes,
            @Param("limit") int limit);

    /**
     * Counts chunks whose {@code search_vector} is still null after indexing.
     * Should be zero once the Task 4.2 trigger + backfill have run.
     */
    @Query(
            value = "SELECT COUNT(*) FROM retrieval_index_chunk WHERE search_vector IS NULL",
            nativeQuery = true)
    long countMissingSearchVector();

    /**
     * Counts chunks still missing an embedding after Task 4.3 ingest (ops / Task 4.4 backfill).
     */
    @Query(
            value = "SELECT COUNT(*) FROM retrieval_index_chunk WHERE embedding IS NULL",
            nativeQuery = true)
    long countMissingEmbedding();

    /**
     * Counts NULL embeddings for a single source record (Task 4.3 contentHash short-circuit).
     */
    @Query(
            value = """
                    SELECT COUNT(*) FROM retrieval_index_chunk
                    WHERE source_record_id = :sourceRecordId
                      AND embedding IS NULL
                    """,
            nativeQuery = true)
    long countMissingEmbeddingForSource(@Param("sourceRecordId") String sourceRecordId);

    /**
     * Loads portable columns for chunks that still need Titan embeddings (retry path).
     */
    @Query(
            value = """
                    SELECT id, patient_id, record_type, source_record_id, chunk_text,
                           chunk_metadata, indexed_at, consent_scope
                    FROM retrieval_index_chunk
                    WHERE source_record_id = :sourceRecordId
                      AND embedding IS NULL
                    """,
            nativeQuery = true)
    List<RetrievalIndexChunk> findBySourceRecordIdAndEmbeddingIsNull(
            @Param("sourceRecordId") String sourceRecordId);

    /**
     * Writes a pgvector embedding for an indexed chunk (Task 4.3).
     *
     * @param id        chunk primary key
     * @param embedding pgvector literal, e.g. {@code [0.1,0.2,...]} with
     *                  {@link com.careconnect.model.retrieval.RetrievalIndexSchema#EMBEDDING_DIMENSION} values
     */
    @Modifying(clearAutomatically = true)
    @Query(
            value = "UPDATE retrieval_index_chunk SET embedding = CAST(:embedding AS vector) WHERE id = :id",
            nativeQuery = true)
    void updateEmbedding(@Param("id") UUID id, @Param("embedding") String embedding);
}
