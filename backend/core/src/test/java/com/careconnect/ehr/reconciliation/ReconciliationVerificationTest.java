package com.careconnect.ehr.reconciliation;

import com.careconnect.ehr.reconciliation.support.InMemoryAuditWriter;
import com.careconnect.ehr.reconciliation.support.InMemoryPatientAccessor;
import com.careconnect.ehr.reconciliation.support.InMemoryProvenanceStore;
import com.careconnect.ehr.reconciliation.support.InMemoryTransactionRunner;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;

import static org.junit.jupiter.api.Assertions.*;

/**
 * WBS 3.2.4 Reconciliation verification (M3). Independent verification of
 * {@link RecencyWinsIdentityReconciler} against the rules in ehr-identity-reconciliation/README.md,
 * covering cases the shared contract suite ({@link AbstractIdentityReconciliationContractTest}) does not:
 * multi-field snapshots, repeated syncs, out-of-order sources, patient isolation, null values, the
 * date_of_birth tie rule, and re-prompting after a patient declines.
 *
 * <p>Tests prefixed {@code finding_} pin down current behaviour the README does not specify
 * (case and whitespace handling). They pass today; each one is listed as an open question in
 * docs/verification/3.2.4-reconciliation-verification.md so the team can confirm or change it.
 *
 * <p>Test IDs (VER-REC-xx) match the verification report.
 */
class ReconciliationVerificationTest {

    private static final String DOB = "date_of_birth";
    private static final String ORG = "ORG-1";
    private static final Instant T1 = Instant.parse("2026-01-01T00:00:00Z");

    private InMemoryPatientAccessor patients;
    private InMemoryAuditWriter audit;
    private IdentityReconciler reconciler;
    private long nextPatientId = 1000;

    @BeforeEach
    void setUp() {
        patients = new InMemoryPatientAccessor();
        audit = new InMemoryAuditWriter();
        reconciler = new RecencyWinsIdentityReconciler(
                new InMemoryProvenanceStore(), patients, audit, new InMemoryTransactionRunner());
    }

    private Object newPatient() {
        return nextPatientId++;
    }

    private List<ReconciliationOutcome> sync(Object patientId, String source, Instant at, Map<String, String> fields) {
        return reconciler.reconcile(new SourceIdentitySnapshot(patientId, source, ORG, at, fields));
    }

    private List<ReconciliationOutcome> sync(Object patientId, String source, Instant at, String field, String value) {
        return sync(patientId, source, at, Map.of(field, value));
    }

    private static Map<String, ReconciliationOutcome.Decision> byField(List<ReconciliationOutcome> outcomes) {
        return outcomes.stream().collect(Collectors.toMap(ReconciliationOutcome::fieldName,
                ReconciliationOutcome::decision, (a, b) -> a, LinkedHashMap::new));
    }

    private Optional<String> value(Object patientId, String field) {
        return patients.getCurrentValue(patientId, field);
    }

    @Test
    @DisplayName("VER-REC-01 One snapshot with several fields decides each field independently")
    void multiFieldSnapshotDecidesEachFieldIndependently() {
        Object p = newPatient();
        sync(p, "ATHENAHEALTH", T1, Map.of("family_name", "Smith", "email", "a@example.com"));

        Map<String, String> epic = new HashMap<>();
        epic.put("family_name", "Smyth");          // newer disagreement -> accepted
        epic.put("email", "a@example.com");        // same value -> already agreed
        epic.put("phone", "555-0100");             // empty on patient -> filled
        epic.put("address_line1", "  ");           // blank -> skipped
        var outcomes = byField(sync(p, "EPIC", T1.plus(1, ChronoUnit.DAYS), epic));

        assertEquals(Map.of(
                "family_name", ReconciliationOutcome.Decision.ACCEPTED_NEWER,
                "email", ReconciliationOutcome.Decision.ALREADY_AGREED,
                "phone", ReconciliationOutcome.Decision.FILLED_EMPTY), outcomes,
                "each field gets its own decision, and the blank field produces no outcome at all");
        assertEquals(Optional.of("Smyth"), value(p, "family_name"));
        assertEquals(Optional.of("555-0100"), value(p, "phone"));
        assertTrue(value(p, "address_line1").isEmpty());
        assertEquals(1, audit.decisionsFor(p, "family_name").size());
        assertTrue(audit.decisionsFor(p, "email").isEmpty());
        assertTrue(audit.decisionsFor(p, "phone").isEmpty());
    }

