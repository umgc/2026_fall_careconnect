package com.careconnect.service.ehr;

import com.careconnect.repository.ehr.EhrAuditEventRepository;
import com.careconnect.repository.ehr.EhrCoverageRecordRepository;
import com.careconnect.repository.ehr.EhrIdentityConflictRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceIdentityRepository;
import com.careconnect.repository.ehr.EhrVisitRecordRepository;
import com.careconnect.repository.ehr.PatientDateOfBirth;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
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
 * The retention rule of issue #214: purge a row once it is more than 7 years old and the patient
 * has reached age 25 (Maryland Health-General § 4-403), across the PHI-bearing {@code ehr_*} tables.
 * <p>
 * The age logic is shared by every table, so it is exercised once, through
 * {@code ehr_raw_payload} (TC-EHR-RAW). TC-EHR-RET covers what differs per table.
 * <p>
 * Test IDs TC-EHR-RAW-004..006 and 008..012, and TC-EHR-RET-001..004 and 010, are permanent. Never
 * renumber, never reuse. The queries themselves are checked on PostgreSQL: TC-EHR-RAW-007 in
 * {@code EhrRawPayloadPostgresJsonbTest}, TC-EHR-RET-005..007 in
 * {@code EhrRetentionQueriesPostgresTest}.
 */
@ExtendWith(MockitoExtension.class)
class EhrRetentionWorkerTest {

    private static final OffsetDateTime NOW = OffsetDateTime.parse("2026-10-02T12:00:00Z");
    private static final OffsetDateTime CUTOFF = NOW.minusYears(7);
    private static final Instant CUTOFF_INSTANT = CUTOFF.toInstant();
    private static final LocalDateTime CUTOFF_LOCAL =
            LocalDateTime.ofInstant(CUTOFF.toInstant(), ZoneId.systemDefault());

    @Mock
    EhrRawPayloadRepository rawPayloads;
    @Mock
    EhrIdentityConflictRepository conflicts;
    @Mock
    EhrSourceIdentityRepository sourceIdentities;
    @Mock
    EhrAuditEventRepository auditEvents;
    @Mock
    EhrCoverageRecordRepository coverages;
    @Mock
    EhrVisitRecordRepository visits;

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

    private EhrRetentionWorker worker(final int years, final int untilAge) {
        return new EhrRetentionWorker(rawPayloads, conflicts, sourceIdentities, auditEvents, coverages, visits,
                years, untilAge);
    }

    private EhrRetentionWorker worker() {
        return worker(7, 25);
    }

    private void rawPayloadCandidates(final PatientDateOfBirth... patients) {
        when(rawPayloads.findPatientsWithPayloadRetrievedBefore(CUTOFF)).thenReturn(List.of(patients));
    }

    // ---- The age rule, exercised through ehr_raw_payload ----

    @Test
    @DisplayName("TC-EHR-RAW-004: payloads of an adult retrieved more than 7 years ago are deleted")
    void purgesAdultPastRetentionPeriod() {
        rawPayloadCandidates(patient(1L, "1950-03-09"));
        when(rawPayloads.deleteRetrievedBeforeForPatients(CUTOFF, List.of(1L))).thenReturn(7);

        assertThat(worker().purgeExpired(NOW)).isEqualTo(7);
        verify(rawPayloads).deleteRetrievedBeforeForPatients(CUTOFF, List.of(1L));
    }

    @Test
    @DisplayName("TC-EHR-RAW-005: years=0 turns the purge off and no table is read or deleted from")
    void offPurgesNothing() {
        assertThat(worker(0, 25).purgeExpired(NOW)).isZero();
        verifyNoInteractions(rawPayloads, conflicts, sourceIdentities, auditEvents, coverages, visits);
    }

    @Test
    @DisplayName("TC-EHR-RAW-006: a negative period is off, never a cutoff in the future")
    void negativePeriodIsOff() {
        // now.minusYears(-5) is five years ahead: every row would be older than it.
        assertThat(worker(-5, 25).purgeExpired(NOW)).isZero();
        verifyNoInteractions(rawPayloads, conflicts, sourceIdentities, auditEvents, coverages, visits);
    }

