package com.careconnect.service.ai.retrieval;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.model.retrieval.RetrievalIndexSchema;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import com.careconnect.security.Role;
import com.careconnect.service.ai.embedding.ChunkEmbeddingService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.EnumSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * Task 5.1 — hybrid Ask AI retrieval merge layer.
 *
 * <p>Pipeline: resolve patient + {@link RetrievalScope} → optional intent plan (Task 5.2) →
 * FTS and vector arms (+ structured medication timeline arm) → Reciprocal Rank Fusion →
 * final top-k {@link RankedChunk}s with citation refs {@code C1..Cn}.
 *
 * <p>When query embedding fails or embeddings are disabled, degrades to FTS-only with an
 * explicit {@link HybridRetrievalResult#vectorDegraded()} flag (not a silent skip).
 */
@Service
public class HybridRetrievalService {

    private static final Logger log = LoggerFactory.getLogger(HybridRetrievalService.class);
    private static final int MAX_ARM_FETCH = 100;
    private static final double STRUCTURED_ARM_WEIGHT = 1.5d;
    private static final Set<RetrievalRecordType> MEDICATION_TIMELINE_TYPES = EnumSet.of(
            RetrievalRecordType.MEDICATION_TIMELINE_EVENT,
            RetrievalRecordType.SUMMARY_CARE_INSTRUCTION,
            RetrievalRecordType.MEDICATION,
            RetrievalRecordType.CALL_SUMMARY,
            RetrievalRecordType.VISIT_SUMMARY,
            RetrievalRecordType.TRANSCRIPT_SEGMENT);

    private final FullTextSearchService fullTextSearchService;
    private final VectorSimilaritySearchService vectorSimilaritySearchService;
    private final ChunkEmbeddingService chunkEmbeddingService;
    private final RetrievalIndexChunkRepository chunkRepository;

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
            final RetrievalIndexChunkRepository chunkRepository,
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
        this.chunkRepository = chunkRepository;
        this.ftsTopK = Math.max(1, ftsTopK);
        this.vectorTopK = Math.max(1, vectorTopK);
        this.finalTopK = Math.max(1, finalTopK);
        this.rrfK = Math.max(1, rrfK);
        this.visibilityOverfetchFactor = Math.max(1, visibilityOverfetchFactor);
        this.maxChunksPerSource = Math.max(1, maxChunksPerSource);
    }

    public HybridRetrievalResult search(
            final RetrievalScope scope, final Long patientId, final String query) {
        return search(scope, patientId, query, RetrievalPlan.general());
    }

    /**
     * Runs scoped hybrid retrieval for one patient, optionally narrowed by {@link RetrievalPlan}.
     */
    public HybridRetrievalResult search(
            final RetrievalScope scope,
            final Long patientId,
            final String query,
            final RetrievalPlan plan) {
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

        Set<String> allowedTypes = toRecordTypeNames(scope.allowedSourceTypes());
        if (allowedTypes.isEmpty()) {
            log.warn("HybridRetrievalService: empty allowedSourceTypes for patientId={}", patientId);
            return HybridRetrievalResult.empty(normalizedQuery);
        }
        final RetrievalPlan effectivePlan = plan == null ? RetrievalPlan.general() : plan;
        if (effectivePlan.isMedicationTimeline()) {
            allowedTypes = narrowForMedicationTimeline(allowedTypes);
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

        final List<RetrievalIndexChunk> structuredHits = effectivePlan.isMedicationTimeline()
                ? structuredMedicationTimelineHits(
                        patientId, effectivePlan.medicationNameHint(), scope.visibilityFilter())
                : List.of();

        final List<ReciprocalRankFusion.MergedHit> merged =
                ReciprocalRankFusion.merge(
                        ftsHits,
                        vectorHits,
                        structuredHits,
                        rrfK,
                        finalTopK,
                        maxChunksPerSource,
                        STRUCTURED_ARM_WEIGHT);
        final List<RankedChunk> ranked = toRankedChunks(merged);

        log.info(
                "Hybrid retrieval patientId={} intent={} fts={} vector={} structured={} final={} degraded={}",
                patientId,
                effectivePlan.intent(),
                ftsHits.size(),
                vectorHits.size(),
                structuredHits.size(),
                ranked.size(),
                vectorDegraded);

        return new HybridRetrievalResult(
                ranked, normalizedQuery, vectorDegraded, ftsHits.size(), vectorHits.size());
    }

    private List<RetrievalIndexChunk> structuredMedicationTimelineHits(
            final Long patientId,
            final String medicationNameHint,
            final CaregiverVisibilityFilter filter) {
        // Over-fetch slightly so visibility filtering still leaves enough candidates.
        final int fetchLimit = visibilityAwareLimit(MAX_ARM_FETCH, filter);
        final List<RetrievalIndexChunk> raw =
                chunkRepository.findByPatientIdAndRecordTypeOrderByIndexedAtDesc(
                        patientId,
                        RetrievalRecordType.MEDICATION_TIMELINE_EVENT.name(),
                        fetchLimit);
        final List<RetrievalIndexChunk> visible = applyVisibility(raw, filter);
        if (medicationNameHint == null || medicationNameHint.isBlank()) {
            return visible.size() > MAX_ARM_FETCH
                    ? List.copyOf(visible.subList(0, MAX_ARM_FETCH))
                    : visible;
        }
        final String hint = medicationNameHint.toLowerCase(Locale.ROOT);
        // Prefer empty structured arm over boosting unrelated meds at 1.5× when the
        // named drug is absent from the index.
        return visible.stream()
                .filter(chunk -> metadataContainsNormalizedName(chunk, hint))
                .limit(MAX_ARM_FETCH)
                .toList();
    }

    private static boolean metadataContainsNormalizedName(
            final RetrievalIndexChunk chunk, final String hint) {
        if (chunk == null || chunk.getChunkMetadata() == null || hint == null || hint.isBlank()) {
            return false;
        }
        final String meta = chunk.getChunkMetadata().toLowerCase(Locale.ROOT);
        // Exact JSON field match only — avoid short-token substring false positives.
        return meta.contains("\"medicationnamenormalized\":\"" + hint + "\"");
    }

    private static Set<String> narrowForMedicationTimeline(final Set<String> allowedTypes) {
        final Set<String> narrowed = new LinkedHashSet<>();
        for (final RetrievalRecordType type : MEDICATION_TIMELINE_TYPES) {
            if (allowedTypes.contains(type.name())) {
                narrowed.add(type.name());
            }
        }
        return narrowed.isEmpty() ? allowedTypes : Set.copyOf(narrowed);
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
