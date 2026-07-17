package com.careconnect.model.retrieval;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Task 4.2 — contract tests for FTS trigger, backfill migration, repository query SQL,
 * and SchemaPatchRunner parity (no live PostgreSQL required).
 */
class RetrievalIndexFtsCoverageTest {

    @Test
    @DisplayName("V2607071921 trigger maintains search_vector on INSERT/UPDATE of chunk_text")
    void precursorMigration_hasEnglishTrigger() throws Exception {
        final String sql = readClasspath("db/migration/V2607071921__create_retrieval_index_chunk.sql");

        assertThat(sql).contains("CREATE OR REPLACE FUNCTION retrieval_index_chunk_search_vector_trigger()");
        assertThat(sql).contains("to_tsvector('english'");
        assertThat(sql).contains("BEFORE INSERT OR UPDATE OF chunk_text");
        assertThat(sql).contains("USING GIN (search_vector)");
        assertThat(sql).contains("FullTextSearchService");
    }

    @Test
    @DisplayName("V2607121930 backfills NULL search_vector and reaffirms trigger")
    void backfillMigration_reaffirmsTriggerAndBackfills() throws Exception {
        final String sql = readClasspath(
                "db/migration/V2607121930__backfill_retrieval_index_chunk_search_vector.sql");

        assertThat(sql).contains("CREATE OR REPLACE FUNCTION retrieval_index_chunk_search_vector_trigger()");
        assertThat(sql).contains("BEFORE INSERT OR UPDATE OF chunk_text");
        assertThat(sql).contains("UPDATE retrieval_index_chunk");
        assertThat(sql).contains("WHERE search_vector IS NULL");
        assertThat(sql).contains("to_tsvector('english'");
        assertThat(sql).contains("searchByPatientIdFullText");
    }

    @Test
    @DisplayName("SchemaPatchRunner applies Task 4.2 search_vector backfill")
    void schemaPatchRunner_includesBackfill() throws Exception {
        final String source = Files.readString(Path.of(
                "src/main/java/com/careconnect/config/SchemaPatchRunner.java"));

        assertThat(source).contains("V2607121930 – backfill retrieval_index_chunk search_vector (Task 4.2)");
        assertThat(source).contains("V2607122000 – indexing_outbox claimed_at lease column");
        assertThat(source).contains("WHERE search_vector IS NULL");
        assertThat(source).contains("to_tsvector('english'");
        assertThat(source).contains("trg_retrieval_index_chunk_search_vector");
        assertThat(source).contains("claimed_at TIMESTAMPTZ");
    }

    @Test
    @DisplayName("Repository FTS query is patient-scoped and uses plainto_tsquery + ts_rank_cd")
    void repository_ftsQueryContract() throws Exception {
        final String source = Files.readString(Path.of(
                "src/main/java/com/careconnect/repository/retrieval/RetrievalIndexChunkRepository.java"));

        assertThat(source).contains("searchByPatientIdFullText");
        assertThat(source).contains("searchByPatientIdFullTextAndRecordTypes");
        assertThat(source).contains("patient_id = :patientId");
        assertThat(source).contains("plainto_tsquery('english', :query)");
        assertThat(source).contains("ts_rank_cd(search_vector");
        assertThat(source).contains("search_vector @@ plainto_tsquery");
        assertThat(source).contains("record_type IN (:recordTypes)");
        assertThat(source).contains("countMissingSearchVector");
        assertThat(source).contains("countMissingEmbedding");
        // Must not SELECT * (entity omits search_vector / embedding).
        assertThat(source).doesNotContain("SELECT * FROM retrieval_index_chunk");
    }

    @Test
    @DisplayName("Schema constants document english FTS config used by trigger and queries")
    void schemaConstants_ftsConfig() {
        assertThat(RetrievalIndexSchema.FTS_TEXT_SEARCH_CONFIG).isEqualTo("english");
        assertThat(RetrievalIndexSchema.FTS_QUERY_MAX_LENGTH).isEqualTo(500);
    }

    private static String readClasspath(final String path) throws Exception {
        try (var stream = RetrievalIndexFtsCoverageTest.class.getClassLoader().getResourceAsStream(path)) {
            assertThat(stream).as("classpath resource %s", path).isNotNull();
            return new String(stream.readAllBytes(), StandardCharsets.UTF_8);
        }
    }
}
