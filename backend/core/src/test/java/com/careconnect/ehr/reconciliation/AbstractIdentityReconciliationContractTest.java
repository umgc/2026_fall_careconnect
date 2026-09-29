package com.careconnect.ehr.reconciliation;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;

/**
 * The contract every implementation of the identity-reconciliation pattern must satisfy — extend this
 * with your own {@link IdentityFieldProvenanceStore}/{@link PatientFieldAccessor}/
 * {@link IdentityConflictAuditWriter}/{@link TransactionRunner} wired to your real database, and every
 * test below runs against your implementation. This is the mechanism referenced in the implementation
 * plan's Phase 0 deliverable: circulating this class to Teams C/D/E means they inherit the same
 * correctness assertions this library was built to guarantee, rather than writing their own tests
 * against their own possibly-incorrect reading of the spec.
 *
 * <p><b>2026-09-26 partial reversal:</b> the {@code date_of_birth}-specific tests below
 * ({@code dateOfBirth*}) are new, added alongside the code change described in the implementation
 * plan's Decisions log. Every pre-existing test that used {@code date_of_birth} purely as an arbitrary
 * field name for a scenario that has nothing to do with DOB specifically (the baseline-fallback and
 * concurrency tests) was moved to a different field, since {@code date_of_birth} no longer behaves like
 * an arbitrary field for a genuine disagreement — see the comments on those two tests.
 *
 * <p>Three things every subclass must provide beyond the four production interfaces, purely for test
 * arrangement/assertion (a real DB-backed subclass typically implements these with a direct SQL
 * insert/select against its own test schema, or by delegating to the same interfaces where a
 * production method already does the job):
 * <ul>
 *   <li>{@link #seedPatientUpdatedAt} — arrange {@code patient.updated_at}, since no production
 *       interface method writes it (the real column is maintained by whatever already updates
 *       {@code patient}, not by this library).</li>
 *   <li>{@link #decisionsFor} — read back what {@link IdentityConflictAuditWriter} recorded, as
 *       {@link RecordedDecision}s, for assertions.</li>
 *   <li>{@link #auditWriter} — expose the same {@link IdentityConflictAuditWriter} instance the
 *       reconciler under test is wired to, so the {@code date_of_birth} tests can assert on
 *       {@link IdentityConflictAuditWriter#currentPendingConflict} directly rather than needing a
 *       third read-side abstraction.</li>
 * </ul>
 */
public abstract class AbstractIdentityReconciliationContractTest {

    private static final String DATE_OF_BIRTH = "date_of_birth";

    protected abstract IdentityReconciler reconciler();

    protected abstract PatientFieldAccessor patientAccessor();

    protected abstract IdentityConflictAuditWriter auditWriter();

    protected abstract void seedPatientUpdatedAt(Object patientId, Instant instant);

    protected abstract List<RecordedDecision> decisionsFor(Object patientId, String fieldName);

    /** A fresh, distinct patient id for each test, so tests never share state. Implement with a counter/UUID. */
    protected abstract Object freshPatientId();


    protected abstract Object sourceId(String sourceCode);

    private static SourceIdentitySnapshot snapshot(Object patientId, Object sourceId,
                                                     Instant sourceUpdatedAt, String fieldName, String value) {
        return new SourceIdentitySnapshot(patientId, sourceId, sourceUpdatedAt,
                java.util.Map.of(fieldName, value));
    }

    @Test
    void fillsEmptyFieldDirectlyWithNoAuditRow() {
        Object patientId = freshPatientId();
        Object athena = sourceId("ATHENAHEALTH");
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");

        // date_of_birth deliberately, to also prove the fill-empty rule is unaffected by the DOB
        // carve-out below (there's no disagreement to hold PENDING when nothing was there to disagree with).
        var outcomes = reconciler().reconcile(snapshot(patientId, athena, t1, DATE_OF_BIRTH, "1950-05-04"));

        assertEquals(ReconciliationOutcome.Decision.FILLED_EMPTY, outcomes.get(0).decision());
        assertEquals(Optional.of("1950-05-04"), patientAccessor().getCurrentValue(patientId, DATE_OF_BIRTH));
        assertTrue(decisionsFor(patientId, DATE_OF_BIRTH).isEmpty(),
                "filling an empty field is not a conflict and must not write an audit row");
    }

