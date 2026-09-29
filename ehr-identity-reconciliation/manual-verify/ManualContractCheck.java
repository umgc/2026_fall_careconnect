import com.careconnect.ehr.reconciliation.*;
import com.careconnect.ehr.reconciliation.support.*;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Dependency-free stand-in for AbstractIdentityReconciliationContractTest, used only because this
 * sandbox has no network access to Maven Central to pull in JUnit Jupiter for a real `mvn test` run.
 * Exercises the exact same production classes (RecencyWinsIdentityReconciler and friends) and the
 * exact same in-memory fakes the real JUnit contract test uses — this is purely a different test
 * *runner*, not different logic under test. Every scenario here has a 1:1 counterpart method in
 * AbstractIdentityReconciliationContractTest; if you add a scenario to one, add it to the other.
 *
 * <p>2026-09-26 partial reversal: the {@code dateOfBirth*} scenarios below mirror the DOB-specific
 * tests added to the JUnit suite at the same time. The two pre-existing scenarios that used
 * {@code date_of_birth} as an arbitrary field name (baseline-fallback, concurrency) were moved to a
 * different field for the same reason they were moved there — see the comments on each.
 */
public class ManualContractCheck {

    static int passed = 0;
    static int failed = 0;
    static final AtomicLong patientIdSeq = new AtomicLong(1);
    static final String DATE_OF_BIRTH = "date_of_birth";

    public static void main(String[] args) throws Exception {
        run("fillsEmptyFieldDirectlyWithNoAuditRow", ManualContractCheck::fillsEmptyFieldDirectlyWithNoAuditRow);
        run("blankIncomingValueIsIgnoredEntirely", ManualContractCheck::blankIncomingValueIsIgnoredEntirely);
        run("agreeingValuesWriteNoAuditRowButStillAdvanceProvenanceBaseline", ManualContractCheck::agreeingValuesWriteNoAuditRowButStillAdvanceProvenanceBaseline);
        run("acceptsAndAppliesADisagreementThatIsNewerThanTheBaseline", ManualContractCheck::acceptsAndAppliesADisagreementThatIsNewerThanTheBaseline);
        run("rejectsAndDiscardsADisagreementThatIsOlderThanTheBaselineButStillAudits", ManualContractCheck::rejectsAndDiscardsADisagreementThatIsOlderThanTheBaselineButStillAudits);
        run("exactlyEqualTimestampsFavorTheExistingValueDeterministically", ManualContractCheck::exactlyEqualTimestampsFavorTheExistingValueDeterministically);
        run("firstDisagreementWithNoPriorProvenanceFallsBackToPatientUpdatedAt", ManualContractCheck::firstDisagreementWithNoPriorProvenanceFallsBackToPatientUpdatedAt);
        run("concurrentRacingAdaptersConvergeOnTheNewerValueRegardlessOfArrivalOrder", ManualContractCheck::concurrentRacingAdaptersConvergeOnTheNewerValueRegardlessOfArrivalOrder);
        run("dateOfBirthFirstDisagreementWithNoPriorProvenanceAlsoFallsBackToPatientUpdatedAt", ManualContractCheck::dateOfBirthFirstDisagreementWithNoPriorProvenanceAlsoFallsBackToPatientUpdatedAt);
        run("dateOfBirthDisagreementOpensPendingConfirmationInsteadOfAutoApplying", ManualContractCheck::dateOfBirthDisagreementOpensPendingConfirmationInsteadOfAutoApplying);
        run("dateOfBirthCandidateNotNewerThanConfirmedBaselineNeverInterruptsThePatient", ManualContractCheck::dateOfBirthCandidateNotNewerThanConfirmedBaselineNeverInterruptsThePatient);
        run("dateOfBirthPendingConflictIsSupersededByAGenuinelyNewerCandidate", ManualContractCheck::dateOfBirthPendingConflictIsSupersededByAGenuinelyNewerCandidate);
        run("dateOfBirthCandidateNotNewerThanTheOpenPendingOneIsIgnored", ManualContractCheck::dateOfBirthCandidateNotNewerThanTheOpenPendingOneIsIgnored);
        run("finalizingPendingDateOfBirthAsAcceptedAppliesTheValueAndClearsThePending", ManualContractCheck::finalizingPendingDateOfBirthAsAcceptedAppliesTheValueAndClearsThePending);
        run("finalizingPendingDateOfBirthAsRejectedLeavesPatientUnchangedAndClearsThePending", ManualContractCheck::finalizingPendingDateOfBirthAsRejectedLeavesPatientUnchangedAndClearsThePending);
        run("finalizingWithNoPendingConflictThrows", ManualContractCheck::finalizingWithNoPendingConflictThrows);

        System.out.println();
        System.out.println(passed + " passed, " + failed + " failed");
        if (failed > 0) {
            System.exit(1);
        }
    }