    @Test
    @DisplayName("TC-EHR-RAW-008: a patient under 25 keeps payloads even when they are more than 7 years old")
    void keepsRecordOfMinorUntilAge25() {
        // Born 2010: the payload was retrieved when they were a child, and they are 16 now.
        rawPayloadCandidates(patient(2L, "2010-05-01"));

        assertThat(worker().purgeExpired(NOW)).isZero();
        verify(rawPayloads, never()).deleteRetrievedBeforeForPatients(any(), anyList());
    }

    @Test
    @DisplayName("TC-EHR-RAW-009: the 25th birthday is the first day the payloads may go, not the day before")
    void ageBoundaryIsTheBirthday() {
        rawPayloadCandidates(patient(3L, "2001-10-02"), patient(4L, "2001-10-03"));
        when(rawPayloads.deleteRetrievedBeforeForPatients(CUTOFF, List.of(3L))).thenReturn(1);

        assertThat(worker().purgeExpired(NOW)).isEqualTo(1);
        verify(rawPayloads).deleteRetrievedBeforeForPatients(CUTOFF, List.of(3L));
    }

    @Test
    @DisplayName("TC-EHR-RAW-010: a missing or unreadable date of birth is unknown, and unknown is kept")
    void unknownDateOfBirthIsKept() {
        rawPayloadCandidates(patient(5L, null), patient(6L, ""), patient(7L, "March 9, 1950"));

        assertThat(worker().purgeExpired(NOW)).isZero();
        verify(rawPayloads, never()).deleteRetrievedBeforeForPatients(any(), anyList());
    }

    @Test
    @DisplayName("TC-EHR-RAW-011: a date of birth stored as MM/DD/YYYY is read the same as ISO")
    void readsBothStoredDateShapes() {
        rawPayloadCandidates(patient(8L, "03/09/1950"), patient(9L, "05/01/2010"));
        when(rawPayloads.deleteRetrievedBeforeForPatients(CUTOFF, List.of(8L))).thenReturn(2);

        assertThat(worker().purgeExpired(NOW)).isEqualTo(2);
    }

    @Test
    @DisplayName("TC-EHR-RAW-012: eligible patients are deleted in bounded batches and the counts are summed")
    void deletesInBatches() {
        final List<PatientDateOfBirth> many = new ArrayList<>();
        for (long id = 1; id <= EhrRetentionWorker.DELETE_BATCH_SIZE + 1; id++) {
            many.add(patient(id, "1950-03-09"));
        }
        when(rawPayloads.findPatientsWithPayloadRetrievedBefore(CUTOFF)).thenReturn(many);
        when(rawPayloads.deleteRetrievedBeforeForPatients(eq(CUTOFF), anyList())).thenReturn(10, 3);

        assertThat(worker().purgeExpired(NOW)).isEqualTo(13);

        @SuppressWarnings("unchecked")
        final ArgumentCaptor<List<Long>> batches = ArgumentCaptor.forClass(List.class);
        verify(rawPayloads, times(2)).deleteRetrievedBeforeForPatients(eq(CUTOFF), batches.capture());
        assertThat(batches.getAllValues().get(0)).hasSize(EhrRetentionWorker.DELETE_BATCH_SIZE);
        assertThat(batches.getAllValues().get(1)).hasSize(1);
    }

    @Test
    @DisplayName("TC-EHR-RAW-013: a negative retain-until-age is a configuration error, not a silent default")
    void negativeAgeIsRejected() {
        assertThatThrownBy(() -> worker(7, -1)).isInstanceOf(IllegalArgumentException.class);
    }

    // ---- What differs per table ----

    @Test
    @DisplayName("TC-EHR-RET-001: resolved identity conflicts are purged on resolved_at, as an instant")
    void purgesResolvedConflicts() {
        when(conflicts.findPatientsWithConflictResolvedBefore(CUTOFF_INSTANT))
                .thenReturn(List.of(patient(1L, "1950-03-09"), patient(2L, "2010-05-01")));
        when(conflicts.deleteResolvedBeforeForPatients(CUTOFF_INSTANT, List.of(1L))).thenReturn(4);

        assertThat(worker().purgeExpired(NOW)).isEqualTo(4);
        verify(conflicts).deleteResolvedBeforeForPatients(CUTOFF_INSTANT, List.of(1L));
    }

