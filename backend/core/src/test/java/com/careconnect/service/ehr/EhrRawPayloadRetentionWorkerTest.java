package com.careconnect.service.ehr;

import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.OffsetDateTime;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Test IDs TC-EHR-RAW-004..006 are permanent. Never renumber, never reuse.
 */
@ExtendWith(MockitoExtension.class)
class EhrRawPayloadRetentionWorkerTest {

    private static final OffsetDateTime NOW = OffsetDateTime.parse("2026-10-01T12:00:00Z");

    @Mock
    EhrRawPayloadRepository repository;

    @Test
    @DisplayName("TC-EHR-RAW-004: a configured period deletes payloads retrieved before now minus that period")
    void purgeExpired_deletesBeforeCutoff() {
        when(repository.deleteRetrievedBefore(NOW.minusDays(30))).thenReturn(7);

        final int deleted = new EhrRawPayloadRetentionWorker(repository, 30).purgeExpired(NOW);

        assertThat(deleted).isEqualTo(7);
        verify(repository).deleteRetrievedBefore(NOW.minusDays(30));
    }

    @Test
    @DisplayName("TC-EHR-RAW-005: the default of 0 purges nothing, because no retention period has been decided")
    void purgeExpired_doesNothingWhenUnconfigured() {
        final int deleted = new EhrRawPayloadRetentionWorker(repository, 0).purgeExpired(NOW);

        assertThat(deleted).isZero();
        verifyNoInteractions(repository);
    }

    @Test
    @DisplayName("TC-EHR-RAW-006: a negative period is treated as unconfigured, never as a cutoff in the future")
    void purgeExpired_doesNothingForNegativePeriod() {
        // now.minusDays(-5) is five days ahead: every row would be older than it and be deleted.
        final int deleted = new EhrRawPayloadRetentionWorker(repository, -5).purgeExpired(NOW);

        assertThat(deleted).isZero();
        verifyNoInteractions(repository);
    }
}