    interface Scenario {
        void run() throws Exception;
    }

    static void run(String name, Scenario s) {
        try {
            s.run();
            System.out.println("PASS - " + name);
            passed++;
        } catch (Throwable t) {
            System.out.println("FAIL - " + name + " -> " + t);
            t.printStackTrace();
            failed++;
        }
    }

    // ---- fixture ----

    static final class Fixture {
        final InMemoryProvenanceStore provenanceStore = new InMemoryProvenanceStore();
        final InMemoryPatientAccessor patientAccessor = new InMemoryPatientAccessor();
        final InMemoryAuditWriter auditWriter = new InMemoryAuditWriter();
        final IdentityReconciler reconciler = new RecencyWinsIdentityReconciler(
                provenanceStore, patientAccessor, auditWriter, new InMemoryTransactionRunner());
        final
        Object freshPatientId() {
            return patientIdSeq.getAndIncrement();
        }

        Object source(String code) {
            return code;
        }

        SourceIdentitySnapshot snapshot(Object patientId, Object sourceId, Instant t, String field, String value) {
            return new SourceIdentitySnapshot(patientId, sourceId, t, Map.of(field, value));
        }
    }

    // ---- assertions ----

    static void assertEquals(Object expected, Object actual, String msg) {
        if (!java.util.Objects.equals(expected, actual)) {
            throw new AssertionError(msg + " -- expected <" + expected + "> but was <" + actual + ">");
        }
    }

    static void assertTrue(boolean cond, String msg) {
        if (!cond) throw new AssertionError(msg);
    }

    static void assertThrows(Class<? extends Throwable> expected, Runnable r, String msg) {
        try {
            r.run();
        } catch (Throwable t) {
            if (expected.isInstance(t)) {
                return;
            }
            throw new AssertionError(msg + " -- wrong exception type: " + t);
        }
        throw new AssertionError(msg + " -- expected " + expected.getSimpleName() + " but nothing was thrown");
    }

    // ---- scenarios (mirrors AbstractIdentityReconciliationContractTest 1:1) ----

    static void fillsEmptyFieldDirectlyWithNoAuditRow() {
        Fixture f = new Fixture();
        Object patientId = f.freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");

        var outcomes = f.reconciler.reconcile(f.snapshot(patientId, f.source("ATHENAHEALTH"), t1, DATE_OF_BIRTH, "1950-05-04"));

        assertEquals(ReconciliationOutcome.Decision.FILLED_EMPTY, outcomes.get(0).decision(), "decision");
        assertEquals(Optional.of("1950-05-04"), f.patientAccessor.getCurrentValue(patientId, DATE_OF_BIRTH), "patient value");
        assertTrue(f.auditWriter.decisionsFor(patientId, DATE_OF_BIRTH).isEmpty(), "no audit row for fill-empty");
    }

    static void blankIncomingValueIsIgnoredEntirely() {
        Fixture f = new Fixture();
        Object patientId = f.freshPatientId();
        var outcomes = f.reconciler.reconcile(f.snapshot(patientId, f.source("EPIC"), Instant.parse("2026-01-01T00:00:00Z"), "phone", "   "));
        assertTrue(outcomes.isEmpty(), "blank incoming must be skipped");
        assertTrue(f.patientAccessor.getCurrentValue(patientId, "phone").isEmpty(), "phone must remain empty");
    }

