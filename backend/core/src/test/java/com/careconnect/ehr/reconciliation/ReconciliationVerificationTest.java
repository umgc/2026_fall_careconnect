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
 * <p>Test IDs (TC-EHR-REC-xxx) match the verification report.
 */
class ReconciliationVerificationTest {

    private static final String DOB = "date_of_birth";
    private static final Instant T1 = Instant.parse("2026-01-01T00:00:00Z");

    private InMemoryPatientAccessor patients;
    private InMemoryAuditWriter audit;
    private IdentityReconciler reconciler;
    private long nextPatientId = 1000;
    /** Ids are Long as of PR #209; each source code gets a stable numeric id, as in InMemoryContractTest. */
    private final Map<String, Long> sourceIds = new HashMap<>();

    @BeforeEach
    void setUp() {
        patients = new InMemoryPatientAccessor();
        audit = new InMemoryAuditWriter();
        reconciler = new RecencyWinsIdentityReconciler(
                new InMemoryProvenanceStore(), patients, audit, new InMemoryTransactionRunner());
    }

    private Long newPatient() {
        return nextPatientId++;
    }

    private Long sourceId(String sourceCode) {
        if (sourceCode == null) {
            return null; // keeps the missing-source case (TC-EHR-REC-030) a missing source
        }
        return sourceIds.computeIfAbsent(sourceCode, code -> 500L + sourceIds.size());
    }

    private List<ReconciliationOutcome> sync(Long patientId, String source, Instant at, Map<String, String> fields) {
        return reconciler.reconcile(new SourceIdentitySnapshot(patientId, sourceId(source), at, fields));
    }

    private List<ReconciliationOutcome> sync(Long patientId, String source, Instant at, String field, String value) {
        return sync(patientId, source, at, Map.of(field, value));
    }

    private static Map<String, ReconciliationOutcome.Decision> byField(List<ReconciliationOutcome> outcomes) {
        return outcomes.stream().collect(Collectors.toMap(ReconciliationOutcome::fieldName,
                ReconciliationOutcome::decision, (a, b) -> a, LinkedHashMap::new));
    }

    private Optional<String> value(Long patientId, String field) {
        return patients.getCurrentValue(patientId, field);
    }

