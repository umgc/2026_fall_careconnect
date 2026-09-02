package com.careconnect.service.ai.retrieval;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.model.retrieval.RetrievalIndexSchema;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import com.careconnect.service.ai.embedding.EmbeddingVectorFormat;
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
 * Patient-scoped pgvector cosine similarity search over {@code retrieval_index_chunk}
 * (Task 5.1 vector leg).
 *
 * <p>Query embeddings must use the same Titan model / dimension as index-time writes
 * ({@link RetrievalIndexSchema#EMBEDDING_DIMENSION}).
 */
@Service
public class VectorSimilaritySearchService {

    private static final Logger log = LoggerFactory.getLogger(VectorSimilaritySearchService.class);

    private static final int DEFAULT_LIMIT = 20;
    private static final int MAX_LIMIT = 100;

    private final RetrievalIndexChunkRepository chunkRepository;

    public VectorSimilaritySearchService(final RetrievalIndexChunkRepository chunkRepository) {
        this.chunkRepository = chunkRepository;
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

    private static int clampLimit(final int limit) {
        if (limit <= 0) {
            return DEFAULT_LIMIT;
        }
        return Math.min(limit, MAX_LIMIT);
    }

    /**
     * Runs cosine-distance ranking for a single patient.
     *
     * @param patientId      mandatory RBAC patient scope key
     * @param queryEmbedding Titan embedding floats (1536-d)
     * @param limit          max rows (clamped to 1..100); default 20 when {@code <= 0}
     */
    public List<RetrievalIndexChunk> search(
            final Long patientId, final float[] queryEmbedding, final int limit) {
        return search(patientId, queryEmbedding, null, limit);
    }

    /**
     * Same as {@link #search(Long, float[], int)} with an optional record-type filter
     * applied in SQL before {@code LIMIT}.
     */
    public List<RetrievalIndexChunk> search(
            final Long patientId,
            final float[] queryEmbedding,
            final Set<String> allowedRecordTypes,
            final int limit) {
        if (patientId == null) {
            log.warn("VectorSimilaritySearchService: refusing search without patientId");
            return Collections.emptyList();
        }
        if (queryEmbedding == null || queryEmbedding.length == 0) {
            return Collections.emptyList();
        }

        final String literal;
        try {
            literal = EmbeddingVectorFormat.toPgVectorLiteral(queryEmbedding);
        } catch (final IllegalArgumentException ex) {
            log.warn("VectorSimilaritySearchService: invalid query embedding: {}", ex.getMessage());
            return Collections.emptyList();
        }

        final int effectiveLimit = clampLimit(limit);
        final Set<String> allowed = normalizeRecordTypes(allowedRecordTypes);
        if (allowed.isEmpty()) {
            return chunkRepository.searchByPatientIdVector(patientId, literal, effectiveLimit);
        }
        return chunkRepository.searchByPatientIdVectorAndRecordTypes(
                patientId, literal, allowed, effectiveLimit);
    }
}