    static void agreeingValuesWriteNoAuditRowButStillAdvanceProvenanceBaseline() {
        Fixture f = new Fixture();
        Object patientId = f.freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");
        Instant t2 = t1.plus(10, ChronoUnit.DAYS);
        Instant t3 = t1.plus(5, ChronoUnit.DAYS);

        f.reconciler.reconcile(f.snapshot(patientId, f.source("ATHENAHEALTH"), t1, "address_line1", "123 Main St"));
        var agree = f.reconciler.reconcile(f.snapshot(patientId, f.source("EPIC"), t2, "address_line1", "123 Main St"));
        assertEquals(ReconciliationOutcome.Decision.ALREADY_AGREED, agree.get(0).decision(), "agree decision");
        assertTrue(f.auditWriter.decisionsFor(patientId, "address_line1").isEmpty(), "no audit row for agreement");

        var stale = f.reconciler.reconcile(f.snapshot(patientId, f.source("ORACLE_HEALTH"), t3, "address_line1", "456 Oak Ave"));
        assertEquals(ReconciliationOutcome.Decision.REJECTED_STALE, stale.get(0).decision(),
                "must be stale against the advanced (t2) baseline, not t1");
        assertEquals(Optional.of("123 Main St"), f.patientAccessor.getCurrentValue(patientId, "address_line1"), "value unchanged");
    }

    static void acceptsAndAppliesADisagreementThatIsNewerThanTheBaseline() {
        Fixture f = new Fixture();
        Object patientId = f.freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");
        Instant t2 = t1.plus(1, ChronoUnit.DAYS);

        f.reconciler.reconcile(f.snapshot(patientId, f.source("ATHENAHEALTH"), t1, "family_name", "Smith"));
        var outcomes = f.reconciler.reconcile(f.snapshot(patientId, f.source("EPIC"), t2, "family_name", "Smyth"));

        assertEquals(ReconciliationOutcome.Decision.ACCEPTED_NEWER, outcomes.get(0).decision(), "decision");
        assertEquals(Optional.of("Smyth"), f.patientAccessor.getCurrentValue(patientId, "family_name"), "patient value");

        List<RecordedDecision> decisions = f.auditWriter.decisionsFor(patientId, "family_name");
        assertEquals(1, decisions.size(), "one audit row");
        assertEquals(IdentityConflictAuditWriter.Outcome.ACCEPTED, decisions.get(0).outcome(), "outcome");
        assertEquals(IdentityConflictAuditWriter.ResolvedBy.SYSTEM, decisions.get(0).resolvedBy(), "resolvedBy");
        assertEquals("Smith", decisions.get(0).canonicalValueBefore(), "before");
        assertEquals("Smyth", decisions.get(0).incomingValue(), "incoming");
    }

    static void rejectsAndDiscardsADisagreementThatIsOlderThanTheBaselineButStillAudits() {
        Fixture f = new Fixture();
        Object patientId = f.freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");
        Instant older = t1.minus(1, ChronoUnit.DAYS);

        f.reconciler.reconcile(f.snapshot(patientId, f.source("ATHENAHEALTH"), t1, "family_name", "Smith"));
        var outcomes = f.reconciler.reconcile(f.snapshot(patientId, f.source("EPIC"), older, "family_name", "Smyth"));

        assertEquals(ReconciliationOutcome.Decision.REJECTED_STALE, outcomes.get(0).decision(), "decision");
        assertEquals(Optional.of("Smith"), f.patientAccessor.getCurrentValue(patientId, "family_name"), "value must not change");

        List<RecordedDecision> decisions = f.auditWriter.decisionsFor(patientId, "family_name");
        assertEquals(1, decisions.size(), "rejected must still be audited");
        assertEquals(IdentityConflictAuditWriter.Outcome.REJECTED, decisions.get(0).outcome(), "outcome");
    }

    static void exactlyEqualTimestampsFavorTheExistingValueDeterministically() {
        Fixture f = new Fixture();
        Object patientId = f.freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");

        f.reconciler.reconcile(f.snapshot(patientId, f.source("ATHENAHEALTH"), t1, "family_name", "Smith"));
        var outcomes = f.reconciler.reconcile(f.snapshot(patientId, f.source("EPIC"), t1, "family_name", "Smyth"));

        assertEquals(ReconciliationOutcome.Decision.REJECTED_STALE, outcomes.get(0).decision(), "tie must favor existing");
        assertEquals(Optional.of("Smith"), f.patientAccessor.getCurrentValue(patientId, "family_name"), "value unchanged");
    }

