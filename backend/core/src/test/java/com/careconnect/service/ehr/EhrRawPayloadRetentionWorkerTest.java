package com.careconnect.service.ehr;

import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository.PatientDateOfBirth;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * The retention rule of issue #214: purge a payload once it was retrieved more than 7 years ago
 * and the patient has reached age 25 (Maryland Health-General § 4-403).
 * <p>
 * Test IDs TC-EHR-RAW-004..006 and 008..012 are permanent. Never renumber, never reuse.
 * (007 is the PostgreSQL case in {@code EhrRawPayloadPostgresJsonbTest}.)
 */
@ExtendWith(MockitoExtension.class)
class EhrRawPayloadRetentionWorkerTest {

    private static final OffsetDateTime NOW = OffsetDateTime.parse("2026-10-02T12:00:00Z");
    private static final OffsetDateTime CUTOFF = NOW.minusYears(7);

    @Mock
    EhrRawPayloadRepository repository;

    private static PatientDateOfBirth patient(final long id, final String dob) {
        return new PatientDateOfBirth() {
            @Override
            public Long getPatientId() {
                return id;
            }

            @Override
            public String getDob() {
                return dob;
            }
        };
    }

    private EhrRawPayloadRetentionWorker worker() {
        return new EhrRawPayloadRetentionWorker(repository, 7, 25);
    }

    private void candidates(final PatientDateOfBirth... patients) {
        when(repository.findPatientsWithPayloadRetrievedBefore(CUTOFF)).thenReturn(List.of(patients));
    }

    @Test
    @DisplayName("TC-EHR-RAW-004: payloads of an adult retrieved more than 7 years ago are deleted")
    void purgesAdultPastRetentionPeriod() {
        candidates(patient(1L, "1950-03-09"));
        when(repository.deleteRetrievedBeforeForPatients(CUTOFF, List.of(1L))).thenReturn(7);

        assertThat(worker().purgeExpired(NOW)).isEqualTo(7);
        verify(repository).deleteRetrievedBeforeForPatients(CUTOFF, List.of(1L));
    }

    @Test
    @DisplayName("TC-EHR-RAW-005: retention-years=0 turns the purge off and nothing is read or deleted")
    void offPurgesNothing() {
        assertThat(new EhrRawPayloadRetentionWorker(repository, 0, 25).purgeExpired(NOW)).isZero();
        verifyNoInteractions(repository);
    }

    @Test
    @DisplayName("TC-EHR-RAW-006: a negative period is off, never a cutoff in the future")
    void negativePeriodIsOff() {
        // now.minusYears(-5) is five years ahead: every row would be older than it.
        assertThat(new EhrRawPayloadRetentionWorker(repository, -5, 25).purgeExpired(NOW)).isZero();
        verifyNoInteractions(repository);
    }

    @Test
    @DisplayName("TC-EHR-RAW-008: a patient under 25 keeps payloads even when they are more than 7 years old")
    void keepsRecordOfMinorUntilAge25() {
        // Born 2010: the payload was retrieved when they were a child, and they are 16 now.
        candidates(patient(2L, "2010-05-01"));

        assertThat(worker().purgeExpired(NOW)).isZero();
        verify(repository, never()).deleteRetrievedBeforeForPatients(any(), anyList());
    }

    @Test
    @DisplayName("TC-EHR-RAW-009: the 25th birthday is the first day the payloads may go, not the day before")
    void ageBoundaryIsTheBirthday() {
        candidates(patient(3L, "2001-10-02"), patient(4L, "2001-10-03"));
        when(repository.deleteRetrievedBeforeForPatients(CUTOFF, List.of(3L))).thenReturn(1);

        assertThat(worker().purgeExpired(NOW)).isEqualTo(1);
        verify(repository).deleteRetrievedBeforeForPatients(CUTOFF, List.of(3L));
    }

    @Test
    @DisplayName("TC-EHR-RAW-010: a missing or unreadable date of birth is unknown, and unknown is kept")
    void unknownDateOfBirthIsKept() {
        candidates(patient(5L, null), patient(6L, ""), patient(7L, "March 9, 1950"));

        assertThat(worker().purgeExpired(NOW)).isZero();
        verify(repository, never()).deleteRetrievedBeforeForPatients(any(), anyList());
    }

    @Test
    @DisplayName("TC-EHR-RAW-011: a date of birth stored as MM/DD/YYYY is read the same as ISO")
    void readsBothStoredDateShapes() {
        candidates(patient(8L, "03/09/1950"), patient(9L, "05/01/2010"));
        when(repository.deleteRetrievedBeforeForPatients(CUTOFF, List.of(8L))).thenReturn(2);

        assertThat(worker().purgeExpired(NOW)).isEqualTo(2);
    }

    @Test
    @DisplayName("TC-EHR-RAW-012: eligible patients are deleted in bounded batches and the counts are summed")
    void deletesInBatches() {
        final List<PatientDateOfBirth> many = new ArrayList<>();
        for (long id = 1; id <= EhrRawPayloadRetentionWorker.DELETE_BATCH_SIZE + 1; id++) {
            many.add(patient(id, "1950-03-09"));
        }
        when(repository.findPatientsWithPayloadRetrievedBefore(CUTOFF)).thenReturn(many);
        when(repository.deleteRetrievedBeforeForPatients(eq(CUTOFF), anyList())).thenReturn(10, 3);

        assertThat(worker().purgeExpired(NOW)).isEqualTo(13);

        @SuppressWarnings("unchecked")
        final ArgumentCaptor<List<Long>> batches = ArgumentCaptor.forClass(List.class);
        verify(repository, times(2)).deleteRetrievedBeforeForPatients(eq(CUTOFF), batches.capture());
        assertThat(batches.getAllValues().get(0)).hasSize(EhrRawPayloadRetentionWorker.DELETE_BATCH_SIZE);
        assertThat(batches.getAllValues().get(1)).hasSize(1);
    }

    @Test
    @DisplayName("a negative retain-until-age is a configuration error, not a silent default")
    void negativeAgeIsRejected() {
        assertThatThrownBy(() -> new EhrRawPayloadRetentionWorker(repository, 7, -1))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
