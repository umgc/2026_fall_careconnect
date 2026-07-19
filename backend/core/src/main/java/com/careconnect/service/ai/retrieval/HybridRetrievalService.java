package com.careconnect.service.ai.retrieval;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.model.retrieval.RetrievalIndexSchema;
import com.careconnect.security.Role;
import com.careconnect.service.ai.embedding.ChunkEmbeddingService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * Task 5.1 — hybrid Ask AI retrieval merge layer.
 *
 * <p>Pipeline: resolve patient + {@link RetrievalScope} → FTS and vector arms →
 * Reciprocal Rank Fusion → final top-k {@link RankedChunk}s with citation refs {@code C1..Cn}.
 *
 * <p>When query embedding fails or embeddings are disabled, degrades to FTS-only with an
 * explicit {@link HybridRetrievalResult#vectorDegraded()} flag (not a silent skip).
 */
@Service
public class HybridRetrievalService {

    private static final Logger log = LoggerFactory.getLogger(HybridRetrievalService.class);
    private static final int MAX_ARM_FETCH = 100;

    private final FullTextSearchService fullTextSearchService;
    private final VectorSimilaritySearchService vectorSimilaritySearchService;
    private final ChunkEmbeddingService chunkEmbeddingService;

    private final int ftsTopK;
    private final int vectorTopK;
    private final int finalTopK;
    private final int rrfK;
    private final int visibilityOverfetchFactor;
    private final int maxChunksPerSource;

    public HybridRetrievalService(
            final FullTextSearchService fullTextSearchService,
            final VectorSimilaritySearchService vectorSimilaritySearchService,
            final ChunkEmbeddingService chunkEmbeddingService,
            @Value("${careconnect.ai.ask.retrieval.fts-top-k:20}") final int ftsTopK,
            @Value("${careconnect.ai.ask.retrieval.vector-top-k:20}") final int vectorTopK,
            @Value("${careconnect.ai.ask.retrieval.final-top-k:10}") final int finalTopK,
            @Value("${careconnect.ai.ask.retrieval.rrf-k:60}") final int rrfK,
            @Value("${careconnect.ai.ask.retrieval.visibility-overfetch-factor:3}")
                    final int visibilityOverfetchFactor,
            @Value("${careconnect.ai.ask.retrieval.max-chunks-per-source:2}")
                    final int maxChunksPerSource) {
        this.fullTextSearchService = fullTextSearchService;
        this.vectorSimilaritySearchService = vectorSimilaritySearchService;
        this.chunkEmbeddingService = chunkEmbeddingService;
        this.ftsTopK = Math.max(1, ftsTopK);
        this.vectorTopK = Math.max(1, vectorTopK);
        this.finalTopK = Math.max(1, finalTopK);
        this.rrfK = Math.max(1, rrfK);
        this.visibilityOverfetchFactor = Math.max(1, visibilityOverfetchFactor);
        this.maxChunksPerSource = Math.max(1, maxChunksPerSource);
    }

    /**
     * Runs scoped hybrid retrieval for one patient.
     *
     * @param scope     RBAC scope from {@link RetrievalScopeService} (patient + source types + visibility)
     * @param patientId target patient; must be in {@link RetrievalScope#allowedPatientIds()}
     * @param query     natural-language question
     */
    public HybridRetrievalResult search(
            final RetrievalScope scope, final Long patientId, final String query) {
        final String normalizedQuery = normalizeQuery(query);
        if (normalizedQuery == null) {
            return HybridRetrievalResult.empty(query == null ? "" : query);
        }
        if (scope == null || patientId == null) {
            log.warn("HybridRetrievalService: refusing search without scope/patientId");
            return HybridRetrievalResult.empty(normalizedQuery);
        }
        if (scope.allowedPatientIds() == null || !scope.allowedPatientIds().contains(patientId)) {
            log.warn(
                    "HybridRetrievalService: patientId={} not in allowedPatientIds for caller={}",
                    patientId,
                    scope.callerUserId());
            return HybridRetrievalResult.empty(normalizedQuery);
        }

        final Set<String> allowedTypes = toRecordTypeNames(scope.allowedSourceTypes());
        if (allowedTypes.isEmpty()) {
            log.warn("HybridRetrievalService: empty allowedSourceTypes for patientId={}", patientId);
            return HybridRetrievalResult.empty(normalizedQuery);
        }

        final int effectiveFtsTopK =
                visibilityAwareLimit(ftsTopK, scope.visibilityFilter());
        final int effectiveVectorTopK =
                visibilityAwareLimit(vectorTopK, scope.visibilityFilter());
        final List<RetrievalIndexChunk> ftsRaw = fullTextSearchService.search(
                patientId, normalizedQuery, allowedTypes, effectiveFtsTopK);
        final List<RetrievalIndexChunk> ftsHits = applyVisibility(ftsRaw, scope.visibilityFilter());

        boolean vectorDegraded = false;
        List<RetrievalIndexChunk> vectorHits = List.of();
        final Optional<float[]> queryEmbedding = chunkEmbeddingService.embedQuery(normalizedQuery);
        if (queryEmbedding.isEmpty()) {
            vectorDegraded = true;
            log.warn(
                    "HybridRetrievalService: vector arm degraded for patientId={} — FTS-only merge",
                    patientId);
        } else {
            final List<RetrievalIndexChunk> vectorRaw = vectorSimilaritySearchService.search(
                    patientId, queryEmbedding.get(), allowedTypes, effectiveVectorTopK);
            vectorHits = applyVisibility(vectorRaw, scope.visibilityFilter());
        }

        final List<ReciprocalRankFusion.MergedHit> merged =
                ReciprocalRankFusion.merge(
                        ftsHits, vectorHits, rrfK, finalTopK, maxChunksPerSource);
        final List<RankedChunk> ranked = toRankedChunks(merged);

        log.info(
                "Hybrid retrieval patientId={} fts={} vector={} final={} degraded={}",
                patientId,
                ftsHits.size(),
                vectorHits.size(),
                ranked.size(),
                vectorDegraded);

        return new HybridRetrievalResult(
                ranked, normalizedQuery, vectorDegraded, ftsHits.size(), vectorHits.size());
    }

    private static List<RankedChunk> toRankedChunks(
            final List<ReciprocalRankFusion.MergedHit> merged) {
        final List<RankedChunk> out = new ArrayList<>(merged.size());
        for (int i = 0; i < merged.size(); i++) {
            final ReciprocalRankFusion.MergedHit hit = merged.get(i);
            final RetrievalIndexChunk chunk = hit.chunk();
            out.add(new RankedChunk(
                    chunk.getId(),
                    chunk.getPatientId(),
                    chunk.resolveRecordTypeEnum().orElse(null),
                    chunk.getSourceKind(),
                    chunk.getSourceRecordId(),
                    chunk.getChunkText(),
                    chunk.getChunkMetadata(),
                    chunk.getConsentScope(),
                    hit.rrfScore(),
                    hit.ftsRank(),
                    hit.vectorRank(),
                    "C" + (i + 1)));
        }
        return List.copyOf(out);
    }

    private static List<RetrievalIndexChunk> applyVisibility(
            final List<RetrievalIndexChunk> chunks, final CaregiverVisibilityFilter filter) {
        if (chunks == null || chunks.isEmpty()) {
            return List.of();
        }
        if (filter == null) {
            return List.copyOf(chunks);
        }
        return chunks.stream()
                .filter(c -> c != null && filter.permits(c.getConsentScope()))
                .toList();
    }

    private int visibilityAwareLimit(
            final int configuredLimit, final CaregiverVisibilityFilter filter) {
        if (!requiresVisibilityFiltering(filter)) {
            return configuredLimit;
        }
        final long overfetch = (long) configuredLimit * visibilityOverfetchFactor;
        return (int) Math.min(MAX_ARM_FETCH, overfetch);
    }

    private static boolean requiresVisibilityFiltering(
            final CaregiverVisibilityFilter filter) {
        if (filter == null) {
            return false;
        }
        return filter.callerRole() != Role.ADMIN && filter.callerRole() != Role.PATIENT;
    }

    private static Set<String> toRecordTypeNames(final Set<RetrievalRecordType> types) {
        if (types == null || types.isEmpty()) {
            return Set.of();
        }
        return types.stream()
                .filter(Objects::nonNull)
                .map(Enum::name)
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
}
