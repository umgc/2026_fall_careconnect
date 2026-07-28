package com.careconnect.config;

import org.junit.jupiter.api.Test;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.ResultSet;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class SchemaPatchRunnerTest {

    @Test
    void normalizeIndexDefinition_acceptsPostgresCanonicalPredicateCasts() {
        final String requested = """
                CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_summary_replay_claim_fair
                ON summary_citation_replay_source
                (replay_after ASC NULLS FIRST, attempts ASC, patient_id,
                 source_kind, source_record_id)
                WHERE migration_status = 'ACTIVE' AND claim_token IS NULL
                """;
        final String catalogDefinition = """
                CREATE INDEX idx_summary_replay_claim_fair
                ON public.summary_citation_replay_source USING btree
                (replay_after NULLS FIRST, attempts, patient_id, source_kind, source_record_id)
                WHERE (((migration_status)::text = 'ACTIVE'::text) AND (claim_token IS NULL))
                """;

        assertThat(SchemaPatchRunner.normalizeIndexDefinition(
                catalogDefinition, "public"))
                .isEqualTo(SchemaPatchRunner.normalizeIndexDefinition(
                        requested, "public"));
    }

    @Test
    void isIdempotentAlreadyApplied_doesNotSkipMissingTypeOnCreate() {
        assertThat(SchemaPatchRunner.isIdempotentAlreadyApplied(
                "ERROR: type \"vector\" does not exist",
                "CREATE EXTENSION IF NOT EXISTS vector"))
                .isFalse();
        assertThat(SchemaPatchRunner.isIdempotentAlreadyApplied(
                "ERROR: type \"vector\" does not exist",
                "CREATE TABLE IF NOT EXISTS retrieval_index_chunk (embedding vector(1536))"))
                .isFalse();
        assertThat(SchemaPatchRunner.isIdempotentAlreadyApplied(
                "ERROR: column \"embedding\" does not exist",
                "CREATE INDEX idx_retrieval_chunk_embedding ON retrieval_index_chunk (embedding)"))
                .isFalse();
    }

    @Test
    void isIdempotentAlreadyApplied_skipsOptionalDropOrRenameOfMissingObject() {
        assertThat(SchemaPatchRunner.isIdempotentAlreadyApplied(
                "ERROR: column \"stripe_customer_id\" does not exist",
                "ALTER TABLE users RENAME COLUMN stripe_customer_id TO payment_customer_id"))
                .isTrue();
        assertThat(SchemaPatchRunner.isIdempotentAlreadyApplied(
                "ERROR: constraint \"user_files_file_category_check\" does not exist",
                "ALTER TABLE user_files DROP CONSTRAINT user_files_file_category_check"))
                .isTrue();
        assertThat(SchemaPatchRunner.isIdempotentAlreadyApplied(
                "ERROR: relation \"foo\" already exists",
                "CREATE TABLE foo (id INT)"))
                .isTrue();
    }

    @Test
    void applyRetrieval_includesDedicatedEmbeddingColumnRepair() throws Exception {
        final java.nio.file.Path sourcePath = java.nio.file.Path.of(
                "src/main/java/com/careconnect/config/SchemaPatchRunner.java");
        final java.nio.file.Path resolved = java.nio.file.Files.exists(sourcePath)
                ? sourcePath
                : java.nio.file.Path.of(
                        "backend/core/src/main/java/com/careconnect/config/SchemaPatchRunner.java");
        final String source = java.nio.file.Files.readString(resolved);
        final String applyRetrievalBody = source.substring(
                source.indexOf("private void applyRetrievalIndexChunkPatches()"),
                source.indexOf("private void applyUspsMailpiecePatches()"));
        assertThat(applyRetrievalBody).contains(
                "V2607071921a2 – ensure retrieval_index_chunk.embedding column");
        assertThat(applyRetrievalBody).contains(
                "ADD COLUMN IF NOT EXISTS embedding vector(1536) NULL");
        assertThat(source).contains("verifyRetrievalEmbeddingColumnPresent();");
        assertThat(source).contains("isIdempotentAlreadyApplied");
        assertThat(source).doesNotContain(
                "msg.contains(\"42P16\") || msg.contains(\"already\") || msg.contains(\"does not exist\")");
    }

    @Test
    void run_appliesConcurrentRetrievalIndexesBeforeRequiredSchemaVerify() throws Exception {
        // Contract: verifyRequiredRetrievalSchema expects GIN/ivfflat/source-identity indexes
        // that are only created in ensureRetrievalConcurrentIndexes after the migration unlock.
        // Guard the source ordering so greenfield PostgreSQL boots cannot regress.
        final java.nio.file.Path sourcePath = java.nio.file.Path.of(
                "src/main/java/com/careconnect/config/SchemaPatchRunner.java");
        final java.nio.file.Path resolved = java.nio.file.Files.exists(sourcePath)
                ? sourcePath
                : java.nio.file.Path.of(
                        "backend/core/src/main/java/com/careconnect/config/SchemaPatchRunner.java");
        final String source = java.nio.file.Files.readString(resolved);
        final int unlockIndexes = source.indexOf("ensureRetrievalConcurrentIndexes();");
        final int embeddingVerify = source.indexOf(
                "verifyRetrievalEmbeddingColumnPresent();", unlockIndexes);
        final int postUnlockVerify = source.indexOf(
                "verifyRequiredRetrievalSchema();", unlockIndexes);
        final String applyRetrievalBody = source.substring(
                source.indexOf("private void applyRetrievalIndexChunkPatches()"),
                source.indexOf("private void applyUspsMailpiecePatches()"));
        assertThat(unlockIndexes).isGreaterThan(0);
        assertThat(embeddingVerify).isGreaterThan(unlockIndexes);
        assertThat(postUnlockVerify).isGreaterThan(embeddingVerify);
        assertThat(applyRetrievalBody).doesNotContain("verifyRequiredRetrievalSchema();");
        assertThat(applyRetrievalBody).doesNotContain("verifyRetrievalEmbeddingColumnPresent();");
    }

    @Test
    void run_waitsTenMinutesForProductionSchemaMigrationLock() throws Exception {
        final java.nio.file.Path sourcePath = java.nio.file.Path.of(
                "src/main/java/com/careconnect/config/SchemaPatchRunner.java");
        final java.nio.file.Path resolved = java.nio.file.Files.exists(sourcePath)
                ? sourcePath
                : java.nio.file.Path.of(
                        "backend/core/src/main/java/com/careconnect/config/SchemaPatchRunner.java");
        final String source = java.nio.file.Files.readString(resolved);
        assertThat(source).contains("TimeUnit.MINUTES.toNanos(10)");
        assertThat(source).doesNotContain("TimeUnit.SECONDS.toNanos(30)");
    }

    @Test
    void verifyCallTerminationSchema_toleratesPostgresPredicateCastsAndIsNonFatal()
            throws Exception {
        // Postgres stores predicates as status = 'TERMINATING'::text; exact-quote
        // POSITION checks false-negative and used to crash-loop startup.
        final java.nio.file.Path sourcePath = java.nio.file.Path.of(
                "src/main/java/com/careconnect/config/SchemaPatchRunner.java");
        final java.nio.file.Path resolved = java.nio.file.Files.exists(sourcePath)
                ? sourcePath
                : java.nio.file.Path.of(
                        "backend/core/src/main/java/com/careconnect/config/SchemaPatchRunner.java");
        final String source = java.nio.file.Files.readString(resolved);
        final int methodStart = source.indexOf("private void verifyCallTerminationSchema()");
        final int methodEnd = source.indexOf(
                "private void verifyCallSummaryIdempotencySchema()", methodStart);
        final String method = methodEnd > methodStart
                ? source.substring(methodStart, methodEnd)
                : source.substring(methodStart);
        assertThat(method).doesNotContain("status = ''TERMINATING''");
        assertThat(method).contains("POSITION(");
        assertThat(method).contains("'TERMINATING'");
        assertThat(method).contains("continuing startup (non-fatal)");
        assertThat(method).contains("columns={}");
        assertThat(method).contains("default={}");
        assertThat(method).contains("check={}");
        assertThat(method).contains("index={}");
        assertThat(method).doesNotContain("throw new IllegalStateException");
    }

    @Test
    void run_abortsWhenRequiredProductionPatchFails() throws Exception {
        final DataSource dataSource = mock(DataSource.class);
        final Connection connection = mock(Connection.class);
        final Connection statementConnection = mock(Connection.class);
        final DatabaseMetaData metadata = mock(DatabaseMetaData.class);
        final DatabaseMetaData statementMetadata = mock(DatabaseMetaData.class);
        final Statement statement = mock(Statement.class);
        final ResultSet resultSet = mock(ResultSet.class);
        when(dataSource.getConnection()).thenReturn(connection);
        when(connection.createStatement()).thenReturn(statement);
        when(connection.getMetaData()).thenReturn(metadata);
        when(statement.getConnection()).thenReturn(statementConnection);
        when(statementConnection.getMetaData()).thenReturn(statementMetadata);
        when(statementMetadata.getDatabaseProductName()).thenReturn("H2");
        when(statement.executeQuery(anyString())).thenReturn(resultSet);
        when(resultSet.next()).thenReturn(true);
        when(resultSet.getBoolean(1)).thenReturn(true);
        when(metadata.getDatabaseProductName()).thenReturn("PostgreSQL");
        doAnswer(invocation -> {
            final String sql = invocation.getArgument(0);
            if (sql.contains("CREATE TABLE IF NOT EXISTS call_sessions")) {
                throw new SQLException("required production DDL unavailable");
            }
            return false;
        }).when(statement).execute(anyString());

        final SchemaPatchLedger patchLedger = mock(SchemaPatchLedger.class);

        assertThatThrownBy(() -> new SchemaPatchRunner(dataSource, patchLedger).run())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("Required schema patch")
                .hasRootCauseMessage("required production DDL unavailable");
    }
}
