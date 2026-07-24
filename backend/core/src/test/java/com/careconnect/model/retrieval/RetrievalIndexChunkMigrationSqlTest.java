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
        assertThat(sql).contains("embedding         vector(" + RetrievalIndexSchema.EMBEDDING_DIMENSION + ")");
        assertThat(sql).contains("fk_retrieval_chunk_patient");
        assertThat(sql).contains("REFERENCES patient (id)");
        assertThat(sql).contains("idx_retrieval_chunk_patient_id");
        assertThat(sql).contains("idx_retrieval_chunk_fts");
        assertThat(sql).contains("USING GIN (search_vector)");
        assertThat(sql).contains("idx_retrieval_chunk_embedding");
        assertThat(sql).contains("vector_cosine_ops");
    }

    @Test
    @DisplayName("embedding dimension in SQL matches RetrievalIndexSchema")
    void embeddingDimensionMatchesSchema() throws Exception {
        String sql = readMigration("V2607071921__create_retrieval_index_chunk.sql");

        assertThat(sql).contains("vector(" + RetrievalIndexSchema.EMBEDDING_DIMENSION + ")");
        assertThat(RetrievalIndexSchema.EMBEDDING_DIMENSION).isEqualTo(1536);
    }

    @Test
    @DisplayName("retrieval_index_chunk migration maintains FTS search_vector via trigger")
    void retrievalIndexChunkFtsTriggerMigration() throws Exception {
        String sql = readMigration("V2607071921__create_retrieval_index_chunk.sql");

        assertThat(sql).contains("retrieval_index_chunk_search_vector_trigger");
        assertThat(sql).contains("to_tsvector('english'");
        assertThat(sql).contains("trg_retrieval_index_chunk_search_vector");
        assertThat(sql).contains("BEFORE INSERT OR UPDATE OF chunk_text");
    }

    @Test
    @DisplayName("Task 4.2 backfill migration is on the Flyway classpath")
    void task42BackfillMigrationPresent() throws Exception {
        String sql = readMigration("V2607121930__backfill_retrieval_index_chunk_search_vector.sql");

        assertThat(sql).contains("WHERE search_vector IS NULL");
        assertThat(sql).contains("to_tsvector('english'");
        assertThat(sql).doesNotContain("SELECT * FROM");
    }

    @Test
    @DisplayName("claimed_at lease column migration is on the Flyway classpath")
    void claimedAtLeaseMigrationPresent() throws Exception {
        String sql = readMigration("V2607122000__add_indexing_outbox_claimed_at.sql");

        assertThat(sql).contains("ADD COLUMN IF NOT EXISTS claimed_at");
        assertThat(sql).contains("idx_indexing_outbox_claimable");
    }

    @Test
    @DisplayName("replay fencing migration repairs partial schemas and quarantines untyped rows")
    void replayFencingMigrationIsAdditiveAndFailClosed() throws Exception {
        String sql = readMigration("V2607182330__fence_retrieval_replay_claims.sql");

        assertThat(sql).contains("ADD COLUMN IF NOT EXISTS search_vector TSVECTOR");
        assertThat(sql).contains("ADD COLUMN IF NOT EXISTS embedding vector(1536)");
        assertThat(sql).contains("ADD COLUMN IF NOT EXISTS citation_replay_claim_token UUID");
        assertThat(sql).contains("pg_constraint");
        assertThat(sql).contains("fk_call_participants_session");
        assertThat(sql).contains("migration_status = 'QUARANTINED'");
        assertThat(sql).contains("WHERE source_kind IS NULL");
    }

    @Test
    @DisplayName("citation replay ownership is source-level and fenced")
    void sourceLevelReplayMigrationDefinesRecoveryAndInvariants() throws Exception {
        String sql = readMigration(
                "V2607190100__create_summary_citation_replay_source.sql");

        assertThat(sql).contains("CREATE TABLE IF NOT EXISTS summary_citation_replay_source");
        assertThat(sql).contains("PRIMARY KEY (patient_id, source_kind, source_record_id)");
        assertThat(sql).contains("ck_summary_replay_lease_token");
        assertThat(sql).contains("ck_retrieval_replay_lease_token");
        assertThat(sql).contains("idx_summary_replay_claim_fair");
        assertThat(sql).contains("JOIN call_summaries cs");
        assertThat(sql).contains("'call-summary:' || cs.id");
        assertThat(sql).doesNotContain("DO $$");
        assertThat(sql).contains("DROP CONSTRAINT IF EXISTS retrieval_index_chunk_pkey");
        assertThat(sql).contains("DROP CONSTRAINT IF EXISTS fk_summary_replay_patient");
        assertThat(sql).contains("FOREIGN KEY (patient_id) REFERENCES patient(id) NOT VALID");
        assertThat(sql).doesNotContain(
                "SET source_kind = 'CALL_SUMMARY',\n    migration_status = 'ACTIVE'");
    }

    private static String readMigration(String filename) throws Exception {
        try (var stream = RetrievalIndexChunkMigrationSqlTest.class.getClassLoader()
                .getResourceAsStream("db/migration/" + filename)) {
            assertThat(stream).as("migration file on classpath: %s", filename).isNotNull();
            return new String(stream.readAllBytes(), StandardCharsets.UTF_8);
        }
    }
}
