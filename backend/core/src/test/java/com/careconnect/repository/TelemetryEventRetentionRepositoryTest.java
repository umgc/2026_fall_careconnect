package com.careconnect.repository;

import com.careconnect.model.TelemetryEvent;
import com.careconnect.service.TelemetryService;
import com.careconnect.service.TelemetryToggleService;
import java.time.OffsetDateTime;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Persistence-layer tests for the telemetry retention purge added by PR #62 (WBS 2.4.1, Issue #3).
 *
 * <p>Covers the boundary semantics of the derived delete
 * {@code TelemetryEventRepository.removeByEventTimeBefore} and — in TC-TEL-RET-020 — the
 * transaction boundary the scheduled task actually runs under in production.
 *
 * <p>Uses {@code replace = Replace.NONE} so the configured H2 datasource from
 * {@code application-test.properties} is kept: it installs the {@code JSONB -> TEXT} domain shim
 * that {@link TelemetryEvent}'s {@code device_info} and {@code details} columns require.
 *
 * <p>Test IDs are permanent and must be reserved in the Software Test Plan when it is drafted.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@DisplayName("TelemetryEvent retention purge (PR #62)")
class TelemetryEventRetentionRepositoryTest {

    /** Retention window under test, mirroring the value the service applies. */
    private static final int RETENTION_DAYS = 30;

    @Autowired
    private TelemetryEventRepository repository;

    @Autowired
    private PlatformTransactionManager transactionManager;

    @BeforeEach
    void clean() {
        repository.deleteAllInBatch();
    }

    private TelemetryEvent seed(final String eventName, final OffsetDateTime eventTime) {
        final TelemetryEvent event = new TelemetryEvent();
        event.setEventName(eventName);
        event.setEventTime(eventTime);
        return repository.saveAndFlush(event);
    }

    private OffsetDateTime cutoff() {
        return OffsetDateTime.now().minusDays(RETENTION_DAYS);
    }

    @Test
    @DisplayName("TC-TEL-RET-010: boundary - strictly-before, row exactly at the cutoff is retained")
    void deletesOnlyStrictlyOlderThanCutoff() {
        final OffsetDateTime now = OffsetDateTime.now();
        seed("older", now.minusDays(RETENTION_DAYS + 1L));
        seed("exactly", now.minusDays(RETENTION_DAYS));
        seed("newer", now.minusDays(RETENTION_DAYS - 1L));
        seed("current", now);

        // Cutoff taken slightly before the "exactly" row so the strictly-less-than semantics of
        // Before are observable rather than a coin flip on sub-second drift.
        final int removed = repository.removeByEventTimeBefore(now.minusDays(RETENTION_DAYS).minusSeconds(1));

        assertThat(removed).isEqualTo(1);
        assertThat(repository.findAll())
                .extracting(TelemetryEvent::getEventName)
                .containsExactlyInAnyOrder("exactly", "newer", "current");
    }

    @Test
    @DisplayName("TC-TEL-RET-011: empty table - returns zero, no error")
    void emptyTableRemovesNothing() {
        final int removed = repository.removeByEventTimeBefore(cutoff());

        assertThat(removed).isZero();
        assertThat(repository.findAll()).isEmpty();
    }

    @Test
    @DisplayName("TC-TEL-RET-012: all rows inside the window - nothing deleted")
    void retainsAllRowsInsideWindow() {
        final OffsetDateTime now = OffsetDateTime.now();
        seed("a", now.minusDays(1));
        seed("b", now.minusDays(14));
        seed("c", now.minusDays(RETENTION_DAYS - 1L));

        final int removed = repository.removeByEventTimeBefore(cutoff());

        assertThat(removed).isZero();
        assertThat(repository.findAll()).hasSize(3);
    }

    @Test
    @DisplayName("TC-TEL-RET-013: all rows outside the window - all deleted")
    void deletesEveryRowOutsideWindow() {
        final OffsetDateTime now = OffsetDateTime.now();
        seed("a", now.minusDays(RETENTION_DAYS + 1L));
        seed("b", now.minusDays(60));
        seed("c", now.minusDays(365));

        final int removed = repository.removeByEventTimeBefore(cutoff());

        assertThat(removed).isEqualTo(3);
        assertThat(repository.findAll()).isEmpty();
    }

