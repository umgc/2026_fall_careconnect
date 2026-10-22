package com.careconnect.ehr.reconciliation;

import com.careconnect.ehr.reconciliation.support.InMemoryAuditWriter;
import com.careconnect.ehr.reconciliation.support.InMemoryPatientAccessor;
import com.careconnect.ehr.reconciliation.support.InMemoryProvenanceStore;
import com.careconnect.ehr.reconciliation.support.InMemoryTransactionRunner;
import com.careconnect.ehr.reconciliation.support.UnsafeProvenanceStore;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Runs the recency-wins race many times over, to show the provenance row lock is what decides the
 * outcome rather than luck.
 *
 * <p>The single-shot version of this lives in {@code AbstractIdentityReconciliationContractTest}
 * (TC-EHR-REC) and, against a real database, in
 * {@code JpaIdentityFieldProvenanceStorePostgresTest} TC-EHR-PROV-003. Both are worth more than this
 * class for catching a broken implementation. What they cannot give is a repetition count: a race
 * that goes wrong one time in ten passes a single-shot test nine times out of ten.
 *
 * <p><b>What this does not prove.</b> Everything here runs against the in-memory fakes, and
 * {@code InMemoryTransactionRunner} runs its work directly with no database underneath. So this
 * shows the algorithm converges under contention <em>when the store's lock works</em>; it cannot
 * fail because {@code JpaIdentityFieldProvenanceStore}'s {@code SELECT ... FOR UPDATE} is missing
 * or wrong. The database-level proof is TC-EHR-PROV-003 and only that. Do not accept this class as
 * evidence that the JPA store serialises concurrent transactions (PR #216 review).
 *
 * <p><b>Origin.</b> This replaces {@code ehr-identity-reconciliation/manual-verify/}, three files at
 * the repository root outside every Maven module. They were written when the authoring environment
 * had no JUnit or Maven Central, and they kept the "verified, not just written" claim in the library
 * README checkable. Nothing compiled them, so nothing noticed when the {@code Object}-to-{@code Long}
 * id change broke all three — which is exactly the drift the PR #209 review predicted, already
 * realised by the time it was raised.
 *
 * <p>Test IDs TC-EHR-REC-049..050 are permanent. Never renumber, never reuse.
 */
class AdversarialLockProofTest {

    /** Enough repetitions to make an intermittent race show up, small enough to stay in the suite. */
    private static final int TRIALS = 60;

    private final AtomicLong patientIds = new AtomicLong(1);

    /**
     * The guarantee: with the lock, the newest-timestamped value wins every single time.
     * <p>
     * Both racers beat the original baseline, so neither is disqualified before the race starts — if
     * only one could ever win, the scenario would pass against a broken store too and prove nothing.
     */
    @Test
    @DisplayName("TC-EHR-REC-049: the locking store converges on the newest value in every trial")
    void lockingStoreNeverLosesTheRace() throws Exception {
        int wrong = runTrials(true);
        assertThat(wrong)
                .as("%d trials against the correctly-locking store; every one must converge on the "
                        + "newest value, or the lock is not doing its job", TRIALS)
                .isZero();
    }

    /**
     * The control, and the reason the assertion above means anything.
     * <p>
     * Opt-in rather than always-on because it is inherently probabilistic: a broken store loses the
     * race <em>often</em>, not always, so asserting a failure count would make the suite flaky. Run
     * it by hand when changing anything about locking:
     * <pre>
     *   EHR_ADVERSARIAL=1 ./mvnw -Dtest=AdversarialLockProofTest test
     * </pre>
     * Historic counts from the harness this replaces: 17, 27 and 34 wrong outcomes in 200 trials on
     * three separate runs. Any non-zero count is the point; the exact number will vary by machine.
     */
    @Test
    @EnabledIfEnvironmentVariable(named = "EHR_ADVERSARIAL", matches = ".+")
    @DisplayName("TC-EHR-REC-050: control: the non-locking store does lose the race, so the scenario is sensitive to the lock")
    void unsafeStoreLosesTheRaceAtLeastSometimes() throws Exception {
        int wrong = runTrials(false);
        assertThat(wrong)
                .as("%d trials against a deliberately non-locking store; expected at least one wrong "
                        + "outcome. Zero means this scenario is race-free by construction and the "
                        + "passing result above is vacuous", TRIALS)
                .isPositive();
    }

    /** @return how many trials ended with a value other than the newest-timestamped one. */
    private int runTrials(boolean locking) throws InterruptedException {
        int wrong = 0;
        for (int i = 0; i < TRIALS; i++) {
            Long patientId = patientIds.getAndIncrement();
            InMemoryPatientAccessor patients = new InMemoryPatientAccessor();
            IdentityFieldProvenanceStore store =
                    locking ? new InMemoryProvenanceStore() : new UnsafeProvenanceStore();
            IdentityReconciler reconciler = new RecencyWinsIdentityReconciler(
                    store, patients, new InMemoryAuditWriter(), new InMemoryTransactionRunner());

            Instant baseline = Instant.parse("2026-01-01T00:00:00Z");
            Instant middle = baseline.plus(1, ChronoUnit.DAYS);
            Instant latest = baseline.plus(2, ChronoUnit.DAYS);

            reconciler.reconcile(snapshot(patientId, 1L, baseline, "Alpha"));

            ExecutorService pool = Executors.newFixedThreadPool(2);
            CountDownLatch ready = new CountDownLatch(2);
            CountDownLatch go = new CountDownLatch(1);
            pool.submit(racer(reconciler, patientId, 2L, middle, "Middle", ready, go));
            pool.submit(racer(reconciler, patientId, 3L, latest, "Latest", ready, go));
            ready.await(5, TimeUnit.SECONDS);
            go.countDown();
            pool.shutdown();
            if (!pool.awaitTermination(10, TimeUnit.SECONDS)) {
                throw new IllegalStateException("trial " + i + " did not finish");
            }

            Optional<String> finalValue = patients.getCurrentValue(patientId, "family_name");
            if (!finalValue.equals(Optional.of("Latest"))) {
                wrong++;
            }
        }
        return wrong;
    }

    private static Runnable racer(
            IdentityReconciler reconciler, Long patientId, Long sourceId,
            Instant at, String value, CountDownLatch ready, CountDownLatch go) {
        return () -> {
            ready.countDown();
            try {
                if (!go.await(5, TimeUnit.SECONDS)) {
                    throw new IllegalStateException("race never released");
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
            reconciler.reconcile(snapshot(patientId, sourceId, at, value));
        };
    }

    private static SourceIdentitySnapshot snapshot(
            Long patientId, Long sourceId, Instant sourceUpdatedAt, String familyName) {
        return new SourceIdentitySnapshot(
                patientId, sourceId, sourceUpdatedAt, Map.of("family_name", familyName));
    }
}