    @Test
    @DisplayName("VER-REC-02 A pending date_of_birth does not hold back other fields in the same snapshot")
    void pendingDateOfBirthDoesNotBlockOtherFieldsInTheSameSnapshot() {
        Object p = newPatient();
        sync(p, "ATHENAHEALTH", T1, Map.of(DOB, "1950-05-04", "family_name", "Smith"));

        var outcomes = byField(sync(p, "EPIC", T1.plus(1, ChronoUnit.DAYS),
                Map.of(DOB, "1950-05-06", "family_name", "Smyth")));

        assertEquals(ReconciliationOutcome.Decision.PENDING_PATIENT_CONFIRMATION, outcomes.get(DOB));
        assertEquals(ReconciliationOutcome.Decision.ACCEPTED_NEWER, outcomes.get("family_name"));
        assertEquals(Optional.of("1950-05-04"), value(p, DOB), "DOB waits for the patient");
        assertEquals(Optional.of("Smyth"), value(p, "family_name"), "other fields apply straight away");
    }

    @Test
    @DisplayName("VER-REC-03 Receiving the same newer snapshot twice changes the patient once and audits once")
    void repeatedIdenticalSnapshotIsIdempotent() {
        Object p = newPatient();
        Instant t2 = T1.plus(1, ChronoUnit.DAYS);
        sync(p, "ATHENAHEALTH", T1, "family_name", "Smith");

        var first = sync(p, "EPIC", t2, "family_name", "Smyth");
        var retry = sync(p, "EPIC", t2, "family_name", "Smyth");

        assertEquals(ReconciliationOutcome.Decision.ACCEPTED_NEWER, first.get(0).decision());
        assertEquals(ReconciliationOutcome.Decision.ALREADY_AGREED, retry.get(0).decision(),
                "a retried sync must not be treated as a second conflict");
        assertEquals(1, audit.decisionsFor(p, "family_name").size(), "exactly one audit row for one real change");
    }

    @Test
    @DisplayName("VER-REC-04 Three sources arriving out of timestamp order converge on the newest")
    void threeSourcesArrivingOutOfOrderConvergeOnTheNewest() {
        Object p = newPatient();
        Instant t2 = T1.plus(2, ChronoUnit.DAYS);
        Instant t3 = T1.plus(3, ChronoUnit.DAYS);

        sync(p, "ATHENAHEALTH", T1, "family_name", "Alpha");
        var newest = sync(p, "ORACLE_HEALTH", t3, "family_name", "Gamma");
        var middleArrivesLast = sync(p, "EPIC", t2, "family_name", "Beta");

        assertEquals(ReconciliationOutcome.Decision.ACCEPTED_NEWER, newest.get(0).decision());
        assertEquals(ReconciliationOutcome.Decision.REJECTED_STALE, middleArrivesLast.get(0).decision(),
                "arriving last must not beat a newer timestamp");
        assertEquals(Optional.of("Gamma"), value(p, "family_name"));

        List<RecordedDecision> decisions = audit.decisionsFor(p, "family_name");
        assertEquals(2, decisions.size());
        assertEquals(IdentityConflictAuditWriter.Outcome.ACCEPTED, decisions.get(0).outcome());
        assertEquals(IdentityConflictAuditWriter.Outcome.REJECTED, decisions.get(1).outcome());
        assertEquals("Beta", decisions.get(1).incomingValue(), "the losing value is still recorded for audit");
    }

    @Test
    @DisplayName("VER-REC-05 Reconciling one patient never changes another patient's values or baseline")
    void patientsAreIsolatedFromEachOther() {
        Object alice = newPatient();
        Object bob = newPatient();
        Instant later = T1.plus(10, ChronoUnit.DAYS);

        sync(alice, "ATHENAHEALTH", T1, "family_name", "Anders");
        sync(bob, "ATHENAHEALTH", T1, "family_name", "Brown");
        sync(alice, "EPIC", later, "family_name", "Andersen");

        assertEquals(Optional.of("Brown"), value(bob, "family_name"));
        assertTrue(audit.decisionsFor(bob, "family_name").isEmpty());

        // Bob's baseline must still be T1: a disagreement just after T1 (but long before Alice's
        // `later`) is newer for Bob and must win.
        var bobUpdate = sync(bob, "EPIC", T1.plus(1, ChronoUnit.DAYS), "family_name", "Browne");
        assertEquals(ReconciliationOutcome.Decision.ACCEPTED_NEWER, bobUpdate.get(0).decision(),
                "Alice's newer provenance must not leak into Bob's baseline");
    }

    @Test
    @DisplayName("VER-REC-06 A null field value is skipped the same way a blank one is")
    void nullIncomingValueIsSkipped() {
        Object p = newPatient();
        sync(p, "ATHENAHEALTH", T1, "phone", "555-0100");

        Map<String, String> withNull = new HashMap<>();
        withNull.put("phone", null);
        var outcomes = sync(p, "EPIC", T1.plus(1, ChronoUnit.DAYS), withNull);

        assertTrue(outcomes.isEmpty());
        assertEquals(Optional.of("555-0100"), value(p, "phone"), "a missing value must never erase a real one");
    }

