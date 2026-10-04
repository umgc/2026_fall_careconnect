package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrAuditEvent;
import com.careconnect.model.ehr.EhrConflictResolver;
import com.careconnect.model.ehr.EhrConflictStatus;
import com.careconnect.model.ehr.EhrIdentityConflict;
import com.careconnect.model.ehr.EhrRetrievalOutcome;
import com.careconnect.model.ehr.EhrSourceIdentity;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.TestPropertySource;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The retention queries {@code EhrRetentionWorker} runs against {@code ehr_identity_conflict},
 * {@code ehr_source_identity} and {@code ehr_audit_event}, on a real PostgreSQL. The unit test
 * mocks the repositories, so it cannot tell whether the JPQL selects and deletes the right rows.
 * ({@code ehr_raw_payload}'s pair is TC-EHR-RAW-007 in {@code EhrRawPayloadPostgresJsonbTest}.)
 * <p>
 * Every case uses a cutoff of 2001-01-01, older than anything a real sync could have stored, so
 * the delete statements cannot touch rows this test did not create. Opt-in, like the other
 * PostgreSQL tests here: skipped unless {@code EHR_IT_JDBC_URI} is set, and the target database
 * must hold at least one {@code patient} row.
 * <p>
 * Test IDs TC-EHR-RET-005..007 are permanent. Never renumber, never reuse.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@EnabledIfEnvironmentVariable(named = "EHR_IT_JDBC_URI", matches = ".+")
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
class EhrRetentionQueriesPostgresTest {

    private static final OffsetDateTime CUTOFF = OffsetDateTime.parse("2001-01-01T00:00:00Z");
    private static final Instant BEFORE = CUTOFF.minusDays(1).toInstant();
    private static final Instant AFTER = CUTOFF.plusDays(1).toInstant();

    @Autowired
    private EhrIdentityConflictRepository conflicts;
    @Autowired
    private EhrSourceIdentityRepository sourceIdentities;
    @Autowired
    private EhrAuditEventRepository auditEvents;
    @Autowired
    private EntityManager entityManager;

    private Long patientId;
    private String storedDob;

    @BeforeEach
    void pickPatient() {
        patientId = ((Number) entityManager
                .createNativeQuery("select id from patient order by id limit 1")
                .getSingleResult()).longValue();
        storedDob = (String) entityManager
                .createNativeQuery("select dob from patient where id = :id")
                .setParameter("id", patientId)
                .getSingleResult();
    }

    private Long sourceId(final String code) {
        return ((Number) entityManager
                .createNativeQuery("select id from ehr_source where code = :code")
                .setParameter("code", code)
                .getSingleResult()).longValue();
    }

    private EhrIdentityConflict resolvedConflict(final Instant resolvedAt) {
        return EhrIdentityConflict.builder()
                .patientId(patientId)
                .sourceId(sourceId("ATHENAHEALTH"))
                .fieldName("phone")
                .canonicalValueBefore("555-0100")
                .incomingValue("555-0199")
                .status(EhrConflictStatus.REJECTED)
                .resolvedBy(EhrConflictResolver.SYSTEM)
                .sourceUpdatedAt(resolvedAt)
                .detectedAt(resolvedAt)
                .resolvedAt(resolvedAt)
                .build();
    }

    @Test
    @DisplayName("TC-EHR-RET-005: only conflicts resolved before the cutoff are found and deleted, and never a PENDING one")
    void conflictQueries() {
        final Long expired = conflicts.save(resolvedConflict(BEFORE)).getId();
        final Long recent = conflicts.save(resolvedConflict(AFTER)).getId();

        // An open date_of_birth conflict detected long before the cutoff. One per patient is all
        // the partial unique index allows, so reuse one if the database already holds it.
        Long pending = conflicts
                .findByPatientIdAndFieldNameAndStatus(patientId, "date_of_birth", EhrConflictStatus.PENDING)
                .map(EhrIdentityConflict::getId)
                .orElse(null);
        if (pending == null) {
            pending = conflicts.save(EhrIdentityConflict.builder()
                    .patientId(patientId)
                    .sourceId(sourceId("ATHENAHEALTH"))
                    .fieldName("date_of_birth")
                    .canonicalValueBefore("1950-03-09")
                    .incomingValue("1950-03-10")
                    .status(EhrConflictStatus.PENDING)
                    .sourceUpdatedAt(BEFORE)
                    .detectedAt(BEFORE)
                    .build()).getId();
        }
        entityManager.flush();

        assertThat(conflicts.findPatientsWithConflictResolvedBefore(CUTOFF.toInstant()))
                .singleElement()
                .satisfies(found -> {
                    assertThat(found.getPatientId()).isEqualTo(patientId);
                    assertThat(found.getDob()).isEqualTo(storedDob);
                });

        assertThat(conflicts.deleteResolvedBeforeForPatients(CUTOFF.toInstant(), List.of(-1L))).isZero();
        assertThat(conflicts.deleteResolvedBeforeForPatients(CUTOFF.toInstant(), List.of(patientId))).isEqualTo(1);
        entityManager.clear();

        assertThat(conflicts.existsById(expired)).isFalse();
        assertThat(conflicts.existsById(recent)).isTrue();
        assertThat(conflicts.existsById(pending)).isTrue();
    }

    @Test
    @DisplayName("TC-EHR-RET-006: a source identity snapshot is found and deleted on updated_at, not source_updated_at")
    void sourceIdentityQueries() {
        // (patient, source) is unique, so use a source this patient has no snapshot for.
        final Long freeSource = ((Number) entityManager
                .createNativeQuery("select s.id from ehr_source s where not exists ("
                        + "select 1 from ehr_source_identity i "
                        + "where i.patient_id = :patientId and i.source_id = s.id) order by s.id limit 1")
                .setParameter("patientId", patientId)
                .getSingleResult()).longValue();

        // source_updated_at is decades old from the start; that alone must not make it a candidate.
        final Long id = sourceIdentities.save(EhrSourceIdentity.builder()
                .patientId(patientId)
                .sourceId(freeSource)
                .sourceUpdatedAt(BEFORE)
                .givenName("Synthetic")
                .build()).getId();
        entityManager.flush();

        final LocalDateTime cutoff = CUTOFF.toLocalDateTime();
        assertThat(sourceIdentities.findPatientsWithSnapshotUpdatedBefore(cutoff)).isEmpty();
        assertThat(sourceIdentities.deleteUpdatedBeforeForPatients(cutoff, List.of(patientId))).isZero();

        // Now age the row itself: this application last stored it before the cutoff.
        entityManager
                .createNativeQuery("update ehr_source_identity set updated_at = TIMESTAMP '1999-06-01 00:00:00' "
                        + "where id = :id")
                .setParameter("id", id)
                .executeUpdate();
        entityManager.clear();

        assertThat(sourceIdentities.findPatientsWithSnapshotUpdatedBefore(cutoff))
                .singleElement()
                .satisfies(found -> {
                    assertThat(found.getPatientId()).isEqualTo(patientId);
                    assertThat(found.getDob()).isEqualTo(storedDob);
                });
        assertThat(sourceIdentities.deleteUpdatedBeforeForPatients(cutoff, List.of(-1L))).isZero();
        assertThat(sourceIdentities.deleteUpdatedBeforeForPatients(cutoff, List.of(patientId))).isEqualTo(1);
        entityManager.clear();

        assertThat(sourceIdentities.existsById(id)).isFalse();
    }

    private EhrAuditEvent event(final Long forPatient, final OffsetDateTime at) {
        return EhrAuditEvent.builder()
                .patientId(forPatient)
                .source("ATHENAHEALTH")
                .resourceType("Patient")
                .outcome(EhrRetrievalOutcome.SUCCESS)
                .eventTime(at)
                .build();
    }

    @Test
    @DisplayName("TC-EHR-RET-007: audit events before the cutoff are found and deleted, and one with no patient row reports a null date of birth")
    void auditEventQueries() {
        // ehr_audit_event has no foreign key to patient, so an id with no patient row can be stored.
        final Long noSuchPatient = -424242L;
        final Long expired = auditEvents.save(event(patientId, CUTOFF.minusDays(1))).getId();
        final Long recent = auditEvents.save(event(patientId, CUTOFF.plusDays(1))).getId();
        final Long orphan = auditEvents.save(event(noSuchPatient, CUTOFF.minusDays(1))).getId();
        entityManager.flush();

        final List<PatientDateOfBirth> found = auditEvents.findPatientsWithEventBefore(CUTOFF);
        assertThat(found).hasSize(2);
        assertThat(found)
                .filteredOn(p -> p.getPatientId().equals(patientId))
                .singleElement()
                .satisfies(p -> assertThat(p.getDob()).isEqualTo(storedDob));
        assertThat(found)
                .filteredOn(p -> p.getPatientId().equals(noSuchPatient))
                .singleElement()
                .satisfies(p -> assertThat(p.getDob()).isNull());

        assertThat(auditEvents.deleteEventsBeforeForPatients(CUTOFF, List.of(patientId))).isEqualTo(1);
        entityManager.clear();

        assertThat(auditEvents.existsById(expired)).isFalse();
        assertThat(auditEvents.existsById(recent)).isTrue();
        assertThat(auditEvents.existsById(orphan)).isTrue();
    }
}