    @Test
    void blankIncomingValueIsIgnoredEntirely() {
        Object patientId = freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");

        var outcomes = reconciler().reconcile(snapshot(patientId, sourceId("EPIC"), t1, "phone", "   "));

        assertTrue(outcomes.isEmpty(), "a blank incoming value must be skipped, not applied as blank");
        assertTrue(patientAccessor().getCurrentValue(patientId, "phone").isEmpty());
    }

    @Test
    void agreeingValuesWriteNoAuditRowButStillAdvanceProvenanceBaseline() {
        Object patientId = freshPatientId();
        Object athena = sourceId("ATHENAHEALTH");
        Object epic = sourceId("EPIC");
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");
        Instant t2 = t1.plus(10, ChronoUnit.DAYS);
        Instant t3BetweenT1AndT2 = t1.plus(5, ChronoUnit.DAYS);

        // Athenahealth fills the field first.
        reconciler().reconcile(snapshot(patientId, athena, t1, "address_line1", "123 Main St"));
        // Epic syncs later with the SAME value -> "agree" branch; must still push the provenance
        // baseline forward to t2, not leave it at t1.
        var agreeOutcomes = reconciler().reconcile(snapshot(patientId, epic, t2, "address_line1", "123 Main St"));
        assertEquals(ReconciliationOutcome.Decision.ALREADY_AGREED, agreeOutcomes.get(0).decision());
        assertTrue(decisionsFor(patientId, "address_line1").isEmpty());

        // A third source disagrees, timestamped BETWEEN t1 and t2. If the baseline correctly advanced
        // to t2 on the agreement above, this must be rejected as stale even though it's newer than t1.
        var staleOutcomes = reconciler().reconcile(
                snapshot(patientId, sourceId("ORACLE_HEALTH"), t3BetweenT1AndT2, "address_line1", "456 Oak Ave"));

        assertEquals(ReconciliationOutcome.Decision.REJECTED_STALE, staleOutcomes.get(0).decision());
        assertEquals(Optional.of("123 Main St"), patientAccessor().getCurrentValue(patientId, "address_line1"));
    }

    @Test
    void acceptsAndAppliesADisagreementThatIsNewerThanTheBaseline() {
        Object patientId = freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");
        Instant t2 = t1.plus(1, ChronoUnit.DAYS);

        reconciler().reconcile(snapshot(patientId, sourceId("ATHENAHEALTH"), t1, "family_name", "Smith"));
        var outcomes = reconciler().reconcile(snapshot(patientId, sourceId("EPIC"), t2, "family_name", "Smyth"));

        assertEquals(ReconciliationOutcome.Decision.ACCEPTED_NEWER, outcomes.get(0).decision());
        assertEquals(Optional.of("Smyth"), patientAccessor().getCurrentValue(patientId, "family_name"));

        List<RecordedDecision> decisions = decisionsFor(patientId, "family_name");
        assertEquals(1, decisions.size());
        assertEquals(IdentityConflictAuditWriter.Outcome.ACCEPTED, decisions.get(0).outcome());
        assertEquals(IdentityConflictAuditWriter.ResolvedBy.SYSTEM, decisions.get(0).resolvedBy());
        assertEquals("Smith", decisions.get(0).canonicalValueBefore());
        assertEquals("Smyth", decisions.get(0).incomingValue());
    }