    @Test
    @DisplayName("TC-EHR-REC-001 One snapshot with several fields decides each field independently")
    void multiFieldSnapshotDecidesEachFieldIndependently() {
        Long p = newPatient();
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
    @DisplayName("TC-EHR-REC-002 A pending date_of_birth does not hold back other fields in the same snapshot")
    void pendingDateOfBirthDoesNotBlockOtherFieldsInTheSameSnapshot() {
        Long p = newPatient();
        sync(p, "ATHENAHEALTH", T1, Map.of(DOB, "1950-05-04", "family_name", "Smith"));

        var outcomes = byField(sync(p, "EPIC", T1.plus(1, ChronoUnit.DAYS),
                Map.of(DOB, "1950-05-06", "family_name", "Smyth")));

        assertEquals(ReconciliationOutcome.Decision.PENDING_PATIENT_CONFIRMATION, outcomes.get(DOB));
        assertEquals(ReconciliationOutcome.Decision.ACCEPTED_NEWER, outcomes.get("family_name"));
        assertEquals(Optional.of("1950-05-04"), value(p, DOB), "DOB waits for the patient");
        assertEquals(Optional.of("Smyth"), value(p, "family_name"), "other fields apply straight away");
    }

    @Test
    @DisplayName("TC-EHR-REC-003 Receiving the same newer snapshot twice changes the patient once and audits once")
    void repeatedIdenticalSnapshotIsIdempotent() {
        Long p = newPatient();
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
    @DisplayName("TC-EHR-REC-004 Three sources arriving out of timestamp order converge on the newest")
    void threeSourcesArrivingOutOfOrderConvergeOnTheNewest() {
        Long p = newPatient();
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
    @DisplayName("TC-EHR-REC-005 Reconciling one patient never changes another patient's values or baseline")
    void patientsAreIsolatedFromEachOther() {
        Long alice = newPatient();
        Long bob = newPatient();
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
    @DisplayName("TC-EHR-REC-006 A null field value is skipped the same way a blank one is")
    void nullIncomingValueIsSkipped() {
        Long p = newPatient();
        sync(p, "ATHENAHEALTH", T1, "phone", "555-0100");

        Map<String, String> withNull = new HashMap<>();
        withNull.put("phone", null);
        var outcomes = sync(p, "EPIC", T1.plus(1, ChronoUnit.DAYS), withNull);

        assertTrue(outcomes.isEmpty());
        assertEquals(Optional.of("555-0100"), value(p, "phone"), "a missing value must never erase a real one");
    }

    @Test
    @DisplayName("TC-EHR-REC-007 A date_of_birth candidate with exactly the baseline timestamp is rejected, not pending")
    void dateOfBirthTieWithBaselineIsRejectedNotPending() {
        Long p = newPatient();
        sync(p, "ATHENAHEALTH", T1, DOB, "1950-05-04");

        var tie = sync(p, "EPIC", T1, DOB, "1950-05-06");

        assertEquals(ReconciliationOutcome.Decision.REJECTED_STALE, tie.get(0).decision(),
                "Assumption A2 (ties keep the existing value) must apply to date_of_birth too");
        assertTrue(audit.currentPendingConflict(p, DOB).isEmpty(), "a tie must not prompt the patient");
    }

    @Test
    @DisplayName("TC-EHR-REC-008 Confirming a date_of_birth twice fails the second time")
    void finalizingTheSameDateOfBirthTwiceThrows() {
        Long p = newPatient();
        sync(p, "ATHENAHEALTH", T1, DOB, "1950-05-04");
        sync(p, "EPIC", T1.plus(1, ChronoUnit.DAYS), DOB, "1950-05-06");

        reconciler.finalizePendingDateOfBirth(p, true);

        assertThrows(IllegalStateException.class, () -> reconciler.finalizePendingDateOfBirth(p, true),
                "a double-submitted confirmation must not apply or audit anything a second time");
        assertEquals(1, audit.decisionsFor(p, DOB).size());
    }

    @Test
    @DisplayName("TC-EHR-REC-009 After an accepted date_of_birth, a sync with the same value does not reopen it")
    void acceptedDateOfBirthIsNotReopenedByAnAgreeingSync() {
        Long p = newPatient();
        sync(p, "ATHENAHEALTH", T1, DOB, "1950-05-04");
        sync(p, "EPIC", T1.plus(1, ChronoUnit.DAYS), DOB, "1950-05-06");
        reconciler.finalizePendingDateOfBirth(p, true);

        var again = sync(p, "EPIC", T1.plus(2, ChronoUnit.DAYS), DOB, "1950-05-06");

        assertEquals(ReconciliationOutcome.Decision.ALREADY_AGREED, again.get(0).decision());
        assertTrue(audit.currentPendingConflict(p, DOB).isEmpty());
    }

    @Test
    @DisplayName("TC-EHR-REC-010 After a patient declines, a newer different candidate prompts them again")
    void declinedDateOfBirthCanBeReopenedByANewerCandidate() {
        Long p = newPatient();
        sync(p, "ATHENAHEALTH", T1, DOB, "1950-05-04");
        sync(p, "EPIC", T1.plus(1, ChronoUnit.DAYS), DOB, "1950-05-06");
        reconciler.finalizePendingDateOfBirth(p, false);

        var newer = sync(p, "EPIC", T1.plus(2, ChronoUnit.DAYS), DOB, "1950-05-07");

        // A different value still prompts. The value the patient declined (1950-05-06) does not:
        // that was open question Q3 in the verification report, resolved by TC-EHR-REC-032.
        assertEquals(ReconciliationOutcome.Decision.PENDING_PATIENT_CONFIRMATION, newer.get(0).decision());
        assertEquals(Optional.of("1950-05-04"), value(p, DOB));
    }

    @Test
    @DisplayName("TC-EHR-REC-011 Finding: values differing only in letter case are treated as a disagreement")
    void finding_caseOnlyDifferenceIsADisagreement() {
        Long p = newPatient();
        sync(p, "ATHENAHEALTH", T1, "family_name", "Smith");

        var outcome = sync(p, "EPIC", T1.plus(1, ChronoUnit.DAYS), "family_name", "SMITH");

        // Open question Q1: should "Smith" vs "SMITH" count as agreement? Today it is an ACCEPTED
        // conflict, which overwrites the patient's capitalisation and writes an audit row.
        assertEquals(ReconciliationOutcome.Decision.ACCEPTED_NEWER, outcome.get(0).decision());
        assertEquals(Optional.of("SMITH"), value(p, "family_name"));
    }

    @Test
    @DisplayName("TC-EHR-REC-012 Finding: surrounding whitespace is kept and counts as a disagreement")
    void finding_surroundingWhitespaceIsKept() {
        Long p = newPatient();
        sync(p, "ATHENAHEALTH", T1, "family_name", "Smith");

        var outcome = sync(p, "EPIC", T1.plus(1, ChronoUnit.DAYS), "family_name", " Smith ");

        // Open question Q2: adapters should probably trim before calling reconcile(); today the padded
        // value wins and is stored as-is.
        assertEquals(ReconciliationOutcome.Decision.ACCEPTED_NEWER, outcome.get(0).decision());
        assertEquals(Optional.of(" Smith "), value(p, "family_name"));
    }

    // ---- Testing Lead additions (Kristopher Bickmore, 2026-09-29) ----

    @Test
    @DisplayName("TC-EHR-REC-029 A snapshot with no sourceUpdatedAt is rejected before anything is written")
    void snapshotWithoutSourceTimestampIsRejectedBeforeAnyWrite() {
        Long p = newPatient();

        // The timestamp is what every recency decision hangs on (SourceIdentitySnapshot javadoc). An
        // undated snapshot must not fill a field and leave a provenance row with no timestamp behind.
        assertThrows(NullPointerException.class, () -> sync(p, "EPIC", null, "family_name", "Smith"),
                "an undated snapshot must be refused, not reconciled");
        assertTrue(value(p, "family_name").isEmpty(), "nothing may be written from an undated snapshot");
    }

    @Test
    @DisplayName("TC-EHR-REC-030 A snapshot missing its patient, source or field map is rejected before anything is written")
    void snapshotMissingPatientSourceOrFieldsIsRejectedBeforeAnyWrite() {
        assertThrows(NullPointerException.class, () -> sync(null, "EPIC", T1, "family_name", "Smith"),
                "a snapshot for no patient must be refused");
        assertTrue(value(null, "family_name").isEmpty(), "nothing may be written against a null patient");

        Long p = newPatient();
        assertThrows(NullPointerException.class, () -> sync(p, null, T1, "family_name", "Smith"),
                "a snapshot from no source must be refused: provenance and audit rows need a source");
        assertTrue(value(p, "family_name").isEmpty(), "nothing may be written from an unknown source");

        assertThrows(NullPointerException.class,
                () -> reconciler.reconcile(new SourceIdentitySnapshot(p, sourceId("EPIC"), T1, null)),
                "a snapshot with no field map must be refused");
    }

    @Test
    @DisplayName("TC-EHR-REC-031 Accepting a date_of_birth after a supersede applies the newest candidate and advances provenance to it")
    void acceptingAfterSupersedeAppliesTheNewestCandidate() {
        Long p = newPatient();
        sync(p, "ATHENAHEALTH", T1, DOB, "1950-05-04");
        sync(p, "EPIC", T1.plus(1, ChronoUnit.DAYS), DOB, "1950-05-06");
        sync(p, "ORACLE_HEALTH", T1.plus(3, ChronoUnit.DAYS), DOB, "1950-05-09");

        ReconciliationOutcome finalized = reconciler.finalizePendingDateOfBirth(p, true);

        assertEquals(ReconciliationOutcome.Decision.ACCEPTED_BY_PATIENT, finalized.decision());
        assertEquals("1950-05-09", finalized.appliedValue(),
                "the patient confirms the candidate open now, not the superseded Epic one");
        assertEquals(Optional.of("1950-05-09"), value(p, DOB));

        List<RecordedDecision> decisions = audit.decisionsFor(p, DOB);
        assertEquals(2, decisions.size(), "one row for the superseded candidate, one for the accepted one");
        assertEquals(IdentityConflictAuditWriter.Outcome.REJECTED, decisions.get(0).outcome());
        assertEquals(IdentityConflictAuditWriter.ResolvedBy.SYSTEM, decisions.get(0).resolvedBy());
        assertEquals("1950-05-06", decisions.get(0).incomingValue());
        assertEquals(IdentityConflictAuditWriter.Outcome.ACCEPTED, decisions.get(1).outcome());
        assertEquals(IdentityConflictAuditWriter.ResolvedBy.PATIENT, decisions.get(1).resolvedBy());
        assertEquals("1950-05-09", decisions.get(1).incomingValue());

        // Provenance must now sit at the accepted candidate's timestamp (T1 + 3 days), so a candidate
        // dated between the superseded and the accepted one is stale and does not prompt again.
        var between = sync(p, "EPIC", T1.plus(2, ChronoUnit.DAYS), DOB, "1950-05-06");
        assertEquals(ReconciliationOutcome.Decision.REJECTED_STALE, between.get(0).decision());
        assertTrue(audit.currentPendingConflict(p, DOB).isEmpty());
    }
}
