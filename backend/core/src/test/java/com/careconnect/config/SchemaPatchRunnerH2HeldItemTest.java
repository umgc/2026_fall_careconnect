package com.careconnect.config;

import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** Checks the H2 test schema's real uniqueness rule without Spring or external services. */
class SchemaPatchRunnerH2HeldItemTest {
    private JdbcTemplate jdbc;
    private SchemaPatchRunner runner;

    @BeforeEach
    void createIsolatedSchema() {
        final DriverManagerDataSource dataSource = new DriverManagerDataSource(
                "jdbc:h2:mem:held_" + UUID.randomUUID() + ";DB_CLOSE_DELAY=-1", "sa", "");
        jdbc = new JdbcTemplate(dataSource);
        runner = new SchemaPatchRunner(dataSource);
        jdbc.execute("CREATE TABLE user_files (id BIGINT PRIMARY KEY)");
        ReflectionTestUtils.invokeMethod(runner, "applyH2AiHeldItemTables");
    }

    @AfterEach
    void closeDatabase() {
        if (jdbc != null) {
            jdbc.execute("SHUTDOWN");
        }
    }

    /** Inserts only synthetic values required by the real held-item schema. */
    private void insert(long patient, String surface, String hash, String status) {
        jdbc.update("INSERT INTO ai_held_item (id, patient_id, requester_user_id, audit_id, "
                        + "source_surface, status, trigger_codes, query_text_hash, draft_answer, "
                        + "citations_json, delivery_status) VALUES (?, ?, 1, ?, ?, ?, '[]', ?, 'draft', '[]', 'NONE')",
                UUID.randomUUID(), patient, UUID.randomUUID(), surface, status, hash);
    }

    @Test
    void duplicatePendingQuestionForSamePatientAndSurfaceIsRejected() {
        // Arrange one open question. Act/assert: another matching open question must fail.
        insert(1, "CHAT", "hash", "PENDING_REVIEW");
        assertThatThrownBy(() -> insert(1, "CHAT", "hash", "PENDING_REVIEW"))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void closedQuestionsDoNotBlockLaterPendingQuestions() {
        // Arrange completed records; closing an open record must also release its key.
        insert(1, "CHAT", "hash", "APPROVED");
        insert(1, "CHAT", "hash", "APPROVED");
        insert(1, "CHAT", "hash", "PENDING_REVIEW");
        jdbc.update("UPDATE ai_held_item SET status = 'APPROVED' WHERE status = 'PENDING_REVIEW'");
        assertThatCode(() -> insert(1, "CHAT", "hash", "PENDING_REVIEW"))
                .doesNotThrowAnyException();
    }

    @Test
    void missingHashAndDifferentPatientOrSurfaceStayIndependent() {
        // Arrange a pending key; null hashes and other patient/surface keys remain valid.
        insert(1, "CHAT", "hash", "PENDING_REVIEW");
        assertThatCode(() -> {
            insert(1, "CHAT", null, "PENDING_REVIEW");
            insert(1, "CHAT", null, "PENDING_REVIEW");
            insert(2, "CHAT", "hash", "PENDING_REVIEW");
            insert(1, "SUMMARY", "hash", "PENDING_REVIEW");
        }).doesNotThrowAnyException();
    }

    @Test
    void schemaReplayRetainsThePendingUniquenessRule() {
        // Arrange existing data; replay must preserve both the row and its constraint.
        insert(1, "CHAT", "hash", "PENDING_REVIEW");
        ReflectionTestUtils.invokeMethod(runner, "applyH2AiHeldItemTables");
        assertThatThrownBy(() -> insert(1, "CHAT", "hash", "PENDING_REVIEW"))
                .isInstanceOf(DataIntegrityViolationException.class);
    }
}