    @Test
    void rejectsAndDiscardsADisagreementThatIsOlderThanTheBaselineButStillAudits() {
        Object patientId = freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");
        Instant tOlder = t1.minus(1, ChronoUnit.DAYS);

        reconciler().reconcile(snapshot(patientId, sourceId("ATHENAHEALTH"), t1, "family_name", "Smith"));
        var outcomes = reconciler().reconcile(snapshot(patientId, sourceId("EPIC"), tOlder, "family_name", "Smyth"));

        assertEquals(ReconciliationOutcome.Decision.REJECTED_STALE, outcomes.get(0).decision());
        assertEquals(Optional.of("Smith"), patientAccessor().getCurrentValue(patientId, "family_name"),
                "a stale disagreement must never overwrite patient");

        List<RecordedDecision> decisions = decisionsFor(patientId, "family_name");
        assertEquals(1, decisions.size(), "a rejected disagreement must still be audited, not silently dropped");
        assertEquals(IdentityConflictAuditWriter.Outcome.REJECTED, decisions.get(0).outcome());
    }

    @Test
    void exactlyEqualTimestampsFavorTheExistingValueDeterministically() {
        Object patientId = freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");

        reconciler().reconcile(snapshot(patientId, sourceId("ATHENAHEALTH"), t1, "family_name", "Smith"));
        var outcomes = reconciler().reconcile(snapshot(patientId, sourceId("EPIC"), t1, "family_name", "Smyth"));

        assertEquals(ReconciliationOutcome.Decision.REJECTED_STALE, outcomes.get(0).decision(),
                "a tie must not flip the existing value (Assumption A2)");
        assertEquals(Optional.of("Smith"), patientAccessor().getCurrentValue(patientId, "family_name"));
    }

    @Test
    void firstDisagreementWithNoPriorProvenanceFallsBackToPatientUpdatedAt() {
        // Uses "email" rather than date_of_birth (which this scenario used before the DOB reversal):
        // this test is about Assumption A1's baseline fallback for an ordinary field, and asserts
        // ACCEPTED_NEWER/REJECTED_STALE outcomes that date_of_birth can no longer return for a genuine
        // disagreement. See dateOfBirthFirstDisagreementWithNoPriorProvenanceAlsoFallsBackToPatientUpdatedAt
        // below for the DOB-specific equivalent of this same assumption.
        Object patientId = freshPatientId();
        Instant patientEditedAt = Instant.parse("2026-06-01T00:00:00Z");
        seedPatientUpdatedAt(patientId, patientEditedAt);

        // A value is present on patient but was never established through this library (e.g. entered
        // at signup), so there is no ehr_identity_field_provenance row for it yet.
        // Subclasses seed this via patientAccessor().applyValue directly, matching how a real
        // signup-entered value would exist on patient with no prior reconciliation history.
        patientAccessor().applyValue(patientId, "email", "old@example.com");

        Instant olderThanEdit = patientEditedAt.minus(30, ChronoUnit.DAYS);
        Instant newerThanEdit = patientEditedAt.plus(1, ChronoUnit.DAYS);

        var staleAttempt = reconciler().reconcile(
                snapshot(patientId, sourceId("ATHENAHEALTH"), olderThanEdit, "email", "stale@example.com"));
        assertEquals(ReconciliationOutcome.Decision.REJECTED_STALE, staleAttempt.get(0).decision(),
                "an incoming timestamp older than patient.updated_at must lose (Assumption A1)");

        var freshAttempt = reconciler().reconcile(
                snapshot(patientId, sourceId("EPIC"), newerThanEdit, "email", "fresh@example.com"));
        assertEquals(ReconciliationOutcome.Decision.ACCEPTED_NEWER, freshAttempt.get(0).decision(),
                "an incoming timestamp newer than patient.updated_at must win (Assumption A1)");
        assertEquals(Optional.of("fresh@example.com"), patientAccessor().getCurrentValue(patientId, "email"));
    }