    // Uses "email" rather than date_of_birth (which this scenario used before the DOB reversal): this
    // is about Assumption A1's baseline fallback for an ordinary field, and asserts ACCEPTED_NEWER /
    // REJECTED_STALE outcomes date_of_birth can no longer return for a genuine disagreement.
    static void firstDisagreementWithNoPriorProvenanceFallsBackToPatientUpdatedAt() {
        Fixture f = new Fixture();
        Object patientId = f.freshPatientId();
        Instant patientEditedAt = Instant.parse("2026-06-01T00:00:00Z");
        f.patientAccessor.seedPatientUpdatedAt(patientId, patientEditedAt);
        f.patientAccessor.applyValue(patientId, "email", "old@example.com");

        Instant olderThanEdit = patientEditedAt.minus(30, ChronoUnit.DAYS);
        Instant newerThanEdit = patientEditedAt.plus(1, ChronoUnit.DAYS);

        var stale = f.reconciler.reconcile(f.snapshot(patientId, f.source("ATHENAHEALTH"), olderThanEdit, "email", "stale@example.com"));
        assertEquals(ReconciliationOutcome.Decision.REJECTED_STALE, stale.get(0).decision(), "older than patient.updated_at must lose");

        var fresh = f.reconciler.reconcile(f.snapshot(patientId, f.source("EPIC"), newerThanEdit, "email", "fresh@example.com"));
        assertEquals(ReconciliationOutcome.Decision.ACCEPTED_NEWER, fresh.get(0).decision(), "newer than patient.updated_at must win");
        assertEquals(Optional.of("fresh@example.com"), f.patientAccessor.getCurrentValue(patientId, "email"), "value applied");
    }

    /**
     * The scenario has to be chosen carefully: BOTH racing timestamps must independently beat the
     * ORIGINAL baseline for this to actually exercise the lock. If one racer's timestamp were a tie or
     * a loss against the original baseline, it would deterministically lose regardless of locking, and
     * the test would pass "by luck" even with a broken (non-locking) store — see UnsafeProvenanceStore
     * for the adversarial run that proves this scenario has teeth.
     *
     * <p>Uses "family_name" rather than date_of_birth (which this scenario used before the DOB
     * reversal) for the same reason as the JUnit counterpart above.
     */
    static void concurrentRacingAdaptersConvergeOnTheNewerValueRegardlessOfArrivalOrder() throws InterruptedException {
        Fixture f = new Fixture();
        Object patientId = f.freshPatientId();
        Instant baseline = Instant.parse("2026-01-01T00:00:00Z");
        Instant middle = baseline.plus(1, ChronoUnit.DAYS);   // beats baseline, loses to `latest`
        Instant latest = baseline.plus(2, ChronoUnit.DAYS);   // beats both

        f.reconciler.reconcile(f.snapshot(patientId, f.source("ATHENAHEALTH"), baseline, "family_name", "Alpha"));
        race(f, patientId, f.source("ORACLE_HEALTH"), middle, "Middle", f.source("EPIC"), latest, "Latest", "family_name");

        assertEquals(Optional.of("Latest"), f.patientAccessor.getCurrentValue(patientId, "family_name"),
                "only the genuinely newest (latest-timestamped) value may win, regardless of thread interleaving");
    }

    // ---- date_of_birth-specific scenarios (2026-09-26 partial reversal) ----

    static void dateOfBirthFirstDisagreementWithNoPriorProvenanceAlsoFallsBackToPatientUpdatedAt() {
        Fixture f = new Fixture();
        Object patientId = f.freshPatientId();
        Instant patientEditedAt = Instant.parse("2026-06-01T00:00:00Z");
        f.patientAccessor.seedPatientUpdatedAt(patientId, patientEditedAt);
        f.patientAccessor.applyValue(patientId, DATE_OF_BIRTH, "1950-05-04");

        Instant olderThanEdit = patientEditedAt.minus(30, ChronoUnit.DAYS);
        var stale = f.reconciler.reconcile(f.snapshot(patientId, f.source("ATHENAHEALTH"), olderThanEdit, DATE_OF_BIRTH, "1950-05-05"));
        assertEquals(ReconciliationOutcome.Decision.REJECTED_STALE, stale.get(0).decision(),
                "older than patient.updated_at must lose outright, same as any other field");
        assertTrue(f.auditWriter.currentPendingConflict(patientId, DATE_OF_BIRTH).isEmpty(), "must never become PENDING");

        Instant newerThanEdit = patientEditedAt.plus(1, ChronoUnit.DAYS);
        var fresh = f.reconciler.reconcile(f.snapshot(patientId, f.source("EPIC"), newerThanEdit, DATE_OF_BIRTH, "1950-05-06"));
        assertEquals(ReconciliationOutcome.Decision.PENDING_PATIENT_CONFIRMATION, fresh.get(0).decision(),
                "newer makes it a genuine candidate, but DOB never auto-applies");
        assertEquals(Optional.of("1950-05-04"), f.patientAccessor.getCurrentValue(patientId, DATE_OF_BIRTH), "must stay untouched");
    }

