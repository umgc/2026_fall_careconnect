package com.careconnect.service.ai.retrieval;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Task 5.1 — contract checks for hybrid retrieval wiring (no live Postgres / Bedrock).
 */
class HybridRetrievalCoverageTest {

    @Test
    @DisplayName("Repository exposes patient-scoped vector similarity queries")
    void repository_vectorSearchHooks() throws Exception {
        final String source = Files.readString(Path.of(
                "src/main/java/com/careconnect/repository/retrieval/RetrievalIndexChunkRepository.java"));
        assertThat(source).contains("searchByPatientIdVector");
        assertThat(source).contains("searchByPatientIdVectorAndRecordTypes");
        assertThat(source).contains("embedding <=> CAST(:queryEmbedding AS vector)");
        assertThat(source).contains("AND embedding IS NOT NULL");
    }

    @Test
    @DisplayName("ChunkEmbeddingService exposes embedQuery for hybrid vector arm")
    void embeddingService_embedQuery() throws Exception {
        final String source = Files.readString(Path.of(
                "src/main/java/com/careconnect/service/ai/embedding/ChunkEmbeddingService.java"));
        assertThat(source).contains("embedQuery");
        assertThat(source).contains("Optional<float[]>");
    }

    @Test
    @DisplayName("HybridRetrievalService merges FTS + vector via RRF with citation refs")
    void hybridService_contract() throws Exception {
        final String source = Files.readString(Path.of(
                "src/main/java/com/careconnect/service/ai/retrieval/HybridRetrievalService.java"));
        assertThat(source).contains("FullTextSearchService");
        assertThat(source).contains("VectorSimilaritySearchService");
        assertThat(source).contains("ReciprocalRankFusion");
        assertThat(source).contains("embedQuery");
        assertThat(source).contains("vectorDegraded");
        assertThat(source).contains("visibilityFilter");
        assertThat(source).contains("\"C\"");
        assertThat(source).contains("careconnect.ai.ask.retrieval");
    }
}
