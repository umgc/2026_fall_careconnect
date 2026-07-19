package com.careconnect.repository.retrieval;

import com.careconnect.config.SchemaPatchRunner;
import com.careconnect.service.ai.indexing.chunker.SummaryChunker;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.datasource.init.ScriptUtils;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Executors;
import javax.sql.DataSource;

import static org.assertj.core.api.Assertions.assertThat;

@DataJpaTest(properties = {
        "spring.jpa.hibernate.ddl-auto=none",
        "spring.flyway.enabled=false",
        "spring.sql.init.mode=never"
})
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
abstract class RetrievalIndexChunkRepositoryPostgresContract {

    @Container
    private static final PostgreSQLContainer<?> POSTGRES =
            new PostgreSQLContainer<>("pgvector/pgvector:pg16");

    @DynamicPropertySource
    static void postgresProperties(final DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
        registry.add("spring.datasource.driver-class-name", POSTGRES::getDriverClassName);
        registry.add("spring.jpa.database-platform",
                () -> "org.hibernate.dialect.PostgreSQLDialect");
    }

    @Autowired
    private RetrievalIndexChunkRepository repository;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private DataSource dataSource;

    @BeforeEach
    void createContractTable() {
        jdbcTemplate.execute("DROP TABLE IF EXISTS retrieval_index_chunk");
        jdbcTemplate.execute("""
                CREATE TABLE retrieval_index_chunk (
                    id UUID PRIMARY KEY,
                    patient_id BIGINT NOT NULL,
                    record_type VARCHAR(40) NOT NULL,
                    source_record_id VARCHAR(120) NOT NULL,
                    source_kind VARCHAR(40),
                    chunk_text TEXT NOT NULL,
                    chunk_metadata JSONB,
                    indexed_at TIMESTAMPTZ NOT NULL,
                    consent_scope VARCHAR(40),
                    citation_replay_after TIMESTAMPTZ,
                    citation_replay_attempts INTEGER NOT NULL DEFAULT 0,
                    citation_replay_claimed_until TIMESTAMPTZ,
                    citation_replay_claim_token UUID,
                    migration_status VARCHAR(24) NOT NULL DEFAULT 'ACTIVE'
                )
                """);
    }

    @Test
    void replayQuery_executesJsonbCastCollectionBindingAndBackoffUpdate() {
        insertChunk("00000000-0000-0000-0000-000000000001", "42", "CALL_SUMMARY");

        final OffsetDateTime claimedUntil =
                OffsetDateTime.now(ZoneOffset.UTC).plusMinutes(5);
        final UUID claimToken = UUID.randomUUID();
        assertThat(repository.claimStaleSummaryCitationSources(
                        RetrievalRecordType.summaryTypeNames(),
                        SummaryChunker.CITATION_METADATA_VERSION,
                        25,
                        claimedUntil,
                        claimToken))
                .extracting(RetrievalIndexChunkRepository.SummaryReplayCandidate::getSourceRecordId)
                .containsExactly("42");
        assertThat(repository.claimStaleSummaryCitationSources(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION,
                25,
                claimedUntil,
                UUID.randomUUID())).isEmpty();

        final OffsetDateTime retryAfter =
                OffsetDateTime.now(ZoneOffset.UTC).plusHours(1);
        assertThat(repository.markSummaryCitationReplayFailure(
                42L, "42", RetrievalRecordType.summaryTypeNames(), retryAfter, claimToken))
                .isEqualTo(1);

        assertThat(staleSources()).isEmpty();
        assertThat(jdbcTemplate.queryForObject(
                """
                SELECT citation_replay_attempts
                FROM retrieval_index_chunk
                WHERE source_record_id = '42'
                """,
                Integer.class)).isEqualTo(1);
        assertThat(jdbcTemplate.queryForObject(
                """
                SELECT citation_replay_after IS NOT NULL
                FROM retrieval_index_chunk
                WHERE source_record_id = '42'
                """,
                Boolean.class)).isTrue();
        assertThat(jdbcTemplate.queryForObject(
                """
                SELECT citation_replay_claimed_until IS NULL
                FROM retrieval_index_chunk
                WHERE source_record_id = '42'
                """,
                Boolean.class)).isTrue();
    }

