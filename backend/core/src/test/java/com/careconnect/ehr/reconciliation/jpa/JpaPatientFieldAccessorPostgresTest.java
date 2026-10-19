package com.careconnect.ehr.reconciliation.jpa;

import com.careconnect.ehr.reconciliation.IdentityConflictAuditWriter;
import com.careconnect.ehr.reconciliation.IdentityReconciler;
import com.careconnect.ehr.reconciliation.RecencyWinsIdentityReconciler;
import com.careconnect.ehr.reconciliation.ReconciliationOutcome;
import com.careconnect.ehr.reconciliation.SourceIdentitySnapshot;
import com.careconnect.ehr.reconciliation.support.InMemoryAuditWriter;
import com.careconnect.model.Patient;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrIdentityFieldProvenanceRepository;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.TestPropertySource;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Covers {@link JpaPatientFieldAccessor} — the translation layer between the library's FHIR-shaped
 * field names and {@code Patient}'s own — and records one consequence of Assumption A1 that only
 * becomes visible once a real {@code patient.updated_at} exists to be read.
 *
 * <p>PostgreSQL rather than H2, and committing rather than rolling back, because
 * {@link #applyingOneFieldRaisesTheBaselineForEveryFieldWithoutProvenance()} drives the real
 * reconciler through real transactions: the per-field commits are the point, and a
 * rollback-per-test arrangement would hide exactly the effect being demonstrated.
 *
 * <p>Runs against a throwaway patient it creates and deletes, never the seeded ones.
 *
 * <pre>
 *   EHR_IT_JDBC_URI=jdbc:postgresql://localhost:5433/cc_phase2 \
 *   EHR_IT_DB_USER=postgres EHR_IT_DB_PASSWORD=... \
 *   ./mvnw -Dtest=JpaPatientFieldAccessorPostgresTest test
 * </pre>
 *
 * Test IDs TC-EHR-PACC-001..010 are permanent. Never renumber, never reuse. 001..006 are the
 * author's; 007..010 were added by the Testing Lead on the PR #209 review (2026-09-29).
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@EnabledIfEnvironmentVariable(named = "EHR_IT_JDBC_URI", matches = ".+")
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@Transactional(propagation = Propagation.NOT_SUPPORTED)
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
class JpaPatientFieldAccessorPostgresTest {

    @PersistenceContext
    private EntityManager entityManager;

    @Autowired
    private PatientRepository patientRepository;

    @Autowired
    private EhrIdentityFieldProvenanceRepository provenanceRepository;

    @Autowired
    private PlatformTransactionManager transactionManager;

    private TransactionTemplate tx;
    private JpaPatientFieldAccessor accessor;
    private Long patientId;
    private long sourceId;

    @BeforeEach
    void setUp() {
        tx = new TransactionTemplate(transactionManager);
        accessor = new JpaPatientFieldAccessor(patientRepository);
        sourceId = ((Number) tx.execute(status -> entityManager
                .createNativeQuery("select id from ehr_source order by id limit 1")
                .getSingleResult())).longValue();
        patientId = tx.execute(status -> {
            Patient patient = new Patient();
            patient.setFirstName("Probe");
            patient.setLastName("Patient");
            patient.setEmail("probe@example.invalid");
            return patientRepository.save(patient).getId();
        });
    }

    @AfterEach
    void tearDown() {
        if (patientId == null) {
            return;
        }
        // ehr_identity_field_provenance cascades on patient delete; the audit writer used here is
        // in-memory, so nothing else of this test survives.
        tx.executeWithoutResult(status -> entityManager
                .createNativeQuery("delete from patient where id = :id")
                .setParameter("id", patientId)
                .executeUpdate());
    }

    // ---- TC-EHR-PACC-001 ----

    @Test
    @DisplayName("TC-EHR-PACC-001: library field names map onto Patient, creating the address if absent")
    void libraryFieldNamesMapOntoPatient() {
        Map<String, String> written = new LinkedHashMap<>();
        written.put("given_name", "Ada");
        written.put("family_name", "Lovelace");
        written.put("date_of_birth", "1815-12-10");
        written.put("phone", "555-0199");
        written.put("email", "ada@example.invalid");
        written.put("address_line1", "12 Analytical Way");
        written.put("address_line2", "Suite 2");
        written.put("city", "London");
        written.put("state", "ON");
        written.put("postal_code", "N6A 3K7");

        tx.executeWithoutResult(status ->
                written.forEach((field, value) -> accessor.applyValue(patientId, field, value)));

        written.forEach((field, value) ->
                assertThat(currentValue(field))
                        .as("%s must round-trip", field)
                        .contains(value));

        Patient reloaded = tx.execute(status -> patientRepository.findById(patientId).orElseThrow());
        assertThat(reloaded.getFirstName()).isEqualTo("Ada");
        assertThat(reloaded.getLastName()).isEqualTo("Lovelace");
        assertThat(reloaded.getAddress()).as("the embedded Address must be created on demand").isNotNull();
        assertThat(reloaded.getAddress().getZip())
                .as("postal_code maps onto Address.zip, which is what the column is actually called")
                .isEqualTo("N6A 3K7");
    }

    // ---- TC-EHR-PACC-002 ----

    @Test
    @DisplayName("TC-EHR-PACC-002: null and blank both read as no value, so the fill-empty path applies")
    void nullAndBlankBothReadAsAbsent() {
        assertThat(currentValue("phone"))
                .as("a null column is absent")
                .isEmpty();

        tx.executeWithoutResult(status -> entityManager
                .createNativeQuery("update patient set phone = '   ' where id = :id")
                .setParameter("id", patientId)
                .executeUpdate());

        assertThat(currentValue("phone"))
                .as("whitespace is not a value to adjudicate against; treating it as one would hold a "
                        + "genuine incoming phone number out on a timestamp technicality")
                .isEmpty();

        assertThat(currentValue("city"))
                .as("a field inside a null embedded Address is absent, not an error")
                .isEmpty();
    }

    // ---- TC-EHR-PACC-003 ----

    @Test
    @DisplayName("TC-EHR-PACC-003: an unrecognised field name is rejected, not silently skipped")
    void unknownFieldNamesAreRejected() {
        assertThatThrownBy(() -> tx.execute(status -> accessor.getCurrentValue(patientId, "firstName")))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Unknown identity field 'firstName'")
                .hasMessageContaining("given_name");

        assertThat(JpaPatientFieldAccessor.supportedFieldNames())
                .containsExactly("given_name", "family_name", "date_of_birth", "phone", "email",
                        "address_line1", "address_line2", "city", "state", "postal_code");
    }

    // ---- TC-EHR-PACC-004 ----

    @Test
    @DisplayName("TC-EHR-PACC-004: date_of_birth is validated on write because the column is varchar")
    void dateOfBirthIsValidatedOnWrite() {
        assertThatThrownBy(() -> tx.executeWithoutResult(status ->
                accessor.applyValue(patientId, "date_of_birth", "12/10/1815")))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("ISO-8601");

        tx.executeWithoutResult(status ->
                accessor.applyValue(patientId, "date_of_birth", "  1815-12-10  "));
        assertThat(currentValue("date_of_birth"))
                .as("a valid date is trimmed and canonicalised, never reformatted")
                .contains("1815-12-10");
    }

    // ---- TC-EHR-PACC-005 ----

    @Test
    @DisplayName("TC-EHR-PACC-005: updated_at is a usable baseline and a write advances it")
    void updatedAtIsAUsableBaselineAndAWriteAdvancesIt() {
        Instant before = tx.execute(status -> accessor.getPatientUpdatedAt(patientId));
        assertThat(before)
                .as("Patient extends Auditable, so a row it persisted must carry a baseline")
                .isNotNull();

        tx.executeWithoutResult(status -> accessor.applyValue(patientId, "phone", "555-0123"));

        Instant after = tx.execute(status -> accessor.getPatientUpdatedAt(patientId));
        assertThat(after)
                .as("applying a value is a change to the record, so the baseline must move with it")
                .isAfterOrEqualTo(before);
    }

    // ---- TC-EHR-PACC-006 ----

    /**
     * Records a consequence of Assumption A1 rather than endorsing it.
     * <p>
     * A1 says that a field with no provenance row falls back to {@code patient.updated_at} as its
     * baseline. But {@code updated_at} is a property of the row, not of the field, and applying any
     * field advances it. Read per field, that meant the first disagreeing field in a snapshot raised
     * the baseline above the snapshot's own shared {@code source_updated_at}, and every later field
     * still lacking provenance lost to a bar the snapshot itself had just raised -- indefinitely,
     * since each sync left {@code updated_at} newer still.
     * <p>
     * Unreachable before 2026-09-29, when {@code patient} gained the column that made A1 readable at
     * all. Fixed the same day by hoisting the fallback read to once per snapshot; this test is the
     * scenario that drove the fix and the guard against it regressing.
     * <p>
     * Both fields here disagree, neither has provenance, and both share one incoming timestamp that
     * beats the baseline. Both must therefore land. If this test ever reports one
     * {@code ACCEPTED_NEWER} and one {@code REJECTED_STALE} again, the fallback has gone back to
     * being read per field.
     */
    @Test
    @DisplayName("TC-EHR-PACC-006: every field of one snapshot is judged against the same A1 baseline")
    void everyFieldOfOneSnapshotIsJudgedAgainstTheSameBaseline() {
        Instant backfilled = Instant.now().minus(30, ChronoUnit.DAYS);
        seedUpdatedAt(backfilled);

        // Both fields already hold a value, so neither takes the fill-empty path, and both disagree.
        tx.executeWithoutResult(status -> {
            Patient patient = patientRepository.findById(patientId).orElseThrow();
            patient.setFirstName("Alpha");
            patient.setLastName("Beta");
            patientRepository.save(patient);
        });
        seedUpdatedAt(backfilled); // undo the bump that save() just caused

        IdentityReconciler reconciler = new RecencyWinsIdentityReconciler(
                new JpaIdentityFieldProvenanceStore(provenanceRepository, entityManager),
                accessor,
                new InMemoryAuditWriter(),
                new SpringTransactionRunner(transactionManager));

        Map<String, String> fields = new LinkedHashMap<>();
        fields.put("given_name", "Gamma");
        fields.put("family_name", "Delta");

        // One shared timestamp for both fields, comfortably newer than the backfilled baseline.
        Instant sourceUpdatedAt = backfilled.plus(1, ChronoUnit.DAYS);
        List<ReconciliationOutcome> outcomes = reconciler.reconcile(
                new SourceIdentitySnapshot(patientId, sourceId, sourceUpdatedAt, fields));

        assertThat(outcomes).hasSize(2);
        assertThat(outcomes)
                .as("both fields beat the one baseline captured before the snapshot began; applying "
                        + "the first must not raise the bar for the second")
                .extracting(ReconciliationOutcome::decision)
                .containsExactly(
                        ReconciliationOutcome.Decision.ACCEPTED_NEWER,
                        ReconciliationOutcome.Decision.ACCEPTED_NEWER);

        assertThat(currentValue("given_name")).contains("Gamma");
        assertThat(currentValue("family_name"))
                .as("the second field must land too -- this is the one that was lost when the "
                        + "fallback baseline was re-read per field")
                .contains("Delta");
    }

    // ---- TC-EHR-PACC-007 ----

    /**
     * {@code patient.dob} is a free-text varchar, and the app writes it in two shapes: the onboarding
     * registration screen stores {@code MM/DD/YYYY}, the sign-up screen stores ISO. A FHIR
     * {@code birthDate} is always ISO. The same calendar date must therefore agree, not open a
     * patient confirmation asking them to "confirm" the date they already gave. DEF-EHR-REC-03.
     */
    @Test
    @DisplayName("TC-EHR-PACC-007: a newer ISO date_of_birth agrees with the same date stored as MM/DD/YYYY")
    void newerIsoDateOfBirthAgreesWithTheSameDateStoredUsFormat() {
        Instant backfilled = Instant.now().truncatedTo(ChronoUnit.MICROS).minus(30, ChronoUnit.DAYS);
        seedDob("05/09/1950");
        seedUpdatedAt(backfilled);
        InMemoryAuditWriter audit = new InMemoryAuditWriter();

        List<ReconciliationOutcome> outcomes = reconcilerWith(audit).reconcile(new SourceIdentitySnapshot(
                patientId, sourceId, backfilled.plus(1, ChronoUnit.DAYS), Map.of("date_of_birth", "1950-05-09")));

        assertThat(outcomes)
                .extracting(ReconciliationOutcome::decision)
                .as("05/09/1950 and 1950-05-09 are the same date; there is nothing for the patient to confirm")
                .containsExactly(ReconciliationOutcome.Decision.ALREADY_AGREED);
        assertThat(audit.currentPendingConflict(patientId, "date_of_birth"))
                .as("no PENDING confirmation may be opened for an unchanged date of birth")
                .isEmpty();
    }

    // ---- TC-EHR-PACC-008 ----

    @Test
    @DisplayName("TC-EHR-PACC-008: an older ISO date_of_birth equal to the stored MM/DD/YYYY date writes no REJECTED row")
    void olderIsoDateOfBirthEqualToTheStoredDateWritesNoAuditRow() {
        Instant backfilled = Instant.now().truncatedTo(ChronoUnit.MICROS).minus(30, ChronoUnit.DAYS);
        seedDob("05/09/1950");
        seedUpdatedAt(backfilled);
        InMemoryAuditWriter audit = new InMemoryAuditWriter();

        List<ReconciliationOutcome> outcomes = reconcilerWith(audit).reconcile(new SourceIdentitySnapshot(
                patientId, sourceId, backfilled.minus(1, ChronoUnit.DAYS), Map.of("date_of_birth", "1950-05-09")));

        assertThat(outcomes)
                .extracting(ReconciliationOutcome::decision)
                .containsExactly(ReconciliationOutcome.Decision.ALREADY_AGREED);
        assertThat(audit.decisionsFor(patientId, "date_of_birth"))
                .as("a REJECTED row records a disagreement; the same date in another format is not one")
                .isEmpty();
    }

    // ---- TC-EHR-PACC-009 ----

    @Test
    @DisplayName("TC-EHR-PACC-009: applyValue without a transaction fails loudly and writes nothing")
    void applyValueOutsideATransactionIsRejected() {
        assertThatThrownBy(() -> accessor.applyValue(patientId, "phone", "555-0142"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("requires an active transaction");

        assertThat(currentValue("phone"))
                .as("the guard must fire before the write, not after it")
                .isEmpty();
    }

    // ---- TC-EHR-PACC-010 ----

    /**
     * Characterization, not a requirement: plan question D9 (Q2) asks whether values are trimmed
     * before comparison. The in-memory fake keeps surrounding spaces (TC-EHR-REC-012); this accessor
     * trims on write but not on read, so the two harnesses disagree. Against the real store a padded
     * value is "accepted" without changing anything, and every re-sync of the same snapshot then
     * writes a REJECTED row. If D9 is answered, this expected result changes with it.
     */
    @Test
    @DisplayName("TC-EHR-PACC-010: a whitespace-padded equal value is accepted unchanged, then rejected on every re-sync (D9)")
    void whitespacePaddedEqualValueIsAcceptedThenRejectedOnResync() {
        Instant backfilled = Instant.now().truncatedTo(ChronoUnit.MICROS).minus(30, ChronoUnit.DAYS);
        tx.executeWithoutResult(status -> {
            Patient patient = patientRepository.findById(patientId).orElseThrow();
            patient.setLastName("Smith");
            patientRepository.save(patient);
        });
        seedUpdatedAt(backfilled);
        InMemoryAuditWriter audit = new InMemoryAuditWriter();
        IdentityReconciler reconciler = reconcilerWith(audit);
        // Microseconds, as PostgreSQL stores them: a sub-microsecond incoming timestamp would read
        // as newer than its own stored provenance on the re-sync and hide what is characterized here.
        SourceIdentitySnapshot padded = new SourceIdentitySnapshot(
                patientId, sourceId, backfilled.plus(1, ChronoUnit.DAYS), Map.of("family_name", " Smith "));

        List<ReconciliationOutcome> first = reconciler.reconcile(padded);
        List<ReconciliationOutcome> second = reconciler.reconcile(padded);

        assertThat(first).extracting(ReconciliationOutcome::decision)
                .containsExactly(ReconciliationOutcome.Decision.ACCEPTED_NEWER);
        assertThat(second).extracting(ReconciliationOutcome::decision)
                .containsExactly(ReconciliationOutcome.Decision.REJECTED_STALE);
        assertThat(currentValue("family_name"))
                .as("the accessor trims on write, so the stored value never changed")
                .contains("Smith");
        assertThat(audit.decisionsFor(patientId, "family_name"))
                .extracting(d -> d.outcome())
                .containsExactly(IdentityConflictAuditWriter.Outcome.ACCEPTED, IdentityConflictAuditWriter.Outcome.REJECTED);
    }

    private IdentityReconciler reconcilerWith(InMemoryAuditWriter audit) {
        return new RecencyWinsIdentityReconciler(
                new JpaIdentityFieldProvenanceStore(provenanceRepository, entityManager),
                accessor,
                audit,
                new SpringTransactionRunner(transactionManager));
    }

    /** Native SQL, as the onboarding screen's value arrives through the API: no ISO check on this path. */
    private void seedDob(String dob) {
        tx.executeWithoutResult(status -> entityManager
                .createNativeQuery("update patient set dob = :dob where id = :id")
                .setParameter("dob", dob)
                .setParameter("id", patientId)
                .executeUpdate());
    }

    /**
     * Explicitly typed so the Optional does not have to be inferred through
     * {@code TransactionTemplate.execute} at an AssertJ call site, where it collides with the
     * {@code Predicate} overload of {@code assertThat}.
     */
    private Optional<String> currentValue(String fieldName) {
        return tx.execute(status -> accessor.getCurrentValue(patientId, fieldName));
    }

    private void seedUpdatedAt(Instant instant) {
        LocalDateTime asLocal = LocalDateTime.ofInstant(instant, ZoneId.systemDefault());
        tx.executeWithoutResult(status -> entityManager
                .createNativeQuery("update patient set updated_at = :ts where id = :id")
                .setParameter("ts", asLocal)
                .setParameter("id", patientId)
                .executeUpdate());
    }
}
