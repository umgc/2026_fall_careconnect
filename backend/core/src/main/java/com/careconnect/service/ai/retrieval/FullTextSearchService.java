package com.careconnect.service.ai.retrieval;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.model.retrieval.RetrievalIndexSchema;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * Patient-scoped PostgreSQL full-text search over {@code retrieval_index_chunk}
 * (Task 4.2).
 *
 * <p>{@code search_vector} is maintained by the DB trigger on {@code chunk_text}
 * writes from {@link com.careconnect.service.ai.indexing.RetrievalIndexService}.
 * This service is the keyword leg that {@code HybridRetrievalService} (Task 5.1)
 * will compose with vector similarity (Task 4.3).
 */
@Service
public class FullTextSearchService {

    private static final Logger log = LoggerFactory.getLogger(FullTextSearchService.class);

    private static final int DEFAULT_LIMIT = 20;
    private static final int MAX_LIMIT = 100;

    private final RetrievalIndexChunkRepository chunkRepository;

    public FullTextSearchService(final RetrievalIndexChunkRepository chunkRepository) {
        this.chunkRepository = chunkRepository;
    }

    /**
     * Runs English {@code plainto_tsquery} FTS for a single patient, ranked by
     * {@code ts_rank_cd}. Always scopes by {@code patient_id} (FR-AI-1).
     *
     * @param patientId mandatory RBAC patient scope key
     * @param query     natural-language keyword query
     * @param limit     max rows (clamped to 1..100); default 20 when {@code <= 0}
     * @return ranked matching chunks; empty when query/patient invalid or no hits
     */
    public List<RetrievalIndexChunk> search(
            final Long patientId, final String query, final int limit) {
        return search(patientId, query, null, limit);
    }

    /**
     * Same as {@link #search(Long, String, int)} with an optional record-type filter
     * applied in SQL before {@code LIMIT} (allowed {@link RetrievalRecordType} names).
     *
     * @param allowedRecordTypes when null or empty, all types for the patient are eligible
     */
    public List<RetrievalIndexChunk> search(
            final Long patientId,
            final String query,
            final Set<String> allowedRecordTypes,
            final int limit) {
        if (patientId == null) {
            log.warn("FullTextSearchService: refusing search without patientId");
            return Collections.emptyList();
        }
        final String normalized = normalizeQuery(query);
        if (normalized == null) {
            return Collections.emptyList();
        }

        final int effectiveLimit = clampLimit(limit);
        final Set<String> allowed = normalizeRecordTypes(allowedRecordTypes);
        if (allowed.isEmpty()) {
            return chunkRepository.searchByPatientIdFullText(
                    patientId, normalized, effectiveLimit);
        }
        return chunkRepository.searchByPatientIdFullTextAndRecordTypes(
                patientId, normalized, allowed, effectiveLimit);
    }

    /**
     * @return count of chunks still missing {@code search_vector} (should be 0 after
     *         Task 4.2 backfill + trigger); useful for ops / readiness checks
     */
    public long countChunksMissingSearchVector() {
        return chunkRepository.countMissingSearchVector();
    }

    private static Set<String> normalizeRecordTypes(final Set<String> allowedRecordTypes) {
        if (allowedRecordTypes == null || allowedRecordTypes.isEmpty()) {
            return Set.of();
        }
        return allowedRecordTypes.stream()
                .filter(Objects::nonNull)
                .map(t -> t.trim().toUpperCase(Locale.ROOT))
                .filter(t -> !t.isEmpty())
                .collect(Collectors.toUnmodifiableSet());
    }

    private static String normalizeQuery(final String query) {
        if (query == null || query.isBlank()) {
            return null;
        }
        final String trimmed = query.trim();
        if (trimmed.length() > RetrievalIndexSchema.FTS_QUERY_MAX_LENGTH) {
            return trimmed.substring(0, RetrievalIndexSchema.FTS_QUERY_MAX_LENGTH);
        }
        return trimmed;
    }

    private static int clampLimit(final int limit) {
        if (limit <= 0) {
            return DEFAULT_LIMIT;
        }
        return Math.min(limit, MAX_LIMIT);
    }
}