    @Test
    void replayQuery_returnsLegacySourceForAuthoritativeResolution() {
        insertChunk("00000000-0000-0000-0000-000000000001", "77", "CALL_SUMMARY");
        insertChunk("00000000-0000-0000-0000-000000000002", "77", "VISIT_SUMMARY");
        jdbcTemplate.update("UPDATE retrieval_index_chunk SET source_kind = NULL");

        assertThat(staleSources()).containsExactly("77");
        assertThat(repository.quarantineAmbiguousLegacySummarySources()).isEqualTo(2);
        assertThat(jdbcTemplate.queryForObject(
                """
                SELECT COUNT(*) FROM retrieval_index_chunk
                WHERE source_record_id = '77'
                  AND migration_status = 'QUARANTINED'
                """,
                Integer.class)).isEqualTo(2);
    }

    @Test
    void retrievalMigrations_executeAgainstPgvectorAndMatchRequiredSchema() throws Exception {
        jdbcTemplate.execute("DROP TABLE IF EXISTS retrieval_index_chunk");
        jdbcTemplate.execute("CREATE EXTENSION IF NOT EXISTS vector");
        jdbcTemplate.execute("CREATE TABLE IF NOT EXISTS patient (id BIGINT PRIMARY KEY)");
        jdbcTemplate.execute("CREATE TABLE IF NOT EXISTS users (id BIGINT PRIMARY KEY)");

        try (var connection = dataSource.getConnection()) {
            for (final String migration : List.of(
                    "db/migration/V2607071921__create_retrieval_index_chunk.sql",
                    "db/migration/V2607121930__backfill_retrieval_index_chunk_search_vector.sql",
                    "db/migration/V2607161317__add_retrieval_chunk_embedding_backfill_index.sql",
                    "db/migration/V2607182130__add_retrieval_source_ownership_and_replay_state.sql",
                    "db/migration/V2607182230__create_call_sessions_and_participants.sql",
                    "db/migration/V2607182330__fence_retrieval_replay_claims.sql")) {
                ScriptUtils.executeSqlScript(connection, new ClassPathResource(migration));
            }
        }

        assertThat(jdbcTemplate.queryForObject(
                """
                SELECT COUNT(*) FROM information_schema.columns
                WHERE table_name = 'retrieval_index_chunk'
                  AND column_name IN (
                    'source_kind', 'citation_replay_after',
                    'citation_replay_attempts', 'citation_replay_claimed_until',
                    'citation_replay_claim_token', 'migration_status')
                """,
                Integer.class)).isEqualTo(6);
        assertThat(jdbcTemplate.queryForObject(
                """
                SELECT COUNT(*) FROM pg_indexes
                WHERE tablename = 'retrieval_index_chunk'
                  AND indexname IN (
                    'idx_retrieval_chunk_embedding',
                    'idx_retrieval_chunk_source_identity',
                    'idx_retrieval_summary_replay',
                    'idx_retrieval_summary_replay_claim')
                """,
                Integer.class)).isEqualTo(4);
    }