    /**
     * The property the provenance-row lock exists to guarantee: two adapters racing on the same field
     * converge to the correct (newest-timestamped) winner regardless of which thread's database write
     * actually lands first. This is the test that fails under a naive
     * "read-compare-in-application-code-then-write" implementation without a row lock — see
     * {@link IdentityFieldProvenanceStore}'s javadoc, and this sandbox's manual verification run
     * (ManualContractCheck vs. UnsafeProvenanceStore) for a demonstration that it actually does.
     *
     * <p>Uses "family_name" rather than date_of_birth (which this scenario used before the DOB
     * reversal): this test asserts an applied, converged value, which date_of_birth can no longer
     * produce for a genuine disagreement between two other sources. See
     * {@code AdversarialCheck}'s date-of-birth section for the DOB-specific equivalent of this same
     * concurrency guarantee (converging on which candidate ends up PENDING, not which value gets applied).
     *
     * <p>The scenario matters: both racing timestamps must independently beat the ORIGINAL baseline,
     * or one of them would deterministically lose regardless of locking and the test would pass by
     * luck even against a broken store. Concretely: baseline at t0; racer A at t1; racer B at t2, with
     * t0 &lt; t1 &lt; t2. Without the lock, both threads can read the stale t0 baseline before either
     * writes, both independently conclude "I'm newer than t0, I win," and then whichever thread's
     * write physically lands last decides the outcome — which may be A's (t1), even though B (t2) is
     * the genuinely newer source. The lock forces whichever thread runs second to compare against the
     * first thread's already-applied result, not the stale original baseline.
     */
    @Test
    void concurrentRacingAdaptersConvergeOnTheNewerValueRegardlessOfArrivalOrder() throws InterruptedException {
        Object patientId = freshPatientId();
        Instant baseline = Instant.parse("2026-01-01T00:00:00Z");
        Instant middle = baseline.plus(1, ChronoUnit.DAYS);   // beats baseline, loses to `latest`
        Instant latest = baseline.plus(2, ChronoUnit.DAYS);   // beats both

        reconciler().reconcile(snapshot(patientId, sourceId("ATHENAHEALTH"), baseline, "family_name", "Alpha"));

        ExecutorService pool = Executors.newFixedThreadPool(2);
        CountDownLatch bothReady = new CountDownLatch(2);
        CountDownLatch go = new CountDownLatch(1);

        Runnable middleRewrite = () -> {
            bothReady.countDown();
            awaitQuietly(go);
            reconciler().reconcile(snapshot(patientId, sourceId("ORACLE_HEALTH"), middle, "family_name", "Middle"));
        };
        Runnable latestRewrite = () -> {
            bothReady.countDown();
            awaitQuietly(go);
            reconciler().reconcile(snapshot(patientId, sourceId("EPIC"), latest, "family_name", "Latest"));
        };

        pool.submit(toRunnableTask(middleRewrite));
        pool.submit(toRunnableTask(latestRewrite));
        bothReady.await(5, TimeUnit.SECONDS);
        go.countDown(); // release both at once to maximize interleaving
        pool.shutdown();
        assertTrue(pool.awaitTermination(10, TimeUnit.SECONDS), "reconciliation calls did not finish in time");

        assertEquals(Optional.of("Latest"), patientAccessor().getCurrentValue(patientId, "family_name"),
                "only the genuinely newest (latest-timestamped, Epic) value may win, regardless of thread interleaving");
    }

    // ---- date_of_birth-specific tests (2026-09-26 partial reversal) ----

