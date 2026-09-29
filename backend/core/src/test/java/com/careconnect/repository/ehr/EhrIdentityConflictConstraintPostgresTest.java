package com.careconnect.repository.ehr;

import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.TestPropertySource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Proves the {@code ehr_identity_conflict} CHECK constraints actually reject what they are
 * meant to reject.
 * <p>
 * These constraints are not decoration — they are where the reconciliation design is enforced.
 * The 2026-09-26 reversal held {@code date_of_birth} for patient confirmation while every other
 * field resolves automatically by recency in the transaction that detects it. Nothing in Java
 * stops a future change writing a {@code PENDING} row for {@code phone}, which would silently
 * reintroduce the exact risk that reversal accepted only for non-DOB fields. So the rule lives
 * in the database, and this test is what stops the rule being quietly dropped.
 * <p>
 * <strong>Why PostgreSQL only.</strong> The normal suite runs on H2, where these constraints do
 * not exist: they are applied by {@code SchemaPatchRunner}, a {@code CommandLineRunner} that
 * does not execute in a slice test. Asserting them on H2 would pass for the wrong reason.
 * <p>
 * Opt-in, needing a database the application has already booted against at least once:
 * <pre>
 *   EHR_IT_JDBC_URI=jdbc:postgresql://localhost:5433/cc_phase2 \
 *   EHR_IT_DB_USER=postgres EHR_IT_DB_PASSWORD=... \
 *   ./mvnw -Dtest=EhrIdentityConflictConstraintPostgresTest test
 * </pre>
 * Skipped when {@code EHR_IT_JDBC_URI} is unset, so CI stays green.
 * <p>
 * Test IDs TC-EHR-CONF-001..005 are permanent. Never renumber, never reuse.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@EnabledIfEnvironmentVariable(named = "EHR_IT_JDBC_URI", matches = ".+")
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@TestPropertySource(properties = {
        "spring.datasource.url=${EHR_IT_JDBC_URI}",
        "spring.datasource.username=${EHR_IT_DB_USER}",
        "spring.datasource.password=${EHR_IT_DB_PASSWORD}",
        "spring.datasource.driver-class-name=org.postgresql.Driver",
        "spring.jpa.database-platform=org.hibernate.dialect.PostgreSQLDialect",
        "spring.jpa.hibernate.ddl-auto=none",
        "spring.flyway.enabled=false",
        "spring.sql.init.mode=never"
})
class EhrIdentityConflictConstraintPostgresTest {

    @Autowired
    private EntityManager entityManager;

    /**
     * Clears the table for the duration of each test. Rows committed outside the suite — a
     * manual psql session, an earlier application run — would otherwise collide with
     * uq_ehr_identity_conflict_open and fail the uniqueness tests for the wrong reason. The
     * surrounding @DataJpaTest transaction rolls this back, so nothing is actually destroyed.
     */
    @BeforeEach
    void clearConflicts() {
        entityManager.createNativeQuery("delete from ehr_identity_conflict").executeUpdate();
        entityManager.flush();
    }

    private long patientId() {
        return ((Number) entityManager
                .createNativeQuery("select id from patient order by id limit 1")
                .getSingleResult()).longValue();
    }

    private long sourceId() {
        return ((Number) entityManager
                .createNativeQuery("select id from ehr_source where code = 'ATHENAHEALTH'")
                .getSingleResult()).longValue();
    }

    /** Inserts by native SQL deliberately: the point is what the database refuses, not what JPA refuses. */
    private void insert(String fieldName, String status, String resolvedBy) {
        String resolved = resolvedBy == null ? "null" : "'" + resolvedBy + "'";
        String resolvedAt = resolvedBy == null ? "null" : "now()";
        entityManager.createNativeQuery(
                        "insert into ehr_identity_conflict"
                                + " (patient_id, source_id, field_name, status, source_updated_at,"
                                + "  detected_at, resolved_at, resolved_by)"
                                + " values (:p, :s, :f, :st, now(), now(), " + resolvedAt + ", " + resolved + ")")
                .setParameter("p", patientId())
                .setParameter("s", sourceId())
                .setParameter("f", fieldName)
                .setParameter("st", status)
                .executeUpdate();
        entityManager.flush();
    }

    @Test
    @DisplayName("TC-EHR-CONF-001: PENDING is rejected for any field other than date_of_birth")
    void pendingIsRejectedForNonDobFields() {
        assertThatThrownBy(() -> insert("phone", "PENDING", null))
                .hasMessageContaining("ck_ehr_identity_conflict_pending_dob");
    }

    @Test
    @DisplayName("TC-EHR-CONF-002: PENDING is accepted for date_of_birth")
    void pendingIsAcceptedForDateOfBirth() {
        insert("date_of_birth", "PENDING", null);

        Number open = (Number) entityManager
                .createNativeQuery("select count(*) from ehr_identity_conflict"
                        + " where status = 'PENDING' and field_name = 'date_of_birth'")
                .getSingleResult();
        assertThat(open.intValue()).isPositive();
    }

    @Test
    @DisplayName("TC-EHR-CONF-003: a second open conflict on the same field is rejected")
    void secondOpenConflictOnSameFieldIsRejected() {
        insert("date_of_birth", "PENDING", null);

        assertThatThrownBy(() -> insert("date_of_birth", "PENDING", null))
                .hasMessageContaining("uq_ehr_identity_conflict_open");
    }

    @Test
    @DisplayName("TC-EHR-CONF-004: a closed conflict must carry resolved_at and resolved_by")
    void closedConflictMustCarryResolution() {
        assertThatThrownBy(() -> insert("phone", "ACCEPTED", null))
                .hasMessageContaining("ck_ehr_identity_conflict_resolution");
    }

    @Test
    @DisplayName("TC-EHR-CONF-005: STAFF is not a valid resolver, SYSTEM is")
    void staffIsNotAValidResolver() {
        // SYSTEM first: PostgreSQL aborts the transaction on a constraint violation, so
        // nothing can run after the expected failure.
        insert("phone", "ACCEPTED", "SYSTEM");

        assertThatThrownBy(() -> insert("email", "ACCEPTED", "STAFF"))
                .hasMessageContaining("ck_ehr_identity_conflict_resolver");
    }
}