    @Test
    void concurrentWorkers_claimDifferentRepresentativeSources() throws Exception {
        insertChunk("00000000-0000-0000-0000-000000000001", "call-summary:41", "CALL_SUMMARY");
        insertChunk("00000000-0000-0000-0000-000000000002", "call-summary:42", "CALL_SUMMARY");
        insertChunk("00000000-0000-0000-0000-000000000003", "call-summary:43", "CALL_SUMMARY");

        final var executor = Executors.newFixedThreadPool(2);
        try {
            var first = executor.submit(() -> repository.claimStaleSummaryCitationSources(
                    RetrievalRecordType.summaryTypeNames(),
                    SummaryChunker.CITATION_METADATA_VERSION, 1,
                    OffsetDateTime.now(ZoneOffset.UTC).plusMinutes(5), UUID.randomUUID()));
            var second = executor.submit(() -> repository.claimStaleSummaryCitationSources(
                    RetrievalRecordType.summaryTypeNames(),
                    SummaryChunker.CITATION_METADATA_VERSION, 1,
                    OffsetDateTime.now(ZoneOffset.UTC).plusMinutes(5), UUID.randomUUID()));

            final var claimed = new java.util.HashSet<String>();
            first.get().forEach(candidate -> claimed.add(candidate.getSourceRecordId()));
            second.get().forEach(candidate -> claimed.add(candidate.getSourceRecordId()));
            assertThat(claimed).hasSize(2);
        } finally {
            executor.shutdownNow();
        }
    }

    @Test
    void expiredWorkerCannotReleaseOrFailNewerLease() {
        insertChunk("00000000-0000-0000-0000-000000000001", "call-summary:42", "CALL_SUMMARY");
        final UUID expiredToken = UUID.randomUUID();
        final var first = repository.claimStaleSummaryCitationSources(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION, 1,
                OffsetDateTime.now(ZoneOffset.UTC).plusMinutes(5), expiredToken);
        assertThat(first).hasSize(1);
        jdbcTemplate.update("""
                UPDATE retrieval_index_chunk
                SET citation_replay_claimed_until = NOW() - INTERVAL '1 second'
                """);

        final UUID currentToken = UUID.randomUUID();
        assertThat(repository.claimStaleSummaryCitationSources(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION, 1,
                OffsetDateTime.now(ZoneOffset.UTC).plusMinutes(5), currentToken)).hasSize(1);

        assertThat(repository.releaseSummaryCitationReplayClaim(
                42L, "call-summary:42", RetrievalRecordType.summaryTypeNames(), expiredToken))
                .isZero();
        assertThat(repository.markSummaryCitationReplayFailure(
                42L, "call-summary:42", RetrievalRecordType.summaryTypeNames(),
                OffsetDateTime.now(ZoneOffset.UTC).plusHours(1), expiredToken)).isZero();
        assertThat(repository.releaseSummaryCitationReplayClaim(
                42L, "call-summary:42", RetrievalRecordType.summaryTypeNames(), currentToken))
                .isEqualTo(1);
    }

