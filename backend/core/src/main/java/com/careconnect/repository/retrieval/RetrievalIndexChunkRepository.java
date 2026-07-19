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

    interface SummaryReplayCandidate {
        Long getPatientId();

        String getSourceRecordId();

        String getSourceKind();

        UUID getClaimToken();
    }

    List<RetrievalIndexChunk> findByPatientId(Long patientId);

    List<RetrievalIndexChunk> findByPatientIdAndRecordType(Long patientId, String recordType);

    List<RetrievalIndexChunk> findByPatientIdAndSourceRecordIdAndRecordType(
            Long patientId, String sourceRecordId, String recordType);

    List<RetrievalIndexChunk> findByPatientIdAndSourceRecordIdAndRecordTypeIn(
            Long patientId,
            String sourceRecordId,
            Collection<String> recordTypes);

    List<RetrievalIndexChunk> findByPatientIdAndSourceRecordIdInAndRecordTypeIn(
            Long patientId,
            Collection<String> sourceRecordIds,
            Collection<String> recordTypes);

    long countByPatientId(Long patientId);

    void deleteByPatientIdAndSourceRecordIdAndRecordType(
            Long patientId, String sourceRecordId, String recordType);

    void deleteByPatientIdAndSourceRecordIdAndRecordTypeIn(
            Long patientId,
            String sourceRecordId,
            Collection<String> recordTypes);

    void deleteByPatientIdAndSourceRecordIdInAndRecordTypeIn(
            Long patientId,
            Collection<String> sourceRecordIds,
            Collection<String> recordTypes);

    @Query(
            value = """
                    SELECT ric.id, ric.patient_id, ric.record_type, ric.source_record_id,
                           ric.chunk_text, ric.chunk_metadata, ric.indexed_at,
                           ric.consent_scope, ric.source_kind,
                           ric.citation_replay_after, ric.citation_replay_attempts,
                           ric.citation_replay_claimed_until, ric.citation_replay_claim_token,
                           ric.migration_status
                    FROM retrieval_index_chunk ric
                    WHERE ric.patient_id = :patientId
                      AND ric.record_type IN (:recordTypes)
                      AND ric.source_record_id = :currentSourceRecordId
                      AND (ric.source_kind = :sourceKind OR ric.source_kind IS NULL)
                      AND ric.source_record_id <> :legacySourceRecordId
                    """,
            nativeQuery = true)
    List<RetrievalIndexChunk> findCallSummaryChunksForReplacement(
            @Param("patientId") Long patientId,
            @Param("currentSourceRecordId") String currentSourceRecordId,
            @Param("legacySourceRecordId") String legacySourceRecordId,
            @Param("sourceKind") String sourceKind,
            @Param("recordTypes") Collection<String> recordTypes);

    @Modifying(clearAutomatically = true)
    @Query(
            value = """
                    DELETE FROM retrieval_index_chunk ric
                    WHERE ric.patient_id = :patientId
                      AND ric.record_type IN (:recordTypes)
                      AND ric.source_record_id = :currentSourceRecordId
                      AND (ric.source_kind = :sourceKind OR ric.source_kind IS NULL)
                      AND ric.source_record_id <> :legacySourceRecordId
                    """,
            nativeQuery = true)
    int deleteCallSummaryChunksForReplacement(
            @Param("patientId") Long patientId,
            @Param("currentSourceRecordId") String currentSourceRecordId,
            @Param("legacySourceRecordId") String legacySourceRecordId,
            @Param("sourceKind") String sourceKind,
            @Param("recordTypes") Collection<String> recordTypes);

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
                           chunk_metadata, indexed_at, consent_scope, source_kind,
                           citation_replay_after, citation_replay_attempts,
                           citation_replay_claimed_until, citation_replay_claim_token,
                           migration_status
                    FROM retrieval_index_chunk
                    WHERE patient_id = :patientId
                      AND migration_status = 'ACTIVE'
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
                           chunk_metadata, indexed_at, consent_scope, source_kind,
                           citation_replay_after, citation_replay_attempts,
                           citation_replay_claimed_until, citation_replay_claim_token,
                           migration_status
                    FROM retrieval_index_chunk
                    WHERE patient_id = :patientId
                      AND migration_status = 'ACTIVE'
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
                           chunk_metadata, indexed_at, consent_scope, source_kind,
                           citation_replay_after, citation_replay_attempts,
                           citation_replay_claimed_until, citation_replay_claim_token,
                           migration_status
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
                           chunk_metadata, indexed_at, consent_scope, source_kind,
                           citation_replay_after, citation_replay_attempts,
                           citation_replay_claimed_until, citation_replay_claim_token,
                           migration_status
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
                           chunk_metadata, indexed_at, consent_scope, source_kind,
                           citation_replay_after, citation_replay_attempts,
                           citation_replay_claimed_until, citation_replay_claim_token,
                           migration_status
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
                    SELECT DISTINCT
                           replay.patient_id AS "patientId",
                           replay.source_record_id AS "sourceRecordId",
                           replay.source_kind AS "sourceKind"
                    FROM summary_citation_replay_source replay
                    WHERE replay.source_kind = 'CALL_SUMMARY'
                      AND replay.migration_status = 'ACTIVE'
                      AND (replay.replay_after IS NULL OR replay.replay_after <= NOW())
                      AND (replay.claimed_until IS NULL OR replay.claimed_until <= NOW())
                      AND EXISTS (
                        SELECT 1
                        FROM retrieval_index_chunk ric
                        WHERE ric.patient_id = replay.patient_id
                          AND ric.record_type IN (:recordTypes)
                          AND ric.migration_status = 'ACTIVE'
                          AND ric.source_kind = replay.source_kind
                          AND ric.source_record_id = replay.source_record_id
                          AND CASE
                                WHEN COALESCE(
                                  ric.chunk_metadata->>'citationMetadataVersion', '')
                                  ~ '^[0-9]{1,9}$'
                                THEN (ric.chunk_metadata->>'citationMetadataVersion')::integer
                                ELSE -1
                              END < :version
                        UNION ALL
                        SELECT 1
                        FROM retrieval_index_chunk legacy
                        WHERE legacy.patient_id = replay.patient_id
                          AND legacy.record_type IN (:recordTypes)
                          AND legacy.migration_status = 'QUARANTINED'
                          AND legacy.source_kind IS NULL
                          AND replay.source_record_id ~ '^call-summary:[0-9]+$'
                          AND legacy.source_record_id =
                              SUBSTRING(replay.source_record_id FROM 14)
                      )
                    ORDER BY replay.replay_after ASC NULLS FIRST,
                             replay.attempts,
                             replay.patient_id,
                             replay.source_record_id
                    LIMIT :limit
                    """,
            nativeQuery = true)
    List<SummaryReplayCandidate> findStaleSummaryCitationSources(
            @Param("recordTypes") Collection<String> recordTypes,
            @Param("version") int version,
            @Param("limit") int limit);

    @Transactional
    @Query(
            value = """
                    WITH locked_sources AS (
                      SELECT replay.patient_id, replay.source_kind,
                             replay.source_record_id
                      FROM summary_citation_replay_source replay
                      WHERE replay.source_kind = 'CALL_SUMMARY'
                        AND replay.migration_status = 'ACTIVE'
                        AND (replay.replay_after IS NULL OR replay.replay_after <= NOW())
                        AND (replay.claimed_until IS NULL OR replay.claimed_until <= NOW())
                        AND EXISTS (
                          SELECT 1
                          FROM retrieval_index_chunk ric
                          WHERE ric.patient_id = replay.patient_id
                            AND ric.record_type IN (:recordTypes)
                            AND ric.migration_status = 'ACTIVE'
                            AND ric.source_kind = replay.source_kind
                            AND ric.source_record_id = replay.source_record_id
                            AND CASE
                                  WHEN COALESCE(
                                    ric.chunk_metadata->>'citationMetadataVersion', '')
                                    ~ '^[0-9]{1,9}$'
                                  THEN (ric.chunk_metadata->>'citationMetadataVersion')::integer
                                  ELSE -1
                                END < :version
                          UNION ALL
                          SELECT 1
                          FROM retrieval_index_chunk legacy
                          WHERE legacy.patient_id = replay.patient_id
                            AND legacy.record_type IN (:recordTypes)
                            AND legacy.migration_status = 'QUARANTINED'
                            AND legacy.source_kind IS NULL
                            AND replay.source_record_id ~ '^call-summary:[0-9]+$'
                            AND legacy.source_record_id =
                                SUBSTRING(replay.source_record_id FROM 14)
                        )
                      ORDER BY replay.replay_after ASC NULLS FIRST,
                               replay.attempts ASC,
                               replay.patient_id,
                               replay.source_kind,
                               replay.source_record_id
                      FOR UPDATE OF replay SKIP LOCKED
                      LIMIT :limit
                    ),
                    claimed_sources AS (
                      UPDATE summary_citation_replay_source replay
                      SET claimed_until = :claimedUntil,
                          claim_token = :claimToken,
                          updated_at = NOW()
                      FROM locked_sources candidate
                      WHERE replay.patient_id = candidate.patient_id
                        AND replay.source_kind = candidate.source_kind
                        AND replay.source_record_id = candidate.source_record_id
                      RETURNING replay.patient_id, replay.source_kind,
                                replay.source_record_id, replay.claim_token
                    )
                    SELECT claimed.patient_id AS "patientId",
                           claimed.source_record_id AS "sourceRecordId",
                           claimed.source_kind AS "sourceKind",
                           claimed.claim_token AS "claimToken"
                    FROM claimed_sources claimed
                    ORDER BY claimed.patient_id, claimed.source_record_id
                    """,
            nativeQuery = true)
    List<SummaryReplayCandidate> claimStaleSummaryCitationSources(
            @Param("recordTypes") Collection<String> recordTypes,
            @Param("version") int version,
            @Param("limit") int limit,
            @Param("claimedUntil") java.time.OffsetDateTime claimedUntil,
            @Param("claimToken") UUID claimToken);

    @Modifying(clearAutomatically = true)
    @Transactional
    @Query(
            value = """
                    UPDATE summary_citation_replay_source
                    SET attempts =
                          CASE WHEN attempts < 2147483647
                               THEN attempts + 1
                               ELSE 2147483647 END,
                        replay_after = :retryAfter,
                        claimed_until = NULL,
                        claim_token = NULL,
                        updated_at = NOW()
                    WHERE patient_id = :patientId
                      AND source_record_id = :sourceRecordId
                      AND source_kind = 'CALL_SUMMARY'
                      AND migration_status = 'ACTIVE'
                      AND claim_token = :claimToken
                    """,
            nativeQuery = true)
    int markSummaryCitationReplayFailure(
            @Param("patientId") Long patientId,
            @Param("sourceRecordId") String sourceRecordId,
            @Param("retryAfter") java.time.OffsetDateTime retryAfter,
            @Param("claimToken") UUID claimToken);

    @Modifying(clearAutomatically = true)
    @Transactional
    @Query(
            value = """
                    UPDATE summary_citation_replay_source
                    SET claimed_until = NULL,
                        claim_token = NULL,
                        updated_at = NOW()
                    WHERE patient_id = :patientId
                      AND source_record_id = :sourceRecordId
                      AND source_kind = 'CALL_SUMMARY'
                      AND migration_status = 'ACTIVE'
                      AND claim_token = :claimToken
                    """,
            nativeQuery = true)
    int releaseSummaryCitationReplayClaim(
            @Param("patientId") Long patientId,
            @Param("sourceRecordId") String sourceRecordId,
            @Param("claimToken") UUID claimToken);

    @Modifying(clearAutomatically = true)
    @Transactional
    @Query(
            value = """
                    WITH fenced AS (
                      UPDATE summary_citation_replay_source
                      SET migration_status = 'QUARANTINED',
                          claimed_until = NULL,
                          claim_token = NULL,
                          updated_at = NOW()
                      WHERE patient_id = :patientId
                        AND source_record_id = :sourceRecordId
                        AND source_kind = 'CALL_SUMMARY'
                        AND migration_status = 'ACTIVE'
                        AND claim_token = :claimToken
                      RETURNING patient_id, source_kind, source_record_id
                    )
                    UPDATE retrieval_index_chunk ric
                    SET migration_status = 'QUARANTINED',
                        citation_replay_claimed_until = NULL,
                        citation_replay_claim_token = NULL
                    FROM fenced
                    WHERE ric.patient_id = fenced.patient_id
                      AND ric.source_kind = fenced.source_kind
                      AND ric.source_record_id = fenced.source_record_id
                      AND ric.record_type IN (:recordTypes)
                    """,
            nativeQuery = true)
    int quarantineSummarySource(
            @Param("patientId") Long patientId,
            @Param("sourceRecordId") String sourceRecordId,
            @Param("recordTypes") Collection<String> recordTypes,
            @Param("claimToken") UUID claimToken);

    @Modifying
    @Transactional
    @Query(
            value = """
                    INSERT INTO summary_citation_replay_source (
                      patient_id, source_kind, source_record_id)
                    VALUES (:patientId, :sourceKind, :sourceRecordId)
                    ON CONFLICT (patient_id, source_kind, source_record_id)
                    DO UPDATE SET migration_status = 'ACTIVE', updated_at = NOW()
                    """,
            nativeQuery = true)
    void registerSummaryCitationReplaySource(
            @Param("patientId") Long patientId,
            @Param("sourceKind") String sourceKind,
            @Param("sourceRecordId") String sourceRecordId);

    /**
     * Registers authoritative recovery without mutating ambiguous numeric chunks.
     * Replaying writes a canonical namespaced source; legacy rows remain quarantined.
     */
    @Modifying(clearAutomatically = true)
    @Transactional
    @Query(
            value = """
                    INSERT INTO summary_citation_replay_source (
                      patient_id, source_kind, source_record_id)
                    SELECT :patientId, 'CALL_SUMMARY', 'call-summary:' || cs.id
                    FROM call_summaries cs
                    WHERE cs.id::text = :sourceRecordId
                      AND cs.patient_id = :patientId
                      AND EXISTS (
                        SELECT 1 FROM retrieval_index_chunk ric
                        WHERE ric.patient_id = :patientId
                          AND ric.source_record_id = :sourceRecordId
                          AND ric.record_type IN (:recordTypes)
                          AND ric.source_kind IS NULL
                          AND ric.migration_status = 'QUARANTINED')
                    ON CONFLICT (patient_id, source_kind, source_record_id)
                    DO UPDATE SET migration_status = 'ACTIVE',
                                  replay_after = NULL,
                                  claimed_until = NULL,
                                  claim_token = NULL,
                                  updated_at = NOW()
                    """,
            nativeQuery = true)
    int promoteReconciledLegacySummarySource(
            @Param("patientId") Long patientId,
            @Param("sourceRecordId") String sourceRecordId,
            @Param("recordTypes") Collection<String> recordTypes);

    @Modifying(clearAutomatically = true)
    @Transactional
    @Query(
            value = """
                    UPDATE retrieval_index_chunk
                    SET migration_status = 'QUARANTINED',
                        citation_replay_claimed_until = NULL,
                        citation_replay_claim_token = NULL
                    WHERE patient_id = :patientId
                      AND source_record_id = :sourceRecordId
                      AND record_type IN (:recordTypes)
                      AND (source_kind IS NULL OR source_kind = 'CALL_SUMMARY')
                      AND migration_status = 'ACTIVE'
                    """,
            nativeQuery = true)
    int quarantineLegacySummarySource(
            @Param("patientId") Long patientId,
            @Param("sourceRecordId") String sourceRecordId,
            @Param("recordTypes") Collection<String> recordTypes);

    /**
     * Quarantines ambiguous or call-owned numeric rows across every patient scope.
     * Typed visit rows are preserved even when their table-local ID collides.
     */
    @Modifying(clearAutomatically = true)
    @Transactional
    @Query(
            value = """
                    UPDATE retrieval_index_chunk
                    SET migration_status = 'QUARANTINED',
                        citation_replay_claimed_until = NULL,
                        citation_replay_claim_token = NULL
                    WHERE source_record_id = :sourceRecordId
                      AND record_type IN (:recordTypes)
                      AND (source_kind IS NULL OR source_kind = 'CALL_SUMMARY')
                      AND migration_status = 'ACTIVE'
                    """,
            nativeQuery = true)
    int quarantineLegacySummarySourceAcrossPatients(
            @Param("sourceRecordId") String sourceRecordId,
            @Param("recordTypes") Collection<String> recordTypes);

    /**
     * Administrative fail-closed cleanup for all unowned numeric summary sources.
     * New replay code quarantines each authoritative candidate independently.
     */
    @Deprecated
    @Modifying(clearAutomatically = true)
    @Transactional
    @Query(
            value = """
                    UPDATE retrieval_index_chunk
                    SET migration_status = 'QUARANTINED'
                    WHERE source_record_id ~ '^[0-9]+$'
                      AND source_kind IS NULL
                      AND record_type IN (
                        'CALL_SUMMARY', 'VISIT_SUMMARY', 'SUMMARY_ACTION_ITEM',
                        'SUMMARY_APPOINTMENT', 'SUMMARY_CARE_INSTRUCTION',
                        'SUMMARY_CONDITION', 'SUMMARY_SOAP',
                        'SUMMARY_CLINICAL_OBSERVATION')
                      AND migration_status = 'ACTIVE'
                    """,
            nativeQuery = true)
    int quarantineAmbiguousLegacySummarySources();

    @Query(
            value = """
                    SELECT pg_try_advisory_xact_lock(
                        hashtextextended(:lockKey, 0))
                    """,
            nativeQuery = true)
    boolean tryAcquireSummaryReplayLock(@Param("lockKey") String lockKey);

    /** Serializes delete-and-replace for one patient/source identity. */
    @Query(
            value = """
                    SELECT pg_advisory_xact_lock(hashtextextended(
                        CONCAT(:patientId, ':', :sourceKind, ':', :sourceRecordId), 0))
                    """,
            nativeQuery = true)
    void acquireSourceReplacementLock(
            @Param("patientId") Long patientId,
            @Param("sourceKind") String sourceKind,
            @Param("sourceRecordId") String sourceRecordId);

    /**
     * Oldest chunks missing embeddings across all sources (Task 4.4 backfill worker).
     */
    @Query(
            value = """
                    SELECT id, patient_id, record_type, source_record_id, chunk_text,
                           chunk_metadata, indexed_at, consent_scope, source_kind,
                           citation_replay_after, citation_replay_attempts,
                           citation_replay_claimed_until, citation_replay_claim_token,
                           migration_status
                    FROM retrieval_index_chunk
                    WHERE embedding IS NULL
                      AND migration_status = 'ACTIVE'
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
                      AND migration_status = 'ACTIVE'
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
                           chunk_metadata, indexed_at, consent_scope, source_kind,
                           citation_replay_after, citation_replay_attempts,
                           citation_replay_claimed_until, citation_replay_claim_token,
                           migration_status
                    FROM retrieval_index_chunk
                    WHERE patient_id = :patientId
                      AND migration_status = 'ACTIVE'
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
                           chunk_metadata, indexed_at, consent_scope, source_kind,
                           citation_replay_after, citation_replay_attempts,
                           citation_replay_claimed_until, citation_replay_claim_token,
                           migration_status
                    FROM retrieval_index_chunk
                    WHERE patient_id = :patientId
                      AND migration_status = 'ACTIVE'
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