    @Test
    void dateOfBirthFirstDisagreementWithNoPriorProvenanceAlsoFallsBackToPatientUpdatedAt() {
        Object patientId = freshPatientId();
        Instant patientEditedAt = Instant.parse("2026-06-01T00:00:00Z");
        seedPatientUpdatedAt(patientId, patientEditedAt);
        patientAccessor().applyValue(patientId, DATE_OF_BIRTH, "1950-05-04");

        Instant olderThanEdit = patientEditedAt.minus(30, ChronoUnit.DAYS);
        var staleAttempt = reconciler().reconcile(
                snapshot(patientId, sourceId("ATHENAHEALTH"), olderThanEdit, DATE_OF_BIRTH, "1950-05-05"));
        assertEquals(ReconciliationOutcome.Decision.REJECTED_STALE, staleAttempt.get(0).decision(),
                "older than patient.updated_at must still lose outright, same as any other field (Assumption A1)");
        assertTrue(auditWriter().currentPendingConflict(patientId, DATE_OF_BIRTH).isEmpty(),
                "a candidate that loses to the confirmed baseline must never become PENDING");

        Instant newerThanEdit = patientEditedAt.plus(1, ChronoUnit.DAYS);
        var freshAttempt = reconciler().reconcile(
                snapshot(patientId, sourceId("EPIC"), newerThanEdit, DATE_OF_BIRTH, "1950-05-06"));
        assertEquals(ReconciliationOutcome.Decision.PENDING_PATIENT_CONFIRMATION, freshAttempt.get(0).decision(),
                "newer than patient.updated_at makes it a genuine candidate, but DOB never auto-applies");
        assertEquals(Optional.of("1950-05-04"), patientAccessor().getCurrentValue(patientId, DATE_OF_BIRTH),
                "patient.date_of_birth must stay untouched while PENDING");
    }

    @Test
    void dateOfBirthDisagreementOpensPendingConfirmationInsteadOfAutoApplying() {
        Object patientId = freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");
        Instant t2 = t1.plus(1, ChronoUnit.DAYS);
        Object epic = sourceId("EPIC");

        reconciler().reconcile(snapshot(patientId, sourceId("ATHENAHEALTH"), t1, DATE_OF_BIRTH, "1950-05-04"));
        var outcomes = reconciler().reconcile(snapshot(patientId, epic, t2, DATE_OF_BIRTH, "1950-05-06"));

        assertEquals(ReconciliationOutcome.Decision.PENDING_PATIENT_CONFIRMATION, outcomes.get(0).decision());
        assertEquals("1950-05-06", outcomes.get(0).appliedValue(),
                "appliedValue carries the candidate awaiting confirmation, despite nothing having been applied yet");
        assertEquals(Optional.of("1950-05-04"), patientAccessor().getCurrentValue(patientId, DATE_OF_BIRTH),
                "a PENDING DOB conflict must never change patient.date_of_birth");
        assertTrue(decisionsFor(patientId, DATE_OF_BIRTH).isEmpty(),
                "a PENDING conflict is not a finalized decision and must not show up as one");

        var pending = auditWriter().currentPendingConflict(patientId, DATE_OF_BIRTH);
        assertTrue(pending.isPresent(), "the conflict must be discoverable as PENDING");
        assertEquals(epic, pending.get().sourceId());
        assertEquals("1950-05-04", pending.get().canonicalValueBefore());
        assertEquals("1950-05-06", pending.get().incomingValue());
        assertEquals(t2, pending.get().sourceUpdatedAt());
    }

    @Test
    void dateOfBirthCandidateNotNewerThanConfirmedBaselineNeverInterruptsThePatient() {
        Object patientId = freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");
        Instant tOlder = t1.minus(1, ChronoUnit.DAYS);

        reconciler().reconcile(snapshot(patientId, sourceId("ATHENAHEALTH"), t1, DATE_OF_BIRTH, "1950-05-04"));
        var outcomes = reconciler().reconcile(snapshot(patientId, sourceId("EPIC"), tOlder, DATE_OF_BIRTH, "1950-05-09"));

        assertEquals(ReconciliationOutcome.Decision.REJECTED_STALE, outcomes.get(0).decision(),
                "a candidate that couldn't have won under the ordinary recency rule must not prompt the patient");
        assertEquals(Optional.of("1950-05-04"), patientAccessor().getCurrentValue(patientId, DATE_OF_BIRTH));
        assertTrue(auditWriter().currentPendingConflict(patientId, DATE_OF_BIRTH).isEmpty());

        List<RecordedDecision> decisions = decisionsFor(patientId, DATE_OF_BIRTH);
        assertEquals(1, decisions.size(), "still audited, exactly like a rejected non-DOB disagreement");
        assertEquals(IdentityConflictAuditWriter.Outcome.REJECTED, decisions.get(0).outcome());
        assertEquals(IdentityConflictAuditWriter.ResolvedBy.SYSTEM, decisions.get(0).resolvedBy());
    }