    @Test
    @DisplayName("TC-TEL-RET-014: no over-deletion - purge is scoped to event_time only")
    void doesNotOverDeleteAcrossOtherColumns() {
        final OffsetDateTime now = OffsetDateTime.now();
        seed("feature_use", now.minusDays(40));
        seed("feature_use", now.minusDays(2));
        seed("sync_completed", now.minusDays(2));

        final int removed = repository.removeByEventTimeBefore(cutoff());

        assertThat(removed).isEqualTo(1);
        assertThat(repository.findAll())
                .extracting(TelemetryEvent::getEventName)
                .containsExactlyInAnyOrder("feature_use", "sync_completed");
        assertThat(repository.findAll())
                .allSatisfy(row -> assertThat(row.getEventTime()).isAfter(cutoff()));
    }

    /**
     * TC-TEL-RET-020 — the decisive transaction-boundary case for defect D-1.
     *
     * <p>{@code @DataJpaTest} wraps every test in a transaction by default, which would mask the
     * defect entirely. {@code Propagation.NOT_SUPPORTED} suspends it so this test runs with no
     * ambient transaction — exactly the condition of the {@code @Scheduled} task in production,
     * where the job executes on a scheduler thread and {@code spring.jpa.open-in-view=false}
     * (application.properties:69) means no EntityManager or transaction is bound to the thread.
     *
     * <p>This asserts the requirement: the daily purge deletes expired telemetry. If
     * {@code removeByEventTimeBefore} genuinely requires {@code @Modifying}/{@code @Transactional}
     * that PR #62 omits, this test fails and that failure is the evidence backing D-1.
     *
     * <p>Because this method commits for real (no rollback), it cleans up after itself.
     */
    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    @DisplayName("TC-TEL-RET-020: scheduled purge deletes expired rows with no ambient transaction")
    void scheduledPurgeWorksOutsideAmbientTransaction() {
        try {
            final OffsetDateTime now = OffsetDateTime.now();
            seed("expired", now.minusDays(40));
            seed("retained", now.minusDays(2));

            final TelemetryService telemetryService =
                    new TelemetryService(repository, new TelemetryToggleService(true));
            ReflectionTestUtils.setField(telemetryService, "cleanupAfterDays", RETENTION_DAYS);

            telemetryService.dropOld();

            final List<TelemetryEvent> remaining = repository.findAll();
            assertThat(remaining)
                    .extracting(TelemetryEvent::getEventName)
                    .containsExactly("retained");
        } finally {
            repository.deleteAllInBatch();
        }
    }

    /**
     * TC-TEL-RET-021 — isolates defect D-1 to the missing transaction boundary.
     *
     * <p>Runs the identical production call path as TC-TEL-RET-020, the only difference being that
     * the invocation is wrapped in an explicit transaction. If this passes while TC-TEL-RET-020
     * fails, the derived delete and its predicate are correct and the sole defect is the absent
     * {@code @Modifying}/{@code @Transactional} declaration — which is what the proposed fix adds.
     */
    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    @DisplayName("TC-TEL-RET-021: same purge succeeds when wrapped in a transaction")
    void scheduledPurgeSucceedsInsideTransaction() {
        try {
            final OffsetDateTime now = OffsetDateTime.now();
            seed("expired", now.minusDays(40));
            seed("retained", now.minusDays(2));

            final TelemetryService telemetryService =
                    new TelemetryService(repository, new TelemetryToggleService(true));
            ReflectionTestUtils.setField(telemetryService, "cleanupAfterDays", RETENTION_DAYS);

            new TransactionTemplate(transactionManager)
                    .executeWithoutResult(status -> telemetryService.dropOld());

            assertThat(repository.findAll())
                    .extracting(TelemetryEvent::getEventName)
                    .containsExactly("retained");
        } finally {
            repository.deleteAllInBatch();
        }
    }
}
