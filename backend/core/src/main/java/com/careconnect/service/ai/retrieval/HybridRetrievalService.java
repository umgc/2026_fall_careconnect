package com.careconnect.service.ai.retrieval;

import com.careconnect.model.retrieval.RetrievalIndexChunk;
import com.careconnect.repository.retrieval.RetrievalIndexChunkRepository;
import java.util.Collections;
import java.util.List;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * Hybrid retrieval service for Ask AI (Task 4.1 / FR-AI-2).
 * Searches retrieval_index_chunk using keyword FTS filtering
 * scoped by RetrievalScope RBAC constraints.
 * pgvector semantic search will be added in Task 4.3 once
 * embedding pipeline is operational.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class HybridRetrievalService {

  private static final int DEFAULT_TOP_K = 10;

  private final RetrievalIndexChunkRepository retrievalIndexChunkRepository;

  /**
   * Retrieves ranked chunks for a patient query within the caller's RBAC scope.
   *
   * @param query the patient's natural-language question
   * @param scope the resolved RBAC scope from RetrievalScopeService
   * @param topK  maximum number of chunks to return
   * @return ranked list of matching RetrievalIndexChunk records
   */
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

    // Load all chunks for patient within allowed source types
    List<RetrievalIndexChunk> candidates = retrievalIndexChunkRepository
        .findByPatientId(patientId)
        .stream()
        .filter(chunk -> isAllowedSourceType(chunk, scope))
        .collect(Collectors.toList());

    log.info("Found {} candidate chunks before keyword filter", candidates.size());

    // Keyword filter — match query terms against chunk text
    String queryLower = query.toLowerCase();
    String[] terms = queryLower.split("\\s+");

    List<RetrievalIndexChunk> matched = candidates.stream()
        .filter(chunk -> matchesKeywords(chunk, terms))
        .limit(topK > 0 ? topK : DEFAULT_TOP_K)
        .collect(Collectors.toList());

    log.info("Returning {} matched chunks after keyword filter", matched.size());
    return matched;
  }

  /**
   * Retrieves chunks using default topK.
   *
   * @param query the patient's natural-language question
   * @param scope the resolved RBAC scope
   * @return ranked list of matching chunks
   */
  public List<RetrievalIndexChunk> retrieve(
      final String query,
      final RetrievalScope scope) {
    return retrieve(query, scope, DEFAULT_TOP_K);
  }

  /**
   * Checks if a chunk's record type is allowed by the scope.
   *
   * @param chunk the retrieval chunk
   * @param scope the RBAC scope
   * @return true if allowed
   */
  private boolean isAllowedSourceType(
      final RetrievalIndexChunk chunk,
      final RetrievalScope scope) {
    if (chunk.getRecordType() == null) {
      return false;
    }
    try {
      RetrievalRecordType recordType = RetrievalRecordType.valueOf(chunk.getRecordType());
      if (scope.excludedSourceTypes() != null
          && scope.excludedSourceTypes().contains(recordType)) {
        return false;
      }
      if (scope.allowedSourceTypes() != null
          && !scope.allowedSourceTypes().isEmpty()) {
        return scope.allowedSourceTypes().contains(recordType);
      }
      return true;
    } catch (IllegalArgumentException e) {
      log.warn("Unknown record type: {}", chunk.getRecordType());
      return false;
    }
  }

  /**
   * Checks if a chunk's text content matches any of the query terms.
   *
   * @param chunk the retrieval chunk
   * @param terms lowercase query terms
   * @return true if any term matches
   */
  private boolean matchesKeywords(
      final RetrievalIndexChunk chunk,
      final String[] terms) {
    if (chunk.getChunkText() == null || chunk.getChunkText().isBlank()) {
      return false;
    }
    String text = chunk.getChunkText().toLowerCase();
    for (String term : terms) {
      if (text.contains(term)) {
        return true;
      }
    }
    return false;
  }
}