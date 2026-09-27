import com.careconnect.ehr.reconciliation.*;
import com.careconnect.ehr.reconciliation.support.*;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Proves the concurrency scenarios in ManualContractCheck / AbstractIdentityReconciliationContractTest
 * actually have teeth: run each many times against UnsafeProvenanceStore (no row lock) instead of the
 * real InMemoryProvenanceStore, and show it fails at least some of the time. If it never failed here,
 * the "passes against the real store" result earlier would be meaningless.
 *
 * <p>2026-09-26 partial reversal: the second experiment below ({@code dateOfBirthPendingRace}) is new,
 * added to verify the date_of_birth carve-out's own correctness-critical path (opening/superseding a
 * PENDING conflict) is covered by the same {@code IdentityFieldProvenanceStore.lockOrCreate} lock the
 * original recency-wins path already depended on — {@code RecencyWinsIdentityReconciler} takes that
 * lock before branching on field name, so it should serialize DOB's pending-conflict reads/writes too.
 * Field-name-specific race, field-name-specific proof.
 */
public class AdversarialCheck {
    public static void main(String[] args) throws Exception {
        familyNameRace();
        dateOfBirthPendingRace();
        if (anyExpectationFailed) {
            System.exit(1);
        }
    }

    /** The original recency-wins race, unchanged in substance -- renamed field only (see README/tests). */
    static void familyNameRace() throws Exception {
        int trials = 200;
        int wrongResult = 0;

        for (int i = 0; i < trials; i++) {
            InMemoryPatientAccessor patientAccessor = new InMemoryPatientAccessor();
            InMemoryAuditWriter auditWriter = new InMemoryAuditWriter();
            UnsafeProvenanceStore unsafeStore = new UnsafeProvenanceStore();
            IdentityReconciler reconciler = new RecencyWinsIdentityReconciler(
                    unsafeStore, patientAccessor, auditWriter, new InMemoryTransactionRunner());

            Object patientId = "fn" + i;
            Object orgId = "ORG-1";
            Instant baseline = Instant.parse("2026-01-01T00:00:00Z");
            Instant middle = baseline.plus(1, ChronoUnit.DAYS);
            Instant latest = baseline.plus(2, ChronoUnit.DAYS);

            reconciler.reconcile(new SourceIdentitySnapshot(patientId, "ATHENAHEALTH", orgId, baseline,
                    Map.of("family_name", "Alpha")));

            ExecutorService pool = Executors.newFixedThreadPool(2);
            CountDownLatch bothReady = new CountDownLatch(2);
            CountDownLatch go = new CountDownLatch(1);

            pool.submit(() -> {
                bothReady.countDown();
                await(go);
                reconciler.reconcile(new SourceIdentitySnapshot(patientId, "ORACLE_HEALTH", orgId, middle,
                        Map.of("family_name", "Middle")));
            });
            pool.submit(() -> {
                bothReady.countDown();
                await(go);
                reconciler.reconcile(new SourceIdentitySnapshot(patientId, "EPIC", orgId, latest,
                        Map.of("family_name", "Latest")));
            });

            bothReady.await(5, TimeUnit.SECONDS);
            go.countDown();
            pool.shutdown();
            pool.awaitTermination(10, TimeUnit.SECONDS);

            Optional<String> finalValue = patientAccessor.getCurrentValue(patientId, "family_name");
            if (!finalValue.equals(Optional.of("Latest"))) {
                wrongResult++;
            }
        }

        System.out.println(wrongResult + " / " + trials + " trials produced the WRONG final value "
                + "with no row lock (expected > 0, proving the scenario is sensitive to the race).");
        recordFailureIfExpectationNotMet("familyNameRace (unsafe store)", wrongResult > 0);

        // Control: the same race against the real, correctly-locking store must never go wrong.
        int wrongAgainstRealStore = 0;
        for (int i = 0; i < trials; i++) {
            InMemoryPatientAccessor patientAccessor = new InMemoryPatientAccessor();
            InMemoryAuditWriter auditWriter = new InMemoryAuditWriter();
            InMemoryProvenanceStore realStore = new InMemoryProvenanceStore();
            IdentityReconciler reconciler = new RecencyWinsIdentityReconciler(
                    realStore, patientAccessor, auditWriter, new InMemoryTransactionRunner());

            Object patientId = "fnreal" + i;
            Object orgId = "ORG-1";
            Instant baseline = Instant.parse("2026-01-01T00:00:00Z");
            Instant middle = baseline.plus(1, ChronoUnit.DAYS);
            Instant latest = baseline.plus(2, ChronoUnit.DAYS);

            reconciler.reconcile(new SourceIdentitySnapshot(patientId, "ATHENAHEALTH", orgId, baseline,
                    Map.of("family_name", "Alpha")));

            ExecutorService pool = Executors.newFixedThreadPool(2);
            CountDownLatch bothReady = new CountDownLatch(2);
            CountDownLatch go = new CountDownLatch(1);
            pool.submit(() -> {
                bothReady.countDown();
                await(go);
                reconciler.reconcile(new SourceIdentitySnapshot(patientId, "ORACLE_HEALTH", orgId, middle,
                        Map.of("family_name", "Middle")));
            });
            pool.submit(() -> {
                bothReady.countDown();
                await(go);
                reconciler.reconcile(new SourceIdentitySnapshot(patientId, "EPIC", orgId, latest,
                        Map.of("family_name", "Latest")));
            });
            bothReady.await(5, TimeUnit.SECONDS);
            go.countDown();
            pool.shutdown();
            pool.awaitTermination(10, TimeUnit.SECONDS);

            if (!patientAccessor.getCurrentValue(patientId, "family_name").equals(Optional.of("Latest"))) {
                wrongAgainstRealStore++;
            }
        }
        System.out.println(wrongAgainstRealStore + " / " + trials + " trials produced the WRONG final value "
                + "with the real, correctly-locking store (expected exactly 0).");
        recordFailureIfExpectationNotMet("familyNameRace (real store)", wrongAgainstRealStore == 0);
    }

    /**
     * date_of_birth's own correctness-critical path: two adapters racing disagreements that both beat
     * the confirmed baseline, where the second one that runs must supersede the first's PENDING
     * candidate rather than either silently duplicating it or throwing. Both racing timestamps beat the
     * baseline (same reasoning as familyNameRace's scenario choice) so the outcome actually depends on
     * the lock, not on one candidate losing outright regardless of interleaving.
     */
    static void dateOfBirthPendingRace() throws Exception {
        int trials = 200;
        int unexpectedExceptions = 0;

        for (int i = 0; i < trials; i++) {
            InMemoryPatientAccessor patientAccessor = new InMemoryPatientAccessor();
            InMemoryAuditWriter auditWriter = new InMemoryAuditWriter();
            UnsafeProvenanceStore unsafeStore = new UnsafeProvenanceStore();
            IdentityReconciler reconciler = new RecencyWinsIdentityReconciler(
                    unsafeStore, patientAccessor, auditWriter, new InMemoryTransactionRunner());

            Object patientId = "dobUnsafe" + i;
            Object orgId = "ORG-1";
            Instant baseline = Instant.parse("2026-01-01T00:00:00Z");
            Instant middle = baseline.plus(1, ChronoUnit.DAYS);
            Instant latest = baseline.plus(2, ChronoUnit.DAYS);

            reconciler.reconcile(new SourceIdentitySnapshot(patientId, "ATHENAHEALTH", orgId, baseline,
                    Map.of("date_of_birth", "1950-05-04")));

            AtomicBoolean sawUnexpectedException = new AtomicBoolean(false);
            ExecutorService pool = Executors.newFixedThreadPool(2);
            CountDownLatch bothReady = new CountDownLatch(2);
            CountDownLatch go = new CountDownLatch(1);

            pool.submit(() -> {
                bothReady.countDown();
                await(go);
                try {
                    reconciler.reconcile(new SourceIdentitySnapshot(patientId, "ORACLE_HEALTH", orgId, middle,
                            Map.of("date_of_birth", "1950-05-09")));
                } catch (RuntimeException e) {
                    sawUnexpectedException.set(true);
                }
            });
            pool.submit(() -> {
                bothReady.countDown();
                await(go);
                try {
                    reconciler.reconcile(new SourceIdentitySnapshot(patientId, "EPIC", orgId, latest,
                            Map.of("date_of_birth", "1950-05-06")));
                } catch (RuntimeException e) {
                    sawUnexpectedException.set(true);
                }
            });

            bothReady.await(5, TimeUnit.SECONDS);
            go.countDown();
            pool.shutdown();
            pool.awaitTermination(10, TimeUnit.SECONDS);

            if (sawUnexpectedException.get()) {
                unexpectedExceptions++;
            }
        }

        System.out.println(unexpectedExceptions + " / " + trials + " trials threw an unexpected exception "
                + "opening/superseding a PENDING date_of_birth conflict with no row lock (expected > 0, "
                + "proving this path is sensitive to the same race the original recency-wins path is).");
        recordFailureIfExpectationNotMet("dateOfBirthPendingRace (unsafe store)", unexpectedExceptions > 0);

        // Control: the same race against the real, correctly-locking store must never throw, and must
        // always converge on a single PENDING conflict carrying the genuinely newest candidate.
        int wrongAgainstRealStore = 0;
        for (int i = 0; i < trials; i++) {
            InMemoryPatientAccessor patientAccessor = new InMemoryPatientAccessor();
            InMemoryAuditWriter auditWriter = new InMemoryAuditWriter();
            InMemoryProvenanceStore realStore = new InMemoryProvenanceStore();
            IdentityReconciler reconciler = new RecencyWinsIdentityReconciler(
                    realStore, patientAccessor, auditWriter, new InMemoryTransactionRunner());

            Object patientId = "dobReal" + i;
            Object orgId = "ORG-1";
            Instant baseline = Instant.parse("2026-01-01T00:00:00Z");
            Instant middle = baseline.plus(1, ChronoUnit.DAYS);
            Instant latest = baseline.plus(2, ChronoUnit.DAYS);

            reconciler.reconcile(new SourceIdentitySnapshot(patientId, "ATHENAHEALTH", orgId, baseline,
                    Map.of("date_of_birth", "1950-05-04")));

            AtomicBoolean threw = new AtomicBoolean(false);
            ExecutorService pool = Executors.newFixedThreadPool(2);
            CountDownLatch bothReady = new CountDownLatch(2);
            CountDownLatch go = new CountDownLatch(1);
            pool.submit(() -> {
                bothReady.countDown();
                await(go);
                try {
                    reconciler.reconcile(new SourceIdentitySnapshot(patientId, "ORACLE_HEALTH", orgId, middle,
                            Map.of("date_of_birth", "1950-05-09")));
                } catch (RuntimeException e) {
                    threw.set(true);
                }
            });
            pool.submit(() -> {
                bothReady.countDown();
                await(go);
                try {
                    reconciler.reconcile(new SourceIdentitySnapshot(patientId, "EPIC", orgId, latest,
                            Map.of("date_of_birth", "1950-05-06")));
                } catch (RuntimeException e) {
                    threw.set(true);
                }
            });
            bothReady.await(5, TimeUnit.SECONDS);
            go.countDown();
            pool.shutdown();
            pool.awaitTermination(10, TimeUnit.SECONDS);

            Optional<IdentityConflictAuditWriter.PendingConflict> pending =
                    auditWriter.currentPendingConflict(patientId, "date_of_birth");
            boolean correct = !threw.get() && pending.isPresent() && "1950-05-06".equals(pending.get().incomingValue());
            if (!correct) {
                wrongAgainstRealStore++;
            }
        }
        System.out.println(wrongAgainstRealStore + " / " + trials + " trials produced the WRONG outcome "
                + "(an exception, or a pending conflict not carrying the genuinely newest candidate) "
                + "with the real, correctly-locking store (expected exactly 0).");
        recordFailureIfExpectationNotMet("dateOfBirthPendingRace (real store)", wrongAgainstRealStore == 0);
    }

    static boolean anyExpectationFailed = false;

    static void recordFailureIfExpectationNotMet(String label, boolean expectationMet) {
        if (!expectationMet) {
            System.out.println("EXPECTATION NOT MET: " + label);
            anyExpectationFailed = true;
        }
    }

    static void await(CountDownLatch latch) {
        try {
            latch.await(5, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