    static void dateOfBirthDisagreementOpensPendingConfirmationInsteadOfAutoApplying() {
        Fixture f = new Fixture();
        Object patientId = f.freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");
        Instant t2 = t1.plus(1, ChronoUnit.DAYS);
        Object epic = f.source("EPIC");

        f.reconciler.reconcile(f.snapshot(patientId, f.source("ATHENAHEALTH"), t1, DATE_OF_BIRTH, "1950-05-04"));
        var outcomes = f.reconciler.reconcile(f.snapshot(patientId, epic, t2, DATE_OF_BIRTH, "1950-05-06"));

        assertEquals(ReconciliationOutcome.Decision.PENDING_PATIENT_CONFIRMATION, outcomes.get(0).decision(), "decision");
        assertEquals("1950-05-06", outcomes.get(0).appliedValue(), "appliedValue is the candidate, not something applied");
        assertEquals(Optional.of("1950-05-04"), f.patientAccessor.getCurrentValue(patientId, DATE_OF_BIRTH), "patient value untouched");
        assertTrue(f.auditWriter.decisionsFor(patientId, DATE_OF_BIRTH).isEmpty(), "PENDING is not a finalized decision");

        var pending = f.auditWriter.currentPendingConflict(patientId, DATE_OF_BIRTH);
        assertTrue(pending.isPresent(), "must be discoverable as PENDING");
        assertEquals(epic, pending.get().sourceId(), "pending sourceId");
        assertEquals("1950-05-04", pending.get().canonicalValueBefore(), "pending before");
        assertEquals("1950-05-06", pending.get().incomingValue(), "pending incoming");
    }

    static void dateOfBirthCandidateNotNewerThanConfirmedBaselineNeverInterruptsThePatient() {
        Fixture f = new Fixture();
        Object patientId = f.freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");
        Instant tOlder = t1.minus(1, ChronoUnit.DAYS);

        f.reconciler.reconcile(f.snapshot(patientId, f.source("ATHENAHEALTH"), t1, DATE_OF_BIRTH, "1950-05-04"));
        var outcomes = f.reconciler.reconcile(f.snapshot(patientId, f.source("EPIC"), tOlder, DATE_OF_BIRTH, "1950-05-09"));

        assertEquals(ReconciliationOutcome.Decision.REJECTED_STALE, outcomes.get(0).decision(),
                "a candidate that couldn't have won under the ordinary recency rule must not prompt the patient");
        assertEquals(Optional.of("1950-05-04"), f.patientAccessor.getCurrentValue(patientId, DATE_OF_BIRTH), "value unchanged");
        assertTrue(f.auditWriter.currentPendingConflict(patientId, DATE_OF_BIRTH).isEmpty(), "no pending conflict opened");

        List<RecordedDecision> decisions = f.auditWriter.decisionsFor(patientId, DATE_OF_BIRTH);
        assertEquals(1, decisions.size(), "still audited, like a rejected non-DOB disagreement");
        assertEquals(IdentityConflictAuditWriter.Outcome.REJECTED, decisions.get(0).outcome(), "outcome");
        assertEquals(IdentityConflictAuditWriter.ResolvedBy.SYSTEM, decisions.get(0).resolvedBy(), "resolvedBy");
    }

    static void dateOfBirthPendingConflictIsSupersededByAGenuinelyNewerCandidate() {
        Fixture f = new Fixture();
        Object patientId = f.freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");
        Instant t2 = t1.plus(1, ChronoUnit.DAYS);
        Instant t3 = t1.plus(2, ChronoUnit.DAYS);
        Object oracle = f.source("ORACLE_HEALTH");

        f.reconciler.reconcile(f.snapshot(patientId, f.source("ATHENAHEALTH"), t1, DATE_OF_BIRTH, "1950-05-04"));
        f.reconciler.reconcile(f.snapshot(patientId, f.source("EPIC"), t2, DATE_OF_BIRTH, "1950-05-06"));
        var supersede = f.reconciler.reconcile(f.snapshot(patientId, oracle, t3, DATE_OF_BIRTH, "1950-05-09"));

        assertEquals(ReconciliationOutcome.Decision.PENDING_PATIENT_CONFIRMATION, supersede.get(0).decision(), "decision");
        var pending = f.auditWriter.currentPendingConflict(patientId, DATE_OF_BIRTH);
        assertTrue(pending.isPresent(), "must have a pending conflict");
        assertEquals("1950-05-09", pending.get().incomingValue(), "pending must be the newest candidate");
        assertEquals(oracle, pending.get().sourceId(), "pending sourceId");

        List<RecordedDecision> decisions = f.auditWriter.decisionsFor(patientId, DATE_OF_BIRTH);
        assertEquals(1, decisions.size(), "the superseded candidate must be closed out, not left dangling");
        assertEquals(IdentityConflictAuditWriter.Outcome.REJECTED, decisions.get(0).outcome(), "superseded outcome");
        assertEquals(IdentityConflictAuditWriter.ResolvedBy.SYSTEM, decisions.get(0).resolvedBy(),
                "the system superseded it, not the patient");
        assertEquals("1950-05-06", decisions.get(0).incomingValue(), "superseded value");
        assertEquals(Optional.of("1950-05-04"), f.patientAccessor.getCurrentValue(patientId, DATE_OF_BIRTH), "patient value untouched throughout");
    }

    static void dateOfBirthCandidateNotNewerThanTheOpenPendingOneIsIgnored() {
        Fixture f = new Fixture();
        Object patientId = f.freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");
        Instant t3 = t1.plus(3, ChronoUnit.DAYS);
        Instant t2BetweenT1AndT3 = t1.plus(1, ChronoUnit.DAYS);

        f.reconciler.reconcile(f.snapshot(patientId, f.source("ATHENAHEALTH"), t1, DATE_OF_BIRTH, "1950-05-04"));
        f.reconciler.reconcile(f.snapshot(patientId, f.source("EPIC"), t3, DATE_OF_BIRTH, "1950-05-09"));
        var ignored = f.reconciler.reconcile(f.snapshot(patientId, f.source("ORACLE_HEALTH"), t2BetweenT1AndT3, DATE_OF_BIRTH, "1950-05-06"));

        assertEquals(ReconciliationOutcome.Decision.REJECTED_STALE, ignored.get(0).decision(), "decision");
        var pending = f.auditWriter.currentPendingConflict(patientId, DATE_OF_BIRTH);
        assertTrue(pending.isPresent(), "must still have a pending conflict");
        assertEquals("1950-05-09", pending.get().incomingValue(), "original (Epic, t3) candidate must remain pending, untouched");
    }