    @Test
    void malformedAndOverflowingMetadataDoNotAbortClaimBatch() {
        insertChunk("00000000-0000-0000-0000-000000000001", "call-summary:41", "CALL_SUMMARY");
        insertChunk("00000000-0000-0000-0000-000000000002", "call-summary:42", "CALL_SUMMARY");
        jdbcTemplate.update("""
                UPDATE retrieval_index_chunk
                SET chunk_metadata = CAST(
                  CASE source_record_id
                    WHEN 'call-summary:41' THEN '{"citationMetadataVersion":"999999999999999999999"}'
                    ELSE '{"citationMetadataVersion":"not-an-integer"}'
                  END AS JSONB)
                """);

        assertThat(repository.claimStaleSummaryCitationSources(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION, 2,
                OffsetDateTime.now(ZoneOffset.UTC).plusMinutes(5), UUID.randomUUID()))
                .hasSize(2);
    }

    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void productionBootstrap_repairsHibernateFirstSchemaAndForeignKeys() {
        prepareBootstrapDependencies();
        new SchemaPatchRunner(dataSource).run();
        new SchemaPatchRunner(dataSource).run(); // upgrade/bootstrap is idempotent

        assertThat(jdbcTemplate.queryForObject("""
                SELECT COUNT(*) FROM information_schema.columns
                WHERE table_name = 'retrieval_index_chunk'
                  AND column_name IN ('search_vector', 'embedding',
                    'citation_replay_claim_token', 'migration_status')
                """, Integer.class)).isEqualTo(4);
        assertThat(jdbcTemplate.queryForObject("""
                SELECT COUNT(*) FROM pg_constraint
                WHERE convalidated AND conname IN (
                  'fk_retrieval_chunk_patient',
                  'fk_call_sessions_patient', 'fk_call_sessions_created_by',
                  'fk_call_participants_session', 'fk_call_participants_user',
                  'fk_call_participants_invited_by')
                """, Integer.class)).isEqualTo(6);
    }

    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void productionBootstrap_buildsFreshSchemaAndRecoversInvalidConcurrentIndex() {
        jdbcTemplate.execute("DROP TABLE IF EXISTS retrieval_index_chunk");
        prepareBootstrapDependencies();
        new SchemaPatchRunner(dataSource).run();
        insertChunk("00000000-0000-0000-0000-000000000001", "call-summary:42", "CALL_SUMMARY");
        insertChunk("00000000-0000-0000-0000-000000000002", "call-summary:42", "CALL_SUMMARY");
        jdbcTemplate.execute("DROP INDEX idx_retrieval_summary_replay");
        try {
            jdbcTemplate.execute("""
                    CREATE UNIQUE INDEX CONCURRENTLY idx_retrieval_summary_replay
                    ON retrieval_index_chunk (source_record_id)
                    """);
        } catch (org.springframework.dao.DataAccessException expected) {
            // PostgreSQL intentionally leaves the failed concurrent index invalid.
        }
        assertThat(indexReadyAndValid("idx_retrieval_summary_replay")).isFalse();

        new SchemaPatchRunner(dataSource).run();

        assertThat(indexReadyAndValid("idx_retrieval_summary_replay")).isTrue();
    }

    private List<String> staleSources() {
        return repository.findStaleSummaryCitationSources(
                        RetrievalRecordType.summaryTypeNames(),
                        SummaryChunker.CITATION_METADATA_VERSION,
                        25)
                .stream()
                .map(RetrievalIndexChunkRepository.SummaryReplayCandidate::getSourceRecordId)
                .toList();
    }

    private void insertChunk(
            final String id,
            final String sourceRecordId,
            final String recordType) {
        jdbcTemplate.update(
                """
                INSERT INTO retrieval_index_chunk (
                    id, patient_id, record_type, source_record_id, source_kind,
                    chunk_text, chunk_metadata, indexed_at, consent_scope
                ) VALUES (
                    CAST(? AS UUID), 42, ?, ?, 'CALL_SUMMARY', 'text',
                    CAST('{"citationMetadataVersion":1}' AS JSONB), NOW(), 'auto'
                )
                """,
                id,
                recordType,
                sourceRecordId);
    }

    private void prepareBootstrapDependencies() {
        jdbcTemplate.execute("CREATE EXTENSION IF NOT EXISTS vector");
        jdbcTemplate.execute("CREATE TABLE IF NOT EXISTS users (id BIGINT PRIMARY KEY, email VARCHAR(255))");
        jdbcTemplate.execute("CREATE TABLE IF NOT EXISTS patient (id BIGINT PRIMARY KEY, user_id BIGINT)");
        jdbcTemplate.execute("""
                CREATE TABLE IF NOT EXISTS indexing_outbox (
                  id BIGSERIAL PRIMARY KEY, processed_at TIMESTAMPTZ)
                """);
    }

    private boolean indexReadyAndValid(final String indexName) {
        final Boolean ready = jdbcTemplate.queryForObject("""
                SELECT i.indisvalid AND i.indisready
                FROM pg_index i
                JOIN pg_class c ON c.oid = i.indexrelid
                WHERE c.relname = ?
                """, Boolean.class, indexName);
        return Boolean.TRUE.equals(ready);
    }
}

@Testcontainers(disabledWithoutDocker = true)
class RetrievalIndexChunkRepositoryPostgresTest
        extends RetrievalIndexChunkRepositoryPostgresContract {
}
