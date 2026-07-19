package com.careconnect.repository.retrieval;

import com.careconnect.service.ai.indexing.chunker.SummaryChunker;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

@DataJpaTest(properties = {
        "spring.jpa.hibernate.ddl-auto=none",
        "spring.flyway.enabled=false",
        "spring.sql.init.mode=never"
})
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Testcontainers(disabledWithoutDocker = true)
class RetrievalIndexChunkRepositoryPostgresTest {

    @Container
    private static final PostgreSQLContainer<?> POSTGRES =
            new PostgreSQLContainer<>("postgres:16-alpine");

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
                    migration_status VARCHAR(24) NOT NULL DEFAULT 'ACTIVE'
                )
                """);
    }

    @Test
    void replayQuery_executesJsonbCastCollectionBindingAndBackoffUpdate() {
        insertChunk("00000000-0000-0000-0000-000000000001", "42", "CALL_SUMMARY");

        assertThat(staleSources()).containsExactly("42");

        final OffsetDateTime retryAfter =
                OffsetDateTime.now(ZoneOffset.UTC).plusHours(1);
        assertThat(repository.markSummaryCitationReplayFailure(
                42L, "42", RetrievalRecordType.summaryTypeNames(), retryAfter))
                .isEqualTo(1);

        assertThat(staleSources()).isEmpty();
        assertThat(jdbcTemplate.queryForObject(
                """
                SELECT chunk_metadata->>'citationReplayAttempts'
                FROM retrieval_index_chunk
                WHERE source_record_id = '42'
                """,
                String.class)).isEqualTo("1");
    }

    @Test
    void replayQuery_excludesAmbiguousLegacyCallVisitCollision() {
        insertChunk("00000000-0000-0000-0000-000000000001", "77", "CALL_SUMMARY");
        insertChunk("00000000-0000-0000-0000-000000000002", "77", "VISIT_SUMMARY");

        assertThat(staleSources()).isEmpty();
        assertThat(repository.quarantineAmbiguousLegacySummarySources()).isEqualTo(2);
        assertThat(jdbcTemplate.queryForObject(
                """
                SELECT COUNT(*) FROM retrieval_index_chunk
                WHERE source_record_id = '77'
                  AND migration_status = 'QUARANTINED'
                """,
                Integer.class)).isEqualTo(2);
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