    static void finalizingPendingDateOfBirthAsAcceptedAppliesTheValueAndClearsThePending() {
        Fixture f = new Fixture();
        Object patientId = f.freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");
        Instant t2 = t1.plus(1, ChronoUnit.DAYS);

        f.reconciler.reconcile(f.snapshot(patientId, f.source("ATHENAHEALTH"), t1, DATE_OF_BIRTH, "1950-05-04"));
        f.reconciler.reconcile(f.snapshot(patientId, f.source("EPIC"), t2, DATE_OF_BIRTH, "1950-05-06"));

        var finalized = f.reconciler.finalizePendingDateOfBirth(patientId, true);

        assertEquals(ReconciliationOutcome.Decision.ACCEPTED_BY_PATIENT, finalized.decision(), "decision");
        assertEquals("1950-05-06", finalized.appliedValue(), "applied value");
        assertEquals(Optional.of("1950-05-06"), f.patientAccessor.getCurrentValue(patientId, DATE_OF_BIRTH), "patient value updated");
        assertTrue(f.auditWriter.currentPendingConflict(patientId, DATE_OF_BIRTH).isEmpty(), "pending cleared");

        List<RecordedDecision> decisions = f.auditWriter.decisionsFor(patientId, DATE_OF_BIRTH);
        assertEquals(1, decisions.size(), "one finalized row");
        assertEquals(IdentityConflictAuditWriter.Outcome.ACCEPTED, decisions.get(0).outcome(), "outcome");
        assertEquals(IdentityConflictAuditWriter.ResolvedBy.PATIENT, decisions.get(0).resolvedBy(), "resolvedBy");

        var staleAfterAccept = f.reconciler.reconcile(
                f.snapshot(patientId, f.source("ORACLE_HEALTH"), t1.plus(12, ChronoUnit.HOURS), DATE_OF_BIRTH, "1950-05-11"));
        assertEquals(ReconciliationOutcome.Decision.REJECTED_STALE, staleAfterAccept.get(0).decision(),
                "provenance must have advanced to t2 on acceptance, not stayed at t1");
    }

    static void finalizingPendingDateOfBirthAsRejectedLeavesPatientUnchangedAndClearsThePending() {
        Fixture f = new Fixture();
        Object patientId = f.freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");
        Instant t2 = t1.plus(1, ChronoUnit.DAYS);

        f.reconciler.reconcile(f.snapshot(patientId, f.source("ATHENAHEALTH"), t1, DATE_OF_BIRTH, "1950-05-04"));
        f.reconciler.reconcile(f.snapshot(patientId, f.source("EPIC"), t2, DATE_OF_BIRTH, "1950-05-06"));

        var finalized = f.reconciler.finalizePendingDateOfBirth(patientId, false);

        assertEquals(ReconciliationOutcome.Decision.REJECTED_BY_PATIENT, finalized.decision(), "decision");
        assertEquals("1950-05-04", finalized.appliedValue(), "reports what patient still holds");
        assertEquals(Optional.of("1950-05-04"), f.patientAccessor.getCurrentValue(patientId, DATE_OF_BIRTH), "value unchanged");
        assertTrue(f.auditWriter.currentPendingConflict(patientId, DATE_OF_BIRTH).isEmpty(), "pending cleared");

        List<RecordedDecision> decisions = f.auditWriter.decisionsFor(patientId, DATE_OF_BIRTH);
        assertEquals(1, decisions.size(), "one finalized row");
        assertEquals(IdentityConflictAuditWriter.Outcome.REJECTED, decisions.get(0).outcome(), "outcome");
        assertEquals(IdentityConflictAuditWriter.ResolvedBy.PATIENT, decisions.get(0).resolvedBy(), "must be PATIENT, not SYSTEM");
    }

    static void finalizingWithNoPendingConflictThrows() {
        Fixture f = new Fixture();
        Object patientId = f.freshPatientId();
        assertThrows(IllegalStateException.class,
                () -> f.reconciler.finalizePendingDateOfBirth(patientId, true),
                "nothing to finalize when no conflict is open");
    }

    static void race(Fixture f, Object patientId, Object sourceA, Instant tA, String valueA,
                      Object sourceB, Instant tB, String valueB, String field) throws InterruptedException {
        ExecutorService pool = Executors.newFixedThreadPool(2);
        CountDownLatch bothReady = new CountDownLatch(2);
        CountDownLatch go = new CountDownLatch(1);

        Runnable a = () -> {
            bothReady.countDown();
            awaitQuietly(go);
            f.reconciler.reconcile(f.snapshot(patientId, sourceA, tA, field, valueA));
        };
        Runnable b = () -> {
            bothReady.countDown();
            awaitQuietly(go);
            f.reconciler.reconcile(f.snapshot(patientId, sourceB, tB, field, valueB));
        };

        pool.submit(a);
        pool.submit(b);
        bothReady.await(5, TimeUnit.SECONDS);
        go.countDown(); // release both at once to maximize interleaving
        pool.shutdown();
        assertTrue(pool.awaitTermination(10, TimeUnit.SECONDS), "tasks finished in time");
    }

    static void awaitQuietly(CountDownLatch latch) {
        try {
            latch.await(5, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