    @Test
    @DisplayName("VER-REC-07 A date_of_birth candidate with exactly the baseline timestamp is rejected, not pending")
    void dateOfBirthTieWithBaselineIsRejectedNotPending() {
        Object p = newPatient();
        sync(p, "ATHENAHEALTH", T1, DOB, "1950-05-04");

        var tie = sync(p, "EPIC", T1, DOB, "1950-05-06");

        assertEquals(ReconciliationOutcome.Decision.REJECTED_STALE, tie.get(0).decision(),
                "Assumption A2 (ties keep the existing value) must apply to date_of_birth too");
        assertTrue(audit.currentPendingConflict(p, DOB).isEmpty(), "a tie must not prompt the patient");
    }

    @Test
    @DisplayName("VER-REC-08 Confirming a date_of_birth twice fails the second time")
    void finalizingTheSameDateOfBirthTwiceThrows() {
        Object p = newPatient();
        sync(p, "ATHENAHEALTH", T1, DOB, "1950-05-04");
        sync(p, "EPIC", T1.plus(1, ChronoUnit.DAYS), DOB, "1950-05-06");

        reconciler.finalizePendingDateOfBirth(p, ORG, true);

        assertThrows(IllegalStateException.class, () -> reconciler.finalizePendingDateOfBirth(p, ORG, true),
                "a double-submitted confirmation must not apply or audit anything a second time");
        assertEquals(1, audit.decisionsFor(p, DOB).size());
    }

    @Test
    @DisplayName("VER-REC-09 After an accepted date_of_birth, a sync with the same value does not reopen it")
    void acceptedDateOfBirthIsNotReopenedByAnAgreeingSync() {
        Object p = newPatient();
        sync(p, "ATHENAHEALTH", T1, DOB, "1950-05-04");
        sync(p, "EPIC", T1.plus(1, ChronoUnit.DAYS), DOB, "1950-05-06");
        reconciler.finalizePendingDateOfBirth(p, ORG, true);

        var again = sync(p, "EPIC", T1.plus(2, ChronoUnit.DAYS), DOB, "1950-05-06");

        assertEquals(ReconciliationOutcome.Decision.ALREADY_AGREED, again.get(0).decision());
        assertTrue(audit.currentPendingConflict(p, DOB).isEmpty());
    }

    @Test
    @DisplayName("VER-REC-10 After a patient declines, a newer different candidate prompts them again")
    void declinedDateOfBirthCanBeReopenedByANewerCandidate() {
        Object p = newPatient();
        sync(p, "ATHENAHEALTH", T1, DOB, "1950-05-04");
        sync(p, "EPIC", T1.plus(1, ChronoUnit.DAYS), DOB, "1950-05-06");
        reconciler.finalizePendingDateOfBirth(p, ORG, false);

        var newer = sync(p, "EPIC", T1.plus(2, ChronoUnit.DAYS), DOB, "1950-05-06");

        // Declining leaves provenance at T1, so the same Epic value with a newer timestamp is a new
        // candidate. Documented as open question Q3 in the verification report: product may want a
        // declined value to stay declined.
        assertEquals(ReconciliationOutcome.Decision.PENDING_PATIENT_CONFIRMATION, newer.get(0).decision());
        assertEquals(Optional.of("1950-05-04"), value(p, DOB));
    }

    @Test
    @DisplayName("VER-REC-11 Finding: values differing only in letter case are treated as a disagreement")
    void finding_caseOnlyDifferenceIsADisagreement() {
        Object p = newPatient();
        sync(p, "ATHENAHEALTH", T1, "family_name", "Smith");

        var outcome = sync(p, "EPIC", T1.plus(1, ChronoUnit.DAYS), "family_name", "SMITH");

        // Open question Q1: should "Smith" vs "SMITH" count as agreement? Today it is an ACCEPTED
        // conflict, which overwrites the patient's capitalisation and writes an audit row.
        assertEquals(ReconciliationOutcome.Decision.ACCEPTED_NEWER, outcome.get(0).decision());
        assertEquals(Optional.of("SMITH"), value(p, "family_name"));
    }

    @Test
    @DisplayName("VER-REC-12 Finding: surrounding whitespace is kept and counts as a disagreement")
    void finding_surroundingWhitespaceIsKept() {
        Object p = newPatient();
        sync(p, "ATHENAHEALTH", T1, "family_name", "Smith");

        var outcome = sync(p, "EPIC", T1.plus(1, ChronoUnit.DAYS), "family_name", " Smith ");

        // Open question Q2: adapters should probably trim before calling reconcile(); today the padded
        // value wins and is stored as-is.
        assertEquals(ReconciliationOutcome.Decision.ACCEPTED_NEWER, outcome.get(0).decision());
        assertEquals(Optional.of(" Smith "), value(p, "family_name"));
    }
}