    @Test
    void dateOfBirthPendingConflictIsSupersededByAGenuinelyNewerCandidate() {
        Object patientId = freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");
        Instant t2 = t1.plus(1, ChronoUnit.DAYS);
        Instant t3 = t1.plus(2, ChronoUnit.DAYS);
        Object oracle = sourceId("ORACLE_HEALTH");

        reconciler().reconcile(snapshot(patientId, sourceId("ATHENAHEALTH"), t1, DATE_OF_BIRTH, "1950-05-04"));
        reconciler().reconcile(snapshot(patientId, sourceId("EPIC"), t2, DATE_OF_BIRTH, "1950-05-06"));
        var supersede = reconciler().reconcile(snapshot(patientId, oracle, t3, DATE_OF_BIRTH, "1950-05-09"));

        assertEquals(ReconciliationOutcome.Decision.PENDING_PATIENT_CONFIRMATION, supersede.get(0).decision());
        var pending = auditWriter().currentPendingConflict(patientId, DATE_OF_BIRTH);
        assertTrue(pending.isPresent());
        assertEquals("1950-05-09", pending.get().incomingValue(), "the pending candidate must be the newest one");
        assertEquals(oracle, pending.get().sourceId());

        List<RecordedDecision> decisions = decisionsFor(patientId, DATE_OF_BIRTH);
        assertEquals(1, decisions.size(), "the superseded (Epic) candidate must be closed out, not left dangling");
        assertEquals(IdentityConflictAuditWriter.Outcome.REJECTED, decisions.get(0).outcome());
        assertEquals(IdentityConflictAuditWriter.ResolvedBy.SYSTEM, decisions.get(0).resolvedBy(),
                "the system superseded it, not the patient -- they were never asked about the Epic candidate");
        assertEquals("1950-05-06", decisions.get(0).incomingValue());
        assertEquals(Optional.of("1950-05-04"), patientAccessor().getCurrentValue(patientId, DATE_OF_BIRTH),
                "patient.date_of_birth is still untouched throughout");
    }

    @Test
    void dateOfBirthCandidateNotNewerThanTheOpenPendingOneIsIgnored() {
        Object patientId = freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");
        Instant t3 = t1.plus(3, ChronoUnit.DAYS);
        Instant t2BetweenT1AndT3 = t1.plus(1, ChronoUnit.DAYS);

        reconciler().reconcile(snapshot(patientId, sourceId("ATHENAHEALTH"), t1, DATE_OF_BIRTH, "1950-05-04"));
        reconciler().reconcile(snapshot(patientId, sourceId("EPIC"), t3, DATE_OF_BIRTH, "1950-05-09"));
        // Newer than the confirmed baseline (t1), but not newer than the already-pending candidate (t3).
        var ignored = reconciler().reconcile(
                snapshot(patientId, sourceId("ORACLE_HEALTH"), t2BetweenT1AndT3, DATE_OF_BIRTH, "1950-05-06"));

        assertEquals(ReconciliationOutcome.Decision.REJECTED_STALE, ignored.get(0).decision());
        var pending = auditWriter().currentPendingConflict(patientId, DATE_OF_BIRTH);
        assertTrue(pending.isPresent());
        assertEquals("1950-05-09", pending.get().incomingValue(),
                "the original (Epic, t3) candidate must remain the one pending, untouched by the older attempt");
    }

