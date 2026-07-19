package com.careconnect.repository.retrieval;

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
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
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
                    migration_status VARCHAR(24) NOT NULL DEFAULT 'ACTIVE'
                )
                """);
    }

    @Test
    void replayQuery_executesJsonbCastCollectionBindingAndBackoffUpdate() {
        insertChunk("00000000-0000-0000-0000-000000000001", "42", "CALL_SUMMARY");

        final OffsetDateTime claimedUntil =
                OffsetDateTime.now(ZoneOffset.UTC).plusMinutes(5);
        assertThat(repository.claimStaleSummaryCitationSources(
                        RetrievalRecordType.summaryTypeNames(),
                        SummaryChunker.CITATION_METADATA_VERSION,
                        25,
                        claimedUntil))
                .extracting(RetrievalIndexChunkRepository.SummaryReplayCandidate::getSourceRecordId)
                .containsExactly("42");
        assertThat(repository.claimStaleSummaryCitationSources(
                RetrievalRecordType.summaryTypeNames(),
                SummaryChunker.CITATION_METADATA_VERSION,
                25,
                claimedUntil)).isEmpty();

        final OffsetDateTime retryAfter =
                OffsetDateTime.now(ZoneOffset.UTC).plusHours(1);
        assertThat(repository.markSummaryCitationReplayFailure(
                42L, "42", RetrievalRecordType.summaryTypeNames(), retryAfter))
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

        try (var connection = dataSource.getConnection()) {
            for (final String migration : List.of(
                    "db/migration/V2607071921__create_retrieval_index_chunk.sql",
                    "db/migration/V2607121930__backfill_retrieval_index_chunk_search_vector.sql",
                    "db/migration/V2607161317__add_retrieval_chunk_embedding_backfill_index.sql",
                    "db/migration/V2607182130__add_retrieval_source_ownership_and_replay_state.sql")) {
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
                    'migration_status')
                """,
                Integer.class)).isEqualTo(5);
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
                    CAST(? AS UUID), 42, ?, ?, NULL, 'text',
                    CAST('{"citationMetadataVersion":1}' AS JSONB), NOW(), 'auto'
                )
                """,
                id,
                recordType,
                sourceRecordId);
    }
}

@Testcontainers(disabledWithoutDocker = true)
class RetrievalIndexChunkRepositoryPostgresTest
        extends RetrievalIndexChunkRepositoryPostgresContract {
}
