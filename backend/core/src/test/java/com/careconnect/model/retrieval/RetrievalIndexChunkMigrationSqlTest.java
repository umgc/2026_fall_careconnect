package com.careconnect.model.retrieval;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

/** Task 1.5 / 1.6 — Flyway migration contract tests (no live PostgreSQL required). */
class RetrievalIndexChunkMigrationSqlTest {

    @Test
    @DisplayName("pgvector extension migration enables vector type")
    void pgvectorExtensionMigration() throws Exception {
        String sql = readMigration("V2607071920__enable_pgvector_extension.sql");

        assertThat(sql).contains("CREATE EXTENSION IF NOT EXISTS vector");
    }

    @Test
    @DisplayName("retrieval_index_chunk migration defines core columns and indexes")
    void retrievalIndexChunkTableMigration() throws Exception {
        String sql = readMigration("V2607071921__create_retrieval_index_chunk.sql");

        assertThat(sql).contains("CREATE TABLE IF NOT EXISTS retrieval_index_chunk");
        assertThat(sql).contains("patient_id        BIGINT        NOT NULL");
        assertThat(sql).contains("record_type       VARCHAR(40)   NOT NULL");
        assertThat(sql).contains("chunk_text        TEXT          NOT NULL");
        assertThat(sql).contains("search_vector     TSVECTOR");
        assertThat(sql).contains("embedding         vector(1536)");
        assertThat(sql).contains("idx_retrieval_chunk_patient_id");
        assertThat(sql).contains("idx_retrieval_chunk_fts");
        assertThat(sql).contains("USING GIN (search_vector)");
        assertThat(sql).contains("idx_retrieval_chunk_embedding");
        assertThat(sql).contains("vector_cosine_ops");
    }

    @Test
    @DisplayName("retrieval_index_chunk migration maintains FTS search_vector via trigger")
    void retrievalIndexChunkFtsTriggerMigration() throws Exception {
        String sql = readMigration("V2607071921__create_retrieval_index_chunk.sql");

        assertThat(sql).contains("retrieval_index_chunk_search_vector_trigger");
        assertThat(sql).contains("to_tsvector('english'");
        assertThat(sql).contains("trg_retrieval_index_chunk_search_vector");
    }

    private static String readMigration(String filename) throws Exception {
        try (var stream = RetrievalIndexChunkMigrationSqlTest.class.getClassLoader()
                .getResourceAsStream("db/migration/" + filename)) {
            assertThat(stream).as("migration file on classpath: %s", filename).isNotNull();
            return new String(stream.readAllBytes(), StandardCharsets.UTF_8);
        }
    }
}