    @Test
    void finalizingPendingDateOfBirthAsAcceptedAppliesTheValueAndClearsThePending() {
        Object patientId = freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");
        Instant t2 = t1.plus(1, ChronoUnit.DAYS);

        reconciler().reconcile(snapshot(patientId, sourceId("ATHENAHEALTH"), t1, DATE_OF_BIRTH, "1950-05-04"));
        reconciler().reconcile(snapshot(patientId, sourceId("EPIC"), t2, DATE_OF_BIRTH, "1950-05-06"));

        var finalized = reconciler().finalizePendingDateOfBirth(patientId, true);

        assertEquals(ReconciliationOutcome.Decision.ACCEPTED_BY_PATIENT, finalized.decision());
        assertEquals("1950-05-06", finalized.appliedValue());
        assertEquals(Optional.of("1950-05-06"), patientAccessor().getCurrentValue(patientId, DATE_OF_BIRTH));
        assertTrue(auditWriter().currentPendingConflict(patientId, DATE_OF_BIRTH).isEmpty(),
                "no conflict should still be PENDING once finalized");

        List<RecordedDecision> decisions = decisionsFor(patientId, DATE_OF_BIRTH);
        assertEquals(1, decisions.size());
        assertEquals(IdentityConflictAuditWriter.Outcome.ACCEPTED, decisions.get(0).outcome());
        assertEquals(IdentityConflictAuditWriter.ResolvedBy.PATIENT, decisions.get(0).resolvedBy());

        // A subsequent, older disagreement must now lose against the newly-accepted (t2) baseline.
        var staleAfterAccept = reconciler().reconcile(
                snapshot(patientId, sourceId("ORACLE_HEALTH"), t1.plus(12, ChronoUnit.HOURS), DATE_OF_BIRTH, "1950-05-11"));
        assertEquals(ReconciliationOutcome.Decision.REJECTED_STALE, staleAfterAccept.get(0).decision(),
                "provenance must have advanced to t2 on acceptance, not stayed at t1");
    }

    @Test
    void finalizingPendingDateOfBirthAsRejectedLeavesPatientUnchangedAndClearsThePending() {
        Object patientId = freshPatientId();
        Instant t1 = Instant.parse("2026-01-01T00:00:00Z");
        Instant t2 = t1.plus(1, ChronoUnit.DAYS);

        reconciler().reconcile(snapshot(patientId, sourceId("ATHENAHEALTH"), t1, DATE_OF_BIRTH, "1950-05-04"));
        reconciler().reconcile(snapshot(patientId, sourceId("EPIC"), t2, DATE_OF_BIRTH, "1950-05-06"));

        var finalized = reconciler().finalizePendingDateOfBirth(patientId, false);

        assertEquals(ReconciliationOutcome.Decision.REJECTED_BY_PATIENT, finalized.decision());
        assertEquals("1950-05-04", finalized.appliedValue(), "reports what patient.date_of_birth still holds");
        assertEquals(Optional.of("1950-05-04"), patientAccessor().getCurrentValue(patientId, DATE_OF_BIRTH),
                "declining must never change patient.date_of_birth");
        assertTrue(auditWriter().currentPendingConflict(patientId, DATE_OF_BIRTH).isEmpty());

        List<RecordedDecision> decisions = decisionsFor(patientId, DATE_OF_BIRTH);
        assertEquals(1, decisions.size());
        assertEquals(IdentityConflictAuditWriter.Outcome.REJECTED, decisions.get(0).outcome());
        assertEquals(IdentityConflictAuditWriter.ResolvedBy.PATIENT, decisions.get(0).resolvedBy(),
                "the patient declined it -- this must never be attributed to SYSTEM");
    }

    @Test
    void finalizingWithNoPendingConflictThrows() {
        Object patientId = freshPatientId();
        assertThrows(IllegalStateException.class,
                () -> reconciler().finalizePendingDateOfBirth(patientId, true),
                "there is nothing to finalize when no date_of_birth conflict is open");
    }

    private static void awaitQuietly(CountDownLatch latch) {
        try {
            latch.await(5, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    private static java.util.concurrent.Callable<Void> toRunnableTask(Runnable r) {
        return () -> {
            r.run();
            return null;
        };
    }
}
