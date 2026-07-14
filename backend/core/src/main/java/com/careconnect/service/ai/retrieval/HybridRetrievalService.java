package com.careconnect.service.ai.retrieval;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import java.util.Collections;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * Hybrid retrieval service for Ask AI (Task 4.1 / FR-AI-2).
 *
 * <p>Upgraded in Task 4.3 to use {@link FullTextSearchService} (PostgreSQL
 * {@code plainto_tsquery} FTS ranked by {@code ts_rank_cd}) instead of
 * in-memory keyword filtering.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class HybridRetrievalService {

    private static final int DEFAULT_TOP_K = 10;

    private final RetrievalIndexChunkRepository retrievalIndexChunkRepository;
    private final FullTextSearchService fullTextSearchService;

    public List<RetrievalIndexChunk> retrieve(
            final String query,
            final RetrievalScope scope,
            final int topK) {

        if (query == null || query.isBlank()) {
            log.warn("Empty query received for retrieval — returning empty results");
            return Collections.emptyList();
        }

        if (scope == null || scope.allowedPatientIds().isEmpty()) {
            log.warn("No allowed patient IDs in scope — returning empty results");
            return Collections.emptyList();
        }

        Long patientId = scope.allowedPatientIds().iterator().next();
        log.info("Hybrid retrieval for patient {} query length {}", patientId, query.length());

        Set<String> allowedTypes = null;
        if (scope.allowedSourceTypes() != null && !scope.allowedSourceTypes().isEmpty()) {
            allowedTypes = scope.allowedSourceTypes().stream()
                    .map(RetrievalRecordType::name)
                    .collect(Collectors.toSet());
            if (scope.excludedSourceTypes() != null) {
                scope.excludedSourceTypes().stream()
                        .map(RetrievalRecordType::name)
                        .forEach(allowedTypes::remove);
            }
        }

        int effectiveTopK = topK > 0 ? topK : DEFAULT_TOP_K;

        List<RetrievalIndexChunk> matched = fullTextSearchService.search(
                patientId, query, allowedTypes, effectiveTopK);

        log.info("Returning {} matched chunks after FTS for patient {}", matched.size(), patientId);
        return matched;
    }

    public List<RetrievalIndexChunk> retrieve(
            final String query,
            final RetrievalScope scope) {
        return retrieve(query, scope, DEFAULT_TOP_K);
    }
}