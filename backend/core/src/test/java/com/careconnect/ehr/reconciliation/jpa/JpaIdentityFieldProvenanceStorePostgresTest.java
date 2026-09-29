package com.careconnect.ehr.reconciliation.jpa;

import com.careconnect.ehr.reconciliation.FieldProvenance;
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
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Proves {@link JpaIdentityFieldProvenanceStore} actually takes the row lock it claims to take.
 * <p>
 * This is the test the class exists for. Every other guarantee in the reconciliation library is
 * single-threaded logic that the in-memory contract suite already covers; the lock is the one piece
 * whose absence produces no error, no log line and no failing unit test — just an intermittently
 * wrong winner when two adapters sync the same patient at the same moment. A store that simply read
 * the row without {@code FOR UPDATE} would pass every test in
 * {@code AbstractIdentityReconciliationContractTest} run single-threaded, and would be wrong.
 *
 * <p><strong>Why PostgreSQL only, and why not {@code @DataJpaTest}'s usual transaction.</strong>
 * H2 is not merely a different dialect here — proving that one transaction <em>blocks</em> another
 * requires two genuinely concurrent, genuinely committed transactions, which the standard
 * rollback-per-test arrangement cannot produce: both threads would be handed the same test
 * transaction and nothing would ever contend. So this class opts out with
 * {@code NOT_SUPPORTED} and drives each transaction explicitly through a {@link TransactionTemplate}
 * on its own thread. The consequence is that these tests commit real rows, so cleanup is explicit
 * rather than free.
 *
 * <p>Opt-in, needing a database the application has already booted against at least once:
 * <pre>
 *   EHR_IT_JDBC_URI=jdbc:postgresql://localhost:5433/cc_phase2 \
 *   EHR_IT_DB_USER=postgres EHR_IT_DB_PASSWORD=... \
 *   ./mvnw -Dtest=JpaIdentityFieldProvenanceStorePostgresTest test
 * </pre>
 * Skipped when {@code EHR_IT_JDBC_URI} is unset, so CI stays green.
 * <p>
 * Test IDs TC-EHR-PROV-001..005 are permanent. Never renumber, never reuse.
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
class JpaIdentityFieldProvenanceStorePostgresTest {

    /**
     * Deliberately not a real identity field. These tests commit, so they must not touch provenance
     * rows that a real reconciliation run owns; a field name no adapter will ever send keeps the
     * blast radius to rows this class created and deletes.
     */
    private static final String TEST_FIELD = "__it_provenance_probe";

    /**
     * How long the lock holder stays in its transaction after taking the lock. Long enough that a
     * non-blocking contender would comfortably finish first and fail the assertion, short enough
     * not to drag the suite. The test asserts ordering via a flag rather than by timing, so this
     * value affects only how convincingly a broken implementation fails, never whether a correct
     * one passes.
     */
    private static final long LOCK_HOLD_MILLIS = 750;

    @PersistenceContext
    private EntityManager entityManager;

    @Autowired
    private EhrIdentityFieldProvenanceRepository repository;

    @Autowired
    private PlatformTransactionManager transactionManager;

    private TransactionTemplate tx;
    private JpaIdentityFieldProvenanceStore store;
    private long patientId;
    private long sourceId;

    @BeforeEach
    void setUp() {
        tx = new TransactionTemplate(transactionManager);
        store = new JpaIdentityFieldProvenanceStore(repository, entityManager);
        patientId = firstIdOf("patient");
        sourceId = firstIdOf("ehr_source");
        deleteProbeRows();
    }

    @AfterEach
    void tearDown() {
        deleteProbeRows();
    }

    // ---- TC-EHR-PROV-001 ----

    @Test
    @DisplayName("TC-EHR-PROV-001: a first touch creates the row and reports no provenance yet")
    void firstTouchCreatesAnEmptyRowAndReportsNoProvenance() {
        Optional<FieldProvenance> provenance =
                tx.execute(status -> store.lockOrCreate(patientId, TEST_FIELD));

        assertThat(provenance)
                .as("a row created purely to be locked must read as 'no source has established "
                        + "provenance yet', not as a FieldProvenance holding nulls")
                .isEmpty();
        assertThat(probeRowCount())
                .as("the placeholder row must actually be committed, or there is nothing to lock")
                .isEqualTo(1);
    }

    // ---- TC-EHR-PROV-002 ----

    @Test
    @DisplayName("TC-EHR-PROV-002: recorded provenance is returned on the next lock")
    void recordedProvenanceIsReturnedOnTheNextLock() {
        Instant recordedAt = Instant.parse("2026-04-01T09:30:00Z");

        tx.executeWithoutResult(status -> {
            store.lockOrCreate(patientId, TEST_FIELD);
            store.recordAsFreshest(patientId, TEST_FIELD, sourceId, recordedAt);
        });

        Optional<FieldProvenance> readBack =
                tx.execute(status -> store.lockOrCreate(patientId, TEST_FIELD));

        assertThat(readBack).isPresent();
        assertThat(readBack.get().sourceId()).isEqualTo(sourceId);
        assertThat(readBack.get().sourceUpdatedAt())
                .as("the timestamp must survive the timestamptz round trip exactly; "
                        + "a truncated or shifted value silently changes who wins a comparison")
                .isEqualTo(recordedAt);
    }

    // ---- TC-EHR-PROV-003: the one that matters ----

    @Test
    @DisplayName("TC-EHR-PROV-003: a second transaction blocks on the lock and then sees the first one's write")
    void secondTransactionBlocksOnTheLockAndSeesTheCommittedWrite() throws Exception {
        Instant holderTimestamp = Instant.parse("2026-05-01T00:00:00Z");
        Instant contenderTimestamp = holderTimestamp.plus(1, ChronoUnit.DAYS);

        // Establish the row first, so this test isolates the lock itself rather than also exercising
        // the create-race that TC-EHR-PROV-004 covers.
        tx.executeWithoutResult(status -> store.lockOrCreate(patientId, TEST_FIELD));

        CountDownLatch holderHasLock = new CountDownLatch(1);
        AtomicBoolean holderCommitted = new AtomicBoolean(false);

        ExecutorService pool = Executors.newFixedThreadPool(2);
        try {
            Future<?> holder = pool.submit(() -> tx.executeWithoutResult(status -> {
                store.lockOrCreate(patientId, TEST_FIELD);
                store.recordAsFreshest(patientId, TEST_FIELD, sourceId, holderTimestamp);
                holderHasLock.countDown();
                sleepQuietly(LOCK_HOLD_MILLIS);
                // Set inside the transaction, immediately before commit: if the contender ever
                // observes this as false, it read the row without waiting for the lock.
                holderCommitted.set(true);
            }));

            Future<Boolean> contender = pool.submit(() -> {
                if (!holderHasLock.await(5, TimeUnit.SECONDS)) {
                    throw new IllegalStateException("holder never reported taking the lock");
                }
                return tx.execute(status -> {
                    Optional<FieldProvenance> seen = store.lockOrCreate(patientId, TEST_FIELD);
                    boolean sawHoldersCommit = holderCommitted.get()
                            && seen.isPresent()
                            && holderTimestamp.equals(seen.get().sourceUpdatedAt());
                    // Write our own provenance too, so the final row proves which order the two
                    // transactions actually serialized in.
                    store.recordAsFreshest(patientId, TEST_FIELD, sourceId, contenderTimestamp);
                    return sawHoldersCommit;
                });
            });

            holder.get(30, TimeUnit.SECONDS);
            assertThat(contender.get(30, TimeUnit.SECONDS))
                    .as("the contender must have blocked until the holder committed and then read "
                            + "the holder's value; reading anything else means SELECT ... FOR UPDATE "
                            + "is not being issued and two adapters can both act on stale provenance")
                    .isTrue();
        } finally {
            pool.shutdownNow();
        }

        Optional<FieldProvenance> finalState =
                tx.execute(status -> store.lockOrCreate(patientId, TEST_FIELD));
        assertThat(finalState).isPresent();
        assertThat(finalState.get().sourceUpdatedAt())
                .as("the two transactions must have serialized, leaving the second one's write intact")
                .isEqualTo(contenderTimestamp);
    }

    // ---- TC-EHR-PROV-004 ----

    @Test
    @DisplayName("TC-EHR-PROV-004: two first touches of the same field race without violating the unique index")
    void concurrentFirstTouchesProduceExactlyOneRowAndNoConstraintViolation() throws Exception {
        CountDownLatch bothReady = new CountDownLatch(2);
        CountDownLatch go = new CountDownLatch(1);

        ExecutorService pool = Executors.newFixedThreadPool(2);
        try {
            List<Future<Optional<FieldProvenance>>> attempts = List.of(
                    pool.submit(() -> raceToCreate(bothReady, go)),
                    pool.submit(() -> raceToCreate(bothReady, go)));

            assertThat(bothReady.await(5, TimeUnit.SECONDS)).isTrue();
            go.countDown();

            for (Future<Optional<FieldProvenance>> attempt : attempts) {
                // A unique violation would surface here. It would also have aborted that thread's
                // whole transaction, which is precisely why the implementation uses
                // ON CONFLICT DO NOTHING rather than catching the violation and retrying.
                assertThat(attempt.get(30, TimeUnit.SECONDS)).isEmpty();
            }
        } finally {
            pool.shutdownNow();
        }

        assertThat(probeRowCount())
                .as("exactly one provenance row may exist per (patient_id, field_name); "
                        + "two would mean two adapters could hold two different 'locks' for one field")
                .isEqualTo(1);
    }

    private Optional<FieldProvenance> raceToCreate(CountDownLatch bothReady, CountDownLatch go) {
        bothReady.countDown();
        if (!awaitQuietly(go)) {
            throw new IllegalStateException("race was never released");
        }
        return tx.execute(status -> store.lockOrCreate(patientId, TEST_FIELD));
    }

    // ---- TC-EHR-PROV-005 ----

    @Test
    @DisplayName("TC-EHR-PROV-005: calling without a transaction fails loudly instead of locking nothing")
    void callingOutsideATransactionIsRejected() {
        assertThatThrownBy(() -> store.lockOrCreate(patientId, TEST_FIELD))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("requires an active transaction");

        assertThatThrownBy(() ->
                store.recordAsFreshest(patientId, TEST_FIELD, sourceId, Instant.now()))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("requires an active transaction");

        assertThat(probeRowCount())
                .as("a rejected call must not have written anything on its way out")
                .isZero();
    }

    // ---- helpers ----

    private long firstIdOf(String table) {
        Number id = (Number) tx.execute(status -> entityManager
                .createNativeQuery("select id from " + table + " order by id limit 1")
                .getSingleResult());
        if (id == null) {
            throw new IllegalStateException(
                    "No rows in " + table + "; this test needs a database the application has booted "
                            + "against, with at least one patient and one ehr_source row.");
        }
        return id.longValue();
    }

    private int probeRowCount() {
        Number count = (Number) tx.execute(status -> entityManager
                .createNativeQuery("select count(*) from ehr_identity_field_provenance "
                        + "where patient_id = :patientId and field_name = :fieldName")
                .setParameter("patientId", patientId)
                .setParameter("fieldName", TEST_FIELD)
                .getSingleResult());
        return count == null ? 0 : count.intValue();
    }

    private void deleteProbeRows() {
        tx.executeWithoutResult(status -> entityManager
                .createNativeQuery("delete from ehr_identity_field_provenance where field_name = :fieldName")
                .setParameter("fieldName", TEST_FIELD)
                .executeUpdate());
    }

    private static void sleepQuietly(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("interrupted while holding the lock", e);
        }
    }

    private static boolean awaitQuietly(CountDownLatch latch) {
        try {
            return latch.await(5, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return false;
        }
    }
}
