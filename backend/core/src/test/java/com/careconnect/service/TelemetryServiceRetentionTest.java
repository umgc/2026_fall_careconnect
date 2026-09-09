package com.careconnect.service;

import com.careconnect.repository.TelemetryEventRepository;
import java.time.OffsetDateTime;
import java.time.temporal.ChronoUnit;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Unit tests for the telemetry retention purge added by PR #62 (WBS 2.4.1, Issue #3).
 *
 * <p>Scope note: these tests mock {@link TelemetryEventRepository}, so they exercise only the
 * cutoff arithmetic and the invocation/logging branches of {@code dropOld()}. They deliberately
 * cannot observe transaction semantics — the derived-delete transaction boundary is covered by
 * TC-TEL-RET-020 in {@code TelemetryEventRetentionRepositoryTest}.
 *
 * <p>Test IDs are permanent and must be reserved in the Software Test Plan when it is drafted.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("TelemetryService retention purge (PR #62)")
class TelemetryServiceRetentionTest {

    /** Retention window the service is configured with (careconnect.telemetry.memory.cleanup-after-days). */
    private static final int RETENTION_DAYS = 30;

    /** Tolerance for wall-clock drift between the service call and the assertion. */
    private static final long CLOCK_TOLERANCE_SECONDS = 30L;

    @Mock
    private TelemetryEventRepository repository;

    @Mock
    private TelemetryToggleService toggle;

    private TelemetryService telemetryService;

    @BeforeEach
    void setUp() {
        telemetryService = new TelemetryService(repository, toggle);
        ReflectionTestUtils.setField(telemetryService, "cleanupAfterDays", RETENTION_DAYS);
    }



    @Test
    @DisplayName("TC-TEL-RET-001: cutoff passed to the repository is now minus cleanupAfterDays days")
    void cutoffIsRetentionWindowBeforeNow() {
        final OffsetDateTime before = OffsetDateTime.now();
        when(repository.removeByEventTimeBefore(any())).thenReturn(0);

        telemetryService.dropOld();

        final OffsetDateTime after = OffsetDateTime.now();
        final ArgumentCaptor<OffsetDateTime> cutoff = ArgumentCaptor.forClass(OffsetDateTime.class);
        verify(repository).removeByEventTimeBefore(cutoff.capture());

        final OffsetDateTime expectedLowerBound =
                before.minusDays(RETENTION_DAYS)
                        .minusSeconds(CLOCK_TOLERANCE_SECONDS);
        final OffsetDateTime expectedUpperBound =
                after.minusDays(RETENTION_DAYS)
                        .plusSeconds(CLOCK_TOLERANCE_SECONDS);

        assertThat(cutoff.getValue()).isAfter(expectedLowerBound).isBefore(expectedUpperBound);
        assertThat(ChronoUnit.DAYS.between(cutoff.getValue(), after)).isEqualTo(RETENTION_DAYS);
    }

    @Test
    @DisplayName("TC-TEL-RET-002: rows removed - repository invoked exactly once")
    void invokesRepositoryOnceWhenRowsRemoved() {
        when(repository.removeByEventTimeBefore(any())).thenReturn(5);

        telemetryService.dropOld();

        verify(repository, times(1)).removeByEventTimeBefore(any());
    }

    @Test
    @DisplayName("TC-TEL-RET-003: zero rows removed - still invoked once, no exception")
    void handlesZeroRemovedWithoutError() {
        when(repository.removeByEventTimeBefore(any())).thenReturn(0);

        assertThatCode(() -> telemetryService.dropOld()).doesNotThrowAnyException();

        verify(repository, times(1)).removeByEventTimeBefore(any());
    }

    @Test
    @DisplayName("TC-TEL-RET-004: negative path - repository failure propagates uncaught")
    void repositoryFailurePropagates() {
        when(repository.removeByEventTimeBefore(any()))
                .thenThrow(new IllegalStateException("simulated purge failure"));

        // Documents current behaviour: no try/catch, no retry, no dead-letter. The exception
        // escapes onto the scheduler thread. Contrast TranscriptArchiveDeletionWorker, which
        // catches RuntimeException and retries or dead-letters.
        assertThatThrownBy(() -> telemetryService.dropOld())
                .isInstanceOf(IllegalStateException.class)
                .hasMessage("simulated purge failure");
    }

    @Test
    @DisplayName("TC-TEL-RET-005: purge ignores the telemetry capture toggle")
    void purgeRunsRegardlessOfCaptureToggle() {
        when(repository.removeByEventTimeBefore(any())).thenReturn(3);

        telemetryService.dropOld();

        // Observed behaviour: record() gates on the toggle, dropOld() does not consult it at all.
        // Defensible, but unspecified — raised with the author for a requirement, not assumed.
        verifyNoInteractions(toggle);
        verify(repository, times(1)).removeByEventTimeBefore(any());
    }
}
