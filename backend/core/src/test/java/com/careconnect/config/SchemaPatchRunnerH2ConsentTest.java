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

/** Verifies consent uniqueness on a real isolated H2 schema, without external services. */
class SchemaPatchRunnerH2ConsentTest {
    private JdbcTemplate jdbc;
    private SchemaPatchRunner runner;

    @BeforeEach
    void createIsolatedSchema() {
        final DriverManagerDataSource dataSource = new DriverManagerDataSource(
                "jdbc:h2:mem:consent_" + UUID.randomUUID() + ";DB_CLOSE_DELAY=-1", "sa", "");
        jdbc = new JdbcTemplate(dataSource);
        runner = new SchemaPatchRunner(dataSource);
        ReflectionTestUtils.invokeMethod(runner, "applyH2ConsentGrantsTable");
    }

    @AfterEach
    void closeDatabase() {
        if (jdbc != null) {
            jdbc.execute("SHUTDOWN");
        }
    }

    /** Creates a synthetic grant with its patient, grantee, scope, and status explicit. */
    private void insert(long patient, long grantee, String scope, String status) {
        jdbc.update("INSERT INTO consent_grants (patient_user_id, grantee_user_id, "
                        + "grantee_role, scope, status) VALUES (?, ?, 'CAREGIVER', ?, ?)",
                patient, grantee, scope, status);
    }

    @Test
    void matchingActiveGrantIsRejectedAfterSchemaReplay() {
        // Arrange a live grant and replay the real schema setup.
        insert(1, 2, "AI_RETRIEVAL", "ACTIVE");
        ReflectionTestUtils.invokeMethod(runner, "applyH2ConsentGrantsTable");
        // Act/assert: replay must not drop the active-only uniqueness rule.
        assertThatThrownBy(() -> insert(1, 2, "AI_RETRIEVAL", "ACTIVE"))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void revokedHistoryDoesNotPreventAReplacementGrant() {
        // Arrange multiple historic grants and then revoke the active one.
        insert(1, 2, "AI_RETRIEVAL", "REVOKED");
        insert(1, 2, "AI_RETRIEVAL", "REVOKED");
        insert(1, 2, "AI_RETRIEVAL", "ACTIVE");
        jdbc.update("UPDATE consent_grants SET status = 'REVOKED' WHERE status = 'ACTIVE'");
        // Act/assert: a new active grant remains possible for the same key.
        assertThatCode(() -> insert(1, 2, "AI_RETRIEVAL", "ACTIVE"))
                .doesNotThrowAnyException();
    }

    @Test
    void differentPatientGranteeAndScopeStayIndependent() {
        // Arrange one grant. Act/assert: each distinct key may also be active.
        insert(1, 2, "AI_RETRIEVAL", "ACTIVE");
        assertThatCode(() -> {
            insert(3, 2, "AI_RETRIEVAL", "ACTIVE");
            insert(1, 3, "AI_RETRIEVAL", "ACTIVE");
            insert(1, 2, "OTHER_SCOPE", "ACTIVE");
        }).doesNotThrowAnyException();
    }
}
