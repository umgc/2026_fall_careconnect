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
import java.util.concurrent.TimeUnit;
import javax.sql.DataSource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

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
        jdbcTemplate.execute("DROP TABLE IF EXISTS summary_citation_replay_source");
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
        jdbcTemplate.execute("""
                CREATE TABLE summary_citation_replay_source (
                    patient_id BIGINT NOT NULL,
                    source_kind VARCHAR(40) NOT NULL,
                    source_record_id VARCHAR(120) NOT NULL,
                    replay_after TIMESTAMPTZ,
                    attempts INTEGER NOT NULL DEFAULT 0,
                    claimed_until TIMESTAMPTZ,
                    claim_token UUID,
                    migration_status VARCHAR(24) NOT NULL DEFAULT 'ACTIVE',
                    quarantine_reason VARCHAR(255),
                    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                    PRIMARY KEY (patient_id, source_kind, source_record_id)
                )
                """);
    }

    @Test
    void replayQuery_executesJsonbCastCollectionBindingAndBackoffUpdate() {
        insertChunk("00000000-0000-0000-0000-000000000001", "42", "CALL_SUMMARY");

        final OffsetDateTime claimedUntil =
                OffsetDateTime.now(ZoneOffset.UTC).plusMinutes(5);
        final var claimed = repository.claimStaleSummaryCitationSources(
                        RetrievalRecordType.summaryTypeNames(),
                        SummaryChunker.CITATION_METADATA_VERSION,
                        25,
                        claimedUntil,
                        8);
        assertThat(claimed)
                .extracting(RetrievalIndexChunkRepository.SummaryReplayCandidate::getSourceRecordId)
                .containsExactly("42");
        final UUID claimToken = claimed.get(0).getClaimToken();
        assertThat(claimToken).isNotNull();
        assertThat(repository.claimStaleSummaryCitationSources(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION,
                25,
                claimedUntil,
                8)).isEmpty();

        final OffsetDateTime retryAfter =
                OffsetDateTime.now(ZoneOffset.UTC).plusHours(1);
        assertThat(repository.markSummaryCitationReplayFailure(
                42L, "42", retryAfter, claimToken))
                .isEqualTo(1);

        assertThat(staleSources()).isEmpty();
        assertThat(jdbcTemplate.queryForObject(
                """
                SELECT attempts
                FROM summary_citation_replay_source
                WHERE source_record_id = '42'
                """,
                Integer.class)).isEqualTo(1);
        assertThat(jdbcTemplate.queryForObject(
                """
                SELECT replay_after IS NOT NULL
                FROM summary_citation_replay_source
                WHERE source_record_id = '42'
                """,
                Boolean.class)).isTrue();
        assertThat(jdbcTemplate.queryForObject(
                """
                SELECT claimed_until IS NULL AND claim_token IS NULL
                FROM summary_citation_replay_source
                WHERE source_record_id = '42'
                """,
                Boolean.class)).isTrue();
    }

    @Test
    void replayQuery_doesNotClaimUntypedAmbiguousChunks() {
        insertChunk("00000000-0000-0000-0000-000000000001", "77", "CALL_SUMMARY");
        insertChunk("00000000-0000-0000-0000-000000000002", "77", "VISIT_SUMMARY");
        jdbcTemplate.update("UPDATE retrieval_index_chunk SET source_kind = NULL");

        assertThat(staleSources()).isEmpty();
        assertThat(repository.quarantineLegacySummarySourceAcrossPatients(
                "77", RetrievalRecordType.summaryTypeNames())).isEqualTo(2);
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
        jdbcTemplate.execute("DROP TABLE IF EXISTS summary_citation_replay_source");
        jdbcTemplate.execute("DROP TABLE IF EXISTS retrieval_index_chunk");
        jdbcTemplate.execute("CREATE EXTENSION IF NOT EXISTS vector");
        jdbcTemplate.execute("CREATE TABLE IF NOT EXISTS patient (id BIGINT PRIMARY KEY)");
        jdbcTemplate.execute("CREATE TABLE IF NOT EXISTS users (id BIGINT PRIMARY KEY)");
        jdbcTemplate.execute("""
                CREATE TABLE IF NOT EXISTS call_summaries (
                  id BIGINT PRIMARY KEY, patient_id BIGINT, summary_json TEXT,
                  status VARCHAR(24), generated_at TIMESTAMP)
                """);

        try (var connection = dataSource.getConnection()) {
            for (final String migration : List.of(
                    "db/migration/V2607071921__create_retrieval_index_chunk.sql",
                    "db/migration/V2607121930__backfill_retrieval_index_chunk_search_vector.sql",
                    "db/migration/V2607161317__add_retrieval_chunk_embedding_backfill_index.sql",
                    "db/migration/V2607182130__add_retrieval_source_ownership_and_replay_state.sql",
                    "db/migration/V2607182230__create_call_sessions_and_participants.sql",
                    "db/migration/V2607182330__fence_retrieval_replay_claims.sql",
                    "db/migration/V2607190100__create_summary_citation_replay_source.sql")) {
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
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void concurrentWorkers_claimDifferentRepresentativeSources() throws Exception {
        insertChunk("00000000-0000-0000-0000-000000000001", "call-summary:41", "CALL_SUMMARY");
        insertChunk("00000000-0000-0000-0000-000000000002", "call-summary:42", "CALL_SUMMARY");
        insertChunk("00000000-0000-0000-0000-000000000003", "call-summary:43", "CALL_SUMMARY");

        final var executor = Executors.newFixedThreadPool(2);
        try {
            var first = executor.submit(() -> repository.claimStaleSummaryCitationSources(
                    RetrievalRecordType.summaryTypeNames(),
                    SummaryChunker.CITATION_METADATA_VERSION, 1,
                    OffsetDateTime.now(ZoneOffset.UTC).plusMinutes(5), 8));
            var second = executor.submit(() -> repository.claimStaleSummaryCitationSources(
                    RetrievalRecordType.summaryTypeNames(),
                    SummaryChunker.CITATION_METADATA_VERSION, 1,
                    OffsetDateTime.now(ZoneOffset.UTC).plusMinutes(5), 8));

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
        final var first = repository.claimStaleSummaryCitationSources(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION, 1,
                OffsetDateTime.now(ZoneOffset.UTC).plusMinutes(5), 8);
        assertThat(first).hasSize(1);
        final UUID expiredToken = first.get(0).getClaimToken();
        jdbcTemplate.update("""
                UPDATE summary_citation_replay_source
                SET claimed_until = NOW() - INTERVAL '1 second'
                """);

        final var second = repository.claimStaleSummaryCitationSources(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION, 1,
                OffsetDateTime.now(ZoneOffset.UTC).plusMinutes(5), 8);
        assertThat(second).hasSize(1);
        final UUID currentToken = second.get(0).getClaimToken();
        assertThat(currentToken).isNotEqualTo(expiredToken);

        assertThat(repository.releaseSummaryCitationReplayClaim(
                42L, "call-summary:42", expiredToken))
                .isZero();
        assertThat(repository.markSummaryCitationReplayFailure(
                42L, "call-summary:42",
                OffsetDateTime.now(ZoneOffset.UTC).plusHours(1), expiredToken)).isZero();
        assertThat(repository.releaseSummaryCitationReplayClaim(
                42L, "call-summary:42", currentToken))
                .isEqualTo(1);
    }

    @Test
    void claimBatch_assignsUniqueClaimTokensPerSource() {
        insertChunk("00000000-0000-0000-0000-000000000001", "call-summary:41", "CALL_SUMMARY");
        insertChunk("00000000-0000-0000-0000-000000000002", "call-summary:42", "CALL_SUMMARY");
        final var claimed = repository.claimStaleSummaryCitationSources(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION, 2,
                OffsetDateTime.now(ZoneOffset.UTC).plusMinutes(5), 8);
        assertThat(claimed).hasSize(2);
        assertThat(claimed.get(0).getClaimToken())
                .isNotNull()
                .isNotEqualTo(claimed.get(1).getClaimToken());
    }

    @Test
    void claimBatch_excludesSourcesAtMaxAttempts() {
        insertChunk("00000000-0000-0000-0000-000000000001", "call-summary:42", "CALL_SUMMARY");
        jdbcTemplate.update("""
                UPDATE summary_citation_replay_source
                SET attempts = 8
                WHERE source_record_id = 'call-summary:42'
                """);
        assertThat(repository.claimStaleSummaryCitationSources(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION, 1,
                OffsetDateTime.now(ZoneOffset.UTC).plusMinutes(5), 8))
                .isEmpty();
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
                OffsetDateTime.now(ZoneOffset.UTC).plusMinutes(5), 8))
                .hasSize(2);
    }

    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void authoritativeRecoveryCreatesCanonicalReplayAndPreservesLegacyRows() throws Exception {
        prepareBootstrapDependencies();
        jdbcTemplate.update("INSERT INTO patient (id) VALUES (42) ON CONFLICT DO NOTHING");
        jdbcTemplate.update("""
                INSERT INTO call_summaries (
                  id, patient_id, summary_json, status, generated_at)
                VALUES (77, 42, '{}', 'SUCCESS', NOW())
                ON CONFLICT DO NOTHING
                """);
        insertChunk("00000000-0000-0000-0000-000000000077", "77", "CALL_SUMMARY");
        jdbcTemplate.update("""
                UPDATE retrieval_index_chunk
                SET source_kind = NULL, migration_status = 'QUARANTINED'
                WHERE source_record_id = '77'
                """);

        try (var connection = dataSource.getConnection()) {
            ScriptUtils.executeSqlScript(connection, new ClassPathResource(
                    "db/migration/V2607190100__create_summary_citation_replay_source.sql"));
        }

        assertThat(jdbcTemplate.queryForObject("""
                SELECT COUNT(*) FROM summary_citation_replay_source
                WHERE patient_id = 42
                  AND source_kind = 'CALL_SUMMARY'
                  AND source_record_id = 'call-summary:77'
                  AND migration_status = 'ACTIVE'
                """, Integer.class)).isEqualTo(1);
        assertThat(jdbcTemplate.queryForObject("""
                SELECT COUNT(*) FROM retrieval_index_chunk
                WHERE source_record_id = '77'
                  AND source_kind IS NULL
                  AND migration_status = 'QUARANTINED'
                """, Integer.class)).isEqualTo(1);
        assertThat(repository.claimStaleSummaryCitationSources(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION,
                1,
                OffsetDateTime.now(ZoneOffset.UTC).plusMinutes(5),
                8))
                .extracting(RetrievalIndexChunkRepository.SummaryReplayCandidate::getSourceRecordId)
                .containsExactly("call-summary:77");
    }

    @Test
    void currentCanonicalChunksMakeQuarantinedLegacyReplayTerminal() {
        insertChunk(
                "00000000-0000-0000-0000-000000000077",
                "call-summary:77",
                "CALL_SUMMARY");
        jdbcTemplate.update("""
                UPDATE retrieval_index_chunk
                SET chunk_metadata = jsonb_build_object(
                      'citationMetadataVersion', ?)
                WHERE source_record_id = 'call-summary:77'
                """, SummaryChunker.CITATION_METADATA_VERSION);
        jdbcTemplate.update("""
                INSERT INTO retrieval_index_chunk (
                  id, patient_id, record_type, source_record_id, source_kind,
                  chunk_text, chunk_metadata, indexed_at, consent_scope,
                  migration_status)
                VALUES (
                  '00000000-0000-0000-0000-000000000078', 42,
                  'CALL_SUMMARY', '77', NULL, 'legacy',
                  '{"citationMetadataVersion":1}', NOW(), 'auto', 'QUARANTINED')
                """);

        assertThat(staleSources()).isEmpty();
        assertThat(repository.claimStaleSummaryCitationSources(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION,
                1,
                OffsetDateTime.now(ZoneOffset.UTC).plusMinutes(5),
                8)).isEmpty();
        assertThat(jdbcTemplate.queryForObject("""
                SELECT migration_status
                FROM retrieval_index_chunk
                WHERE source_record_id = '77'
                """, String.class)).isEqualTo("QUARANTINED");
    }

    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void productionBootstrap_repairsHibernateFirstSchemaAndForeignKeys() {
        jdbcTemplate.execute("DROP TABLE summary_citation_replay_source");
        jdbcTemplate.execute("""
                CREATE TABLE summary_citation_replay_source (
                  patient_id BIGINT, source_kind VARCHAR(40),
                  source_record_id VARCHAR(120))
                """);
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
        jdbcTemplate.execute("CREATE SCHEMA IF NOT EXISTS catalog_decoy");
        jdbcTemplate.execute("""
                CREATE TABLE IF NOT EXISTS catalog_decoy.retrieval_index_chunk (
                  citation_replay_after TIMESTAMPTZ, patient_id BIGINT,
                  source_record_id VARCHAR(120))
                """);
        jdbcTemplate.execute("""
                CREATE INDEX IF NOT EXISTS idx_retrieval_summary_replay
                ON catalog_decoy.retrieval_index_chunk (
                  citation_replay_after, patient_id, source_record_id)
                """);

        new SchemaPatchRunner(dataSource).run();

        assertThat(indexReadyAndValid("idx_retrieval_summary_replay")).isTrue();
    }

    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void productionBootstrap_freshReplayIndexesValidateOnSecondRun() {
        jdbcTemplate.execute("DROP TABLE IF EXISTS summary_citation_replay_source");
        prepareBootstrapDependencies();

        new SchemaPatchRunner(dataSource).run();
        new SchemaPatchRunner(dataSource).run();

        assertThat(indexDefinition("idx_summary_replay_claim_fair"))
                .contains("replay_after NULLS FIRST")
                .contains("(migration_status)::text = 'ACTIVE'::text");
        assertThat(indexDefinition("idx_summary_replay_expired_claim"))
                .contains("replay_after NULLS FIRST")
                .contains("(migration_status)::text = 'ACTIVE'::text");
        assertThat(indexReadyAndValid("idx_summary_replay_claim_fair")).isTrue();
        assertThat(indexReadyAndValid("idx_summary_replay_expired_claim")).isTrue();
    }

    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void productionBootstrap_serializesRequiredDdlAcrossConcurrentNodes() throws Exception {
        jdbcTemplate.execute("DROP TABLE IF EXISTS summary_citation_replay_source");
        jdbcTemplate.execute("DROP TABLE IF EXISTS retrieval_index_chunk");
        jdbcTemplate.execute("DROP TABLE IF EXISTS call_participants");
        jdbcTemplate.execute("DROP TABLE IF EXISTS call_sessions");
        prepareBootstrapDependencies();
        final var executor = Executors.newFixedThreadPool(2);
        try {
            final var first = executor.submit(() -> new SchemaPatchRunner(dataSource).run());
            final var second = executor.submit(() -> new SchemaPatchRunner(dataSource).run());

            first.get(90, TimeUnit.SECONDS);
            second.get(90, TimeUnit.SECONDS);
        } finally {
            executor.shutdownNow();
        }

        assertThat(jdbcTemplate.queryForObject("""
                SELECT COUNT(*) FROM information_schema.tables
                WHERE table_schema = current_schema()
                  AND table_name IN (
                    'call_sessions', 'call_participants',
                    'call_summaries', 'retrieval_index_chunk',
                    'summary_citation_replay_source')
                """, Integer.class)).isEqualTo(5);
        assertThat(indexReadyAndValid("idx_summary_replay_claim_fair")).isTrue();
        assertThat(indexReadyAndValid("idx_summary_replay_expired_claim")).isTrue();
    }

    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void productionBootstrap_upgradesOldCallSummarySchemaAndRepairsReplayIndexes() {
        prepareBootstrapDependencies();
        jdbcTemplate.execute("DROP TABLE IF EXISTS call_summaries CASCADE");
        jdbcTemplate.execute("""
                CREATE TABLE call_summaries (
                  id BIGSERIAL PRIMARY KEY,
                  call_id VARCHAR(120) NOT NULL,
                  patient_id BIGINT,
                  summary_json TEXT NOT NULL,
                  status VARCHAR(24) NOT NULL,
                  generated_at TIMESTAMP NOT NULL)
                """);
        jdbcTemplate.execute("""
                CREATE INDEX uq_call_summary_generation_snapshot
                ON call_summaries (call_id)
                """);
        jdbcTemplate.execute("DROP INDEX IF EXISTS idx_summary_replay_claim_fair");
        jdbcTemplate.execute("""
                CREATE INDEX idx_summary_replay_claim_fair
                ON summary_citation_replay_source (patient_id)
                """);
        jdbcTemplate.execute("DROP INDEX IF EXISTS idx_summary_replay_expired_claim");
        jdbcTemplate.execute("""
                CREATE INDEX idx_summary_replay_expired_claim
                ON summary_citation_replay_source (source_record_id)
                """);
        jdbcTemplate.execute("""
                ALTER TABLE summary_citation_replay_source
                ADD CONSTRAINT legacy_summary_replay_patient_fk
                FOREIGN KEY (patient_id) REFERENCES patient(id) NOT VALID
                """);

        new SchemaPatchRunner(dataSource).run();
        new SchemaPatchRunner(dataSource).run();

        assertThat(jdbcTemplate.queryForObject("""
                SELECT COUNT(*) FROM information_schema.columns
                WHERE table_schema = current_schema()
                  AND table_name = 'call_summaries'
                  AND column_name IN (
                    'transcript_snapshot_version', 'model_config_version')
                """, Integer.class)).isEqualTo(2);
        assertThat(indexDefinition("uq_call_summary_generation_snapshot"))
                .contains("UNIQUE INDEX")
                .contains("(call_id, transcript_snapshot_version, model_config_version)")
                .contains("transcript_snapshot_version IS NOT NULL")
                .contains("model_config_version IS NOT NULL");
        assertThat(indexDefinition("idx_summary_replay_claim_fair"))
                .contains("(replay_after, attempts, patient_id, source_kind, source_record_id)")
                .contains("migration_status")
                .contains("claim_token IS NULL");
        assertThat(indexDefinition("idx_summary_replay_expired_claim"))
                .contains("(claimed_until, replay_after, patient_id, source_kind, source_record_id)")
                .contains("migration_status")
                .contains("claim_token IS NOT NULL");
        assertThat(indexReadyAndValid("uq_call_summary_generation_snapshot")).isTrue();
        assertThat(indexReadyAndValid("idx_summary_replay_claim_fair")).isTrue();
        assertThat(indexReadyAndValid("idx_summary_replay_expired_claim")).isTrue();
        assertThat(equivalentForeignKeyCount(
                "summary_citation_replay_source", "patient_id", "patient", "id", "a"))
                .isEqualTo(1);
        assertThat(jdbcTemplate.queryForObject("""
                SELECT convalidated FROM pg_constraint
                WHERE conname = 'legacy_summary_replay_patient_fk'
                  AND connamespace = (
                    SELECT oid FROM pg_namespace WHERE nspname = current_schema())
                """, Boolean.class)).isTrue();
    }

    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void productionBootstrap_rollsBackCallSummaryResourceOnFailure() {
        prepareBootstrapDependencies();
        jdbcTemplate.execute("DROP TABLE IF EXISTS call_summaries CASCADE");
        jdbcTemplate.execute("""
                CREATE TABLE call_summaries (
                  id BIGSERIAL PRIMARY KEY,
                  patient_id BIGINT,
                  summary_json TEXT NOT NULL,
                  status VARCHAR(24) NOT NULL,
                  generated_at TIMESTAMP NOT NULL)
                """);
        try {
            assertThatThrownBy(() -> new SchemaPatchRunner(dataSource).run())
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("V2607190010");
            assertThat(jdbcTemplate.queryForObject("""
                    SELECT COUNT(*) FROM information_schema.columns
                    WHERE table_schema = current_schema()
                      AND table_name = 'call_summaries'
                      AND column_name IN (
                        'transcript_snapshot_version', 'model_config_version')
                    """, Integer.class)).isZero();
        } finally {
            jdbcTemplate.execute("DROP TABLE call_summaries CASCADE");
            prepareBootstrapDependencies();
        }
    }

    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void productionBootstrap_rollsBackReplayResourceOnFailure() {
        prepareBootstrapDependencies();
        jdbcTemplate.execute("DROP TABLE summary_citation_replay_source");
        jdbcTemplate.execute("DROP TABLE call_summaries CASCADE");
        jdbcTemplate.execute("""
                CREATE TABLE call_summaries (
                  call_id VARCHAR(120) NOT NULL)
                """);
        try {
            assertThatThrownBy(() -> new SchemaPatchRunner(dataSource).run())
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("V2607190100");
            assertThat(jdbcTemplate.queryForObject("""
                    SELECT to_regclass(
                      current_schema() || '.summary_citation_replay_source') IS NULL
                    """, Boolean.class)).isTrue();
        } finally {
            jdbcTemplate.execute("DROP TABLE call_summaries CASCADE");
            prepareBootstrapDependencies();
        }
    }

    private List<String> staleSources() {
        return repository.findStaleSummaryCitationSources(
                        RetrievalRecordType.summaryTypeNames(),
                        SummaryChunker.CITATION_METADATA_VERSION,
                        25,
                        8)
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
        jdbcTemplate.update("""
                INSERT INTO summary_citation_replay_source (
                  patient_id, source_kind, source_record_id)
                VALUES (42, 'CALL_SUMMARY', ?)
                ON CONFLICT DO NOTHING
                """, sourceRecordId);
    }

    private void prepareBootstrapDependencies() {
        jdbcTemplate.execute("CREATE EXTENSION IF NOT EXISTS vector");
        jdbcTemplate.execute("CREATE TABLE IF NOT EXISTS users (id BIGINT PRIMARY KEY, email VARCHAR(255))");
        jdbcTemplate.execute("CREATE TABLE IF NOT EXISTS patient (id BIGINT PRIMARY KEY, user_id BIGINT)");
        jdbcTemplate.execute("""
                CREATE TABLE IF NOT EXISTS scheduled_visits (
                  id BIGINT PRIMARY KEY)
                """);
        jdbcTemplate.execute("""
                CREATE TABLE IF NOT EXISTS call_summaries (
                  id BIGINT PRIMARY KEY, patient_id BIGINT, summary_json TEXT,
                  status VARCHAR(24), generated_at TIMESTAMP)
                """);
        jdbcTemplate.execute("""
                CREATE TABLE IF NOT EXISTS indexing_outbox (
                  id BIGSERIAL PRIMARY KEY, processed_at TIMESTAMPTZ)
                """);
    }

    private String indexDefinition(final String indexName) {
        return jdbcTemplate.queryForObject("""
                SELECT pg_get_indexdef(i.indexrelid)
                FROM pg_index i
                JOIN pg_class c ON c.oid = i.indexrelid
                JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = current_schema() AND c.relname = ?
                """, String.class, indexName);
    }

    private int equivalentForeignKeyCount(
            final String table,
            final String column,
            final String referencedTable,
            final String referencedColumn,
            final String deleteAction) {
        return jdbcTemplate.queryForObject("""
                SELECT COUNT(*) FROM pg_constraint c
                WHERE c.conrelid = CAST(? AS regclass)
                  AND c.confrelid = CAST(? AS regclass)
                  AND c.contype = 'f'
                  AND c.conkey = ARRAY[(
                    SELECT attnum FROM pg_attribute
                    WHERE attrelid = CAST(? AS regclass) AND attname = ?
                  )]::smallint[]
                  AND c.confkey = ARRAY[(
                    SELECT attnum FROM pg_attribute
                    WHERE attrelid = CAST(? AS regclass) AND attname = ?
                  )]::smallint[]
                  AND c.confdeltype = CAST(? AS "char")
                """, Integer.class,
                table, referencedTable, table, column,
                referencedTable, referencedColumn, deleteAction);
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
