package com.careconnect.repository.retrieval;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

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

    List<RetrievalIndexChunk> findByPatientIdAndSourceRecordIdAndRecordTypeIn(
            Long patientId,
            String sourceRecordId,
            Collection<String> recordTypes);

    List<RetrievalIndexChunk> findByPatientIdAndSourceRecordIdInAndRecordTypeIn(
            Long patientId,
            Collection<String> sourceRecordIds,
            Collection<String> recordTypes);

    long countByPatientId(Long patientId);

    void deleteBySourceRecordIdAndRecordType(String sourceRecordId, String recordType);

    void deleteByPatientIdAndSourceRecordIdAndRecordTypeIn(
            Long patientId,
            String sourceRecordId,
            Collection<String> recordTypes);

    void deleteByPatientIdAndSourceRecordIdInAndRecordTypeIn(
            Long patientId,
            Collection<String> sourceRecordIds,
            Collection<String> recordTypes);

    /**
     * Broad cleanup helper retained for tests and administrative maintenance.
     * Production indexing must prefer patient/type-scoped deletion.
     */
    @Deprecated
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
     * Only counts embeddable rows (non-blank {@code chunk_text}) — same filter as backfill/retry.
     */
    @Query(
            value = """
                    SELECT COUNT(*) FROM retrieval_index_chunk
                    WHERE source_record_id = :sourceRecordId
                      AND embedding IS NULL
                      AND chunk_text IS NOT NULL
                      AND TRIM(chunk_text) <> ''
                    """,
            nativeQuery = true)
    long countMissingEmbeddingForSource(@Param("sourceRecordId") String sourceRecordId);

    /**
     * Loads portable columns for chunks that still need Titan embeddings (retry path).
     * Only embeddable rows (non-blank {@code chunk_text}) — aligned with backfill batch query.
     */
    @Query(
            value = """
                    SELECT id, patient_id, record_type, source_record_id, chunk_text,
                           chunk_metadata, indexed_at, consent_scope
                    FROM retrieval_index_chunk
                    WHERE source_record_id = :sourceRecordId
                      AND embedding IS NULL
                      AND chunk_text IS NOT NULL
                      AND TRIM(chunk_text) <> ''
                    """,
            nativeQuery = true)
    List<RetrievalIndexChunk> findBySourceRecordIdAndEmbeddingIsNull(
            @Param("sourceRecordId") String sourceRecordId);

    @Query(
            value = """
                    SELECT COUNT(*) FROM retrieval_index_chunk
                    WHERE patient_id = :patientId
                      AND source_record_id = :sourceRecordId
                      AND record_type IN (:recordTypes)
                      AND embedding IS NULL
                      AND chunk_text IS NOT NULL
                      AND TRIM(chunk_text) <> ''
                    """,
            nativeQuery = true)
    long countMissingEmbeddingForSummary(
            @Param("patientId") Long patientId,
            @Param("sourceRecordId") String sourceRecordId,
            @Param("recordTypes") Collection<String> recordTypes);

    @Query(
            value = """
                    SELECT COUNT(*) FROM retrieval_index_chunk
                    WHERE patient_id = :patientId
                      AND source_record_id IN (:sourceRecordIds)
                      AND record_type IN (:recordTypes)
                      AND embedding IS NULL
                      AND chunk_text IS NOT NULL
                      AND TRIM(chunk_text) <> ''
                    """,
            nativeQuery = true)
    long countMissingEmbeddingForSummarySources(
            @Param("patientId") Long patientId,
            @Param("sourceRecordIds") Collection<String> sourceRecordIds,
            @Param("recordTypes") Collection<String> recordTypes);

    @Query(
            value = """
                    SELECT id, patient_id, record_type, source_record_id, chunk_text,
                           chunk_metadata, indexed_at, consent_scope
                    FROM retrieval_index_chunk
                    WHERE patient_id = :patientId
                      AND source_record_id = :sourceRecordId
                      AND record_type IN (:recordTypes)
                      AND embedding IS NULL
                      AND chunk_text IS NOT NULL
                      AND TRIM(chunk_text) <> ''
                    """,
            nativeQuery = true)
    List<RetrievalIndexChunk> findMissingEmbeddingsForSummary(
            @Param("patientId") Long patientId,
            @Param("sourceRecordId") String sourceRecordId,
            @Param("recordTypes") Collection<String> recordTypes);

    @Query(
            value = """
                    SELECT id, patient_id, record_type, source_record_id, chunk_text,
                           chunk_metadata, indexed_at, consent_scope
                    FROM retrieval_index_chunk
                    WHERE patient_id = :patientId
                      AND source_record_id IN (:sourceRecordIds)
                      AND record_type IN (:recordTypes)
                      AND embedding IS NULL
                      AND chunk_text IS NOT NULL
                      AND TRIM(chunk_text) <> ''
                    """,
            nativeQuery = true)
    List<RetrievalIndexChunk> findMissingEmbeddingsForSummarySources(
            @Param("patientId") Long patientId,
            @Param("sourceRecordIds") Collection<String> sourceRecordIds,
            @Param("recordTypes") Collection<String> recordTypes);

    @Query(
            value = """
                    SELECT DISTINCT source_record_id
                    FROM retrieval_index_chunk
                    WHERE record_type IN (:recordTypes)
                      AND source_record_id ~ '^(call-summary:)?[0-9]+$'
                      AND (
                        source_record_id LIKE 'call-summary:%'
                        OR record_type = 'CALL_SUMMARY'
                        OR chunk_metadata->>'episodeType' = 'call'
                      )
                      AND (
                        chunk_metadata->>'citationReplayAfter' IS NULL
                        OR (chunk_metadata->>'citationReplayAfter')::timestamptz <= NOW()
                      )
                      AND (
                        CASE
                          WHEN COALESCE(chunk_metadata->>'citationMetadataVersion', '')
                                 ~ '^[0-9]+$'
                          THEN (chunk_metadata->>'citationMetadataVersion')::integer
                          ELSE -1
                        END
                      ) < :version
                    ORDER BY source_record_id
                    LIMIT :limit
                    """,
            nativeQuery = true)
    List<String> findStaleSummaryCitationSourceIds(
            @Param("recordTypes") Collection<String> recordTypes,
            @Param("version") int version,
            @Param("limit") int limit);

    @Modifying
    @Transactional
    @Query(
            value = """
                    UPDATE retrieval_index_chunk
                    SET chunk_metadata =
                        jsonb_set(
                            jsonb_set(
                                COALESCE(chunk_metadata, '{}'::jsonb),
                                '{citationReplayAttempts}',
                                to_jsonb(
                                    COALESCE(
                                        CASE
                                          WHEN COALESCE(
                                                chunk_metadata->>'citationReplayAttempts', '')
                                                ~ '^[0-9]+$'
                                          THEN (chunk_metadata->>'citationReplayAttempts')::integer
                                          ELSE 0
                                        END,
                                        0) + 1)),
                            '{citationReplayAfter}',
                            to_jsonb(CAST(:retryAfter AS text)))
                    WHERE source_record_id = :sourceRecordId
                      AND record_type IN (:recordTypes)
                    """,
            nativeQuery = true)
    int markSummaryCitationReplayFailure(
            @Param("sourceRecordId") String sourceRecordId,
            @Param("recordTypes") Collection<String> recordTypes,
            @Param("retryAfter") java.time.OffsetDateTime retryAfter);

    /**
     * Oldest chunks missing embeddings across all sources (Task 4.4 backfill worker).
     */
    @Query(
            value = """
                    SELECT id, patient_id, record_type, source_record_id, chunk_text,
                           chunk_metadata, indexed_at, consent_scope
                    FROM retrieval_index_chunk
                    WHERE embedding IS NULL
                      AND chunk_text IS NOT NULL
                      AND TRIM(chunk_text) <> ''
                    ORDER BY indexed_at ASC NULLS LAST, id ASC
                    LIMIT :limit
                    """,
            nativeQuery = true)
    List<RetrievalIndexChunk> findMissingEmbeddingsForBackfill(@Param("limit") int limit);

    /**
     * Counts embeddable chunks still missing an embedding (Task 4.4 ops / backfill progress).
     */
    @Query(
            value = """
                    SELECT COUNT(*) FROM retrieval_index_chunk
                    WHERE embedding IS NULL
                      AND chunk_text IS NOT NULL
                      AND TRIM(chunk_text) <> ''
                    """,
            nativeQuery = true)
    long countMissingEmbeddingsForBackfill();

    /**
     * Patient-scoped vector similarity search (Task 5.1).
     *
     * <p>Orders by cosine distance ({@code <=>}) using the ivfflat cosine ops index.
     * Only rows with a non-null {@code embedding} are eligible.
     * Production must tune PostgreSQL {@code ivfflat.probes} at the session or database
     * level and validate the recall/latency trade-off with representative data.
     *
     * @param queryEmbedding pgvector literal from {@link com.careconnect.service.ai.embedding.EmbeddingVectorFormat}
     */
    @Query(
            value = """
                    SELECT id, patient_id, record_type, source_record_id, chunk_text,
                           chunk_metadata, indexed_at, consent_scope
                    FROM retrieval_index_chunk
                    WHERE patient_id = :patientId
                      AND embedding IS NOT NULL
                    ORDER BY embedding <=> CAST(:queryEmbedding AS vector),
                             indexed_at DESC
                    LIMIT :limit
                    """,
            nativeQuery = true)
    List<RetrievalIndexChunk> searchByPatientIdVector(
            @Param("patientId") Long patientId,
            @Param("queryEmbedding") String queryEmbedding,
            @Param("limit") int limit);

    /**
     * Patient-scoped vector search with {@code record_type} filter applied before {@code LIMIT}.
     */
    @Query(
            value = """
                    SELECT id, patient_id, record_type, source_record_id, chunk_text,
                           chunk_metadata, indexed_at, consent_scope
                    FROM retrieval_index_chunk
                    WHERE patient_id = :patientId
                      AND embedding IS NOT NULL
                      AND record_type IN (:recordTypes)
                    ORDER BY embedding <=> CAST(:queryEmbedding AS vector),
                             indexed_at DESC
                    LIMIT :limit
                    """,
            nativeQuery = true)
    List<RetrievalIndexChunk> searchByPatientIdVectorAndRecordTypes(
            @Param("patientId") Long patientId,
            @Param("queryEmbedding") String queryEmbedding,
            @Param("recordTypes") Collection<String> recordTypes,
            @Param("limit") int limit);

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