    @Test
    @DisplayName("TC-EHR-RET-002: source identity snapshots are purged on updated_at, in the zone Auditable writes")
    void purgesSourceIdentitySnapshots() {
        when(sourceIdentities.findPatientsWithSnapshotUpdatedBefore(CUTOFF_LOCAL))
                .thenReturn(List.of(patient(1L, "1950-03-09")));
        when(sourceIdentities.deleteUpdatedBeforeForPatients(CUTOFF_LOCAL, List.of(1L))).thenReturn(2);

        assertThat(worker().purgeExpired(NOW)).isEqualTo(2);
    }

    @Test
    @DisplayName("TC-EHR-RET-003: audit events are purged on event_time, and an event with no patient row is kept")
    void purgesAuditEventsButKeepsOrphans() {
        // ehr_audit_event has no foreign key to patient; a missing patient row arrives as a null dob.
        when(auditEvents.findPatientsWithEventBefore(CUTOFF))
                .thenReturn(List.of(patient(1L, "1950-03-09"), patient(99L, null)));
        when(auditEvents.deleteEventsBeforeForPatients(CUTOFF, List.of(1L))).thenReturn(5);

        assertThat(worker().purgeExpired(NOW)).isEqualTo(5);
        verify(auditEvents).deleteEventsBeforeForPatients(CUTOFF, List.of(1L));
    }

    @Test
    @DisplayName("TC-EHR-RET-004: one run covers all six tables and returns the total")
    void oneRunCoversEveryTable() {
        final PatientDateOfBirth adult = patient(1L, "1950-03-09");
        when(rawPayloads.findPatientsWithPayloadRetrievedBefore(CUTOFF)).thenReturn(List.of(adult));
        when(conflicts.findPatientsWithConflictResolvedBefore(CUTOFF_INSTANT)).thenReturn(List.of(adult));
        when(sourceIdentities.findPatientsWithSnapshotUpdatedBefore(CUTOFF_LOCAL)).thenReturn(List.of(adult));
        when(auditEvents.findPatientsWithEventBefore(CUTOFF)).thenReturn(List.of(adult));
        when(coverages.findPatientsWithCoverageUpdatedBefore(CUTOFF_LOCAL)).thenReturn(List.of(adult));
        when(visits.findPatientsWithVisitUpdatedBefore(CUTOFF_LOCAL)).thenReturn(List.of(adult));
        when(rawPayloads.deleteRetrievedBeforeForPatients(CUTOFF, List.of(1L))).thenReturn(1);
        when(conflicts.deleteResolvedBeforeForPatients(CUTOFF_INSTANT, List.of(1L))).thenReturn(2);
        when(sourceIdentities.deleteUpdatedBeforeForPatients(CUTOFF_LOCAL, List.of(1L))).thenReturn(3);
        when(auditEvents.deleteEventsBeforeForPatients(CUTOFF, List.of(1L))).thenReturn(4);
        when(coverages.deleteUpdatedBeforeForPatients(CUTOFF_LOCAL, List.of(1L))).thenReturn(5);
        when(visits.deleteUpdatedBeforeForPatients(CUTOFF_LOCAL, List.of(1L))).thenReturn(6);

        assertThat(worker().purgeExpired(NOW)).isEqualTo(21);
    }

    @Test
    @DisplayName("TC-EHR-RET-010: coverage and visit records are purged on updated_at, in the zone Auditable writes")
    void purgesCoverageAndVisitRecords() {
        when(coverages.findPatientsWithCoverageUpdatedBefore(CUTOFF_LOCAL))
                .thenReturn(List.of(patient(1L, "1950-03-09"), patient(2L, "2010-05-01")));
        when(visits.findPatientsWithVisitUpdatedBefore(CUTOFF_LOCAL))
                .thenReturn(List.of(patient(1L, "1950-03-09")));
        when(coverages.deleteUpdatedBeforeForPatients(CUTOFF_LOCAL, List.of(1L))).thenReturn(2);
        when(visits.deleteUpdatedBeforeForPatients(CUTOFF_LOCAL, List.of(1L))).thenReturn(3);

        assertThat(worker().purgeExpired(NOW)).isEqualTo(5);
        // The patient under 25 keeps their coverage.
        verify(coverages).deleteUpdatedBeforeForPatients(CUTOFF_LOCAL, List.of(1L));
    }
}
