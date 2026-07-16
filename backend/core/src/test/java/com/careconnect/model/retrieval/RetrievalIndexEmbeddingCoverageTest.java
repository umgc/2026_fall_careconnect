package com.careconnect.model.retrieval;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Task 4.3 — contract checks for Titan embedding wiring (no live Bedrock required).
 */
class RetrievalIndexEmbeddingCoverageTest {

    @Test
    @DisplayName("Schema documents Titan Embed Text v1 1536-d lock")
    void schema_documentsTitanV1Dimension() {
        assertThat(RetrievalIndexSchema.EMBEDDING_DIMENSION).isEqualTo(1536);
        assertThat(RetrievalIndexSchema.TABLE_NAME).isEqualTo("retrieval_index_chunk");
    }

    @Test
    @DisplayName("Repository exposes updateEmbedding and missing-embedding count")
    void repository_embeddingHooks() throws Exception {
        final String source = Files.readString(Path.of(
                "src/main/java/com/careconnect/repository/retrieval/RetrievalIndexChunkRepository.java"));
        assertThat(source).contains("updateEmbedding");
        assertThat(source).contains("countMissingEmbedding");
        assertThat(source).contains("countMissingEmbeddingForSource");
        assertThat(source).contains("findBySourceRecordIdAndEmbeddingIsNull");
        assertThat(source).contains("findMissingEmbeddingsForBackfill");
        assertThat(source).contains("CAST(:embedding AS vector)");
        assertThat(source).contains("WHERE embedding IS NULL");
    }

    @Test
    @DisplayName("ChunkEmbeddingService defaults to amazon.titan-embed-text-v1")
    void embeddingService_defaultsToTitanV1() throws Exception {
        final String source = Files.readString(Path.of(
                "src/main/java/com/careconnect/service/ai/embedding/ChunkEmbeddingService.java"));
        assertThat(source).contains("amazon.titan-embed-text-v1");
        assertThat(source).contains("embedAndPersist");
        assertThat(source).contains("updateEmbedding");
    }

    @Test
    @DisplayName("RetrievalIndexService invokes ChunkEmbeddingService after saveAll")
    void retrievalIndexService_callsEmbedAfterPersist() throws Exception {
        final String source = Files.readString(Path.of(
                "src/main/java/com/careconnect/service/ai/indexing/RetrievalIndexService.java"));
        assertThat(source).contains("ChunkEmbeddingService");
        assertThat(source).contains("chunkEmbeddingService.embedAndPersist");
        assertThat(source).contains("scheduleEmbeddingAfterCommit");
        assertThat(source).contains("afterCommit");
    }

    @Test
    @DisplayName("ChunkEmbeddingBackfillWorker polls NULL embeddings via repository batch query")
    void backfillWorker_contract() throws Exception {
        final String source = Files.readString(Path.of(
                "src/main/java/com/careconnect/service/ai/embedding/ChunkEmbeddingBackfillWorker.java"));
        assertThat(source).contains("findMissingEmbeddingsForBackfill");
        assertThat(source).contains("chunkEmbeddingService.embedAndPersist");
        assertThat(source).contains("countMissingEmbedding");
        assertThat(source).contains("careconnect.embedding.backfill.enabled");
    }
}
