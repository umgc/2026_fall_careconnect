package com.careconnect.service.evv;

import com.careconnect.model.Patient;
import com.careconnect.model.evv.EvvRecord;
import com.careconnect.repository.evv.EvvRecordRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class HhaExchangeBatchSubmissionServiceTest {

    @Mock private VirginiaHhaExchangeClient hhaClient;
    @Mock private EvvRecordRepository evvRecordRepository;
    @Mock private AuditLogger audit;

    @InjectMocks private HhaExchangeBatchSubmissionService service;

    // ─── buildPayload() ───────────────────────────────────────────────────────

    @Test
    void buildPayload_eligibleRecord_returnsHhaClientRequest() throws Exception {
        EvvRecord rec = approvedVaRecord(20L, false);
        com.careconnect.dto.evv.hhaexchange.HhaExchangeVisitRequest expectedRequest =
                new com.careconnect.dto.evv.hhaexchange.HhaExchangeVisitRequest();
        when(evvRecordRepository.findAllByIdWithPatient(List.of(20L))).thenReturn(List.of(rec));
        when(hhaClient.buildRequest(List.of(rec))).thenReturn(expectedRequest);

        Object result = service.buildPayload(List.of(20L));

        assertThat(result).isSameAs(expectedRequest);
    }

    @Test
    void buildPayload_noEligibleRecords_throwsIllegalArgument() {
        when(evvRecordRepository.findAllByIdWithPatient(List.of(21L))).thenReturn(List.of());

        assertThatThrownBy(() -> service.buildPayload(List.of(21L)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("No eligible VA/APPROVED records");
    }

    @Test
    void buildPayload_nonVaRecord_isExcluded() {
        EvvRecord mdRecord = approvedVaRecord(22L, false);
        mdRecord.setStateCode("MD");
        when(evvRecordRepository.findAllByIdWithPatient(List.of(22L))).thenReturn(List.of(mdRecord));

        assertThatThrownBy(() -> service.buildPayload(List.of(22L)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("No eligible VA/APPROVED records");
    }

    @Test
    void buildPayload_notApprovedRecord_isExcluded() {
        EvvRecord rec = approvedVaRecord(23L, false);
        rec.setStatus("UNDER_REVIEW");
        when(evvRecordRepository.findAllByIdWithPatient(List.of(23L))).thenReturn(List.of(rec));

        assertThatThrownBy(() -> service.buildPayload(List.of(23L)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("No eligible VA/APPROVED records");
    }

    @Test
    void buildPayload_hhaClientThrows_propagatesException() throws Exception {
        EvvRecord rec = approvedVaRecord(24L, false);
        when(evvRecordRepository.findAllByIdWithPatient(List.of(24L))).thenReturn(List.of(rec));
        when(hhaClient.buildRequest(List.of(rec))).thenThrow(new RuntimeException("bad payload"));

        assertThatThrownBy(() -> service.buildPayload(List.of(24L)))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("bad payload");
    }

    // ─── getPayloadJson() ─────────────────────────────────────────────────────

    @Test
    void getPayloadJson_eligibleRecord_returnsClientJson() throws Exception {
        EvvRecord rec = approvedVaRecord(25L, false);
        when(evvRecordRepository.findAllByIdWithPatient(List.of(25L))).thenReturn(List.of(rec));
        when(hhaClient.getPayloadJson(List.of(rec))).thenReturn("{\"json\":true}");

        String json = service.getPayloadJson(List.of(25L));

        assertThat(json).isEqualTo("{\"json\":true}");
    }

    @Test
    void getPayloadJson_noEligibleRecords_throwsIllegalArgument() {
        when(evvRecordRepository.findAllByIdWithPatient(List.of(26L))).thenReturn(List.of());

        assertThatThrownBy(() -> service.getPayloadJson(List.of(26L)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("No eligible VA/APPROVED records");
    }

    @Test
    void getPayloadJson_nonVaRecord_isExcluded() {
        EvvRecord mdRecord = approvedVaRecord(27L, false);
        mdRecord.setStateCode("MD");
        when(evvRecordRepository.findAllByIdWithPatient(List.of(27L))).thenReturn(List.of(mdRecord));

        assertThatThrownBy(() -> service.getPayloadJson(List.of(27L)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("No eligible VA/APPROVED records");
    }

    @Test
    void getPayloadJson_notApprovedRecord_isExcluded() {
        EvvRecord rec = approvedVaRecord(28L, false);
        rec.setStatus("UNDER_REVIEW");
        when(evvRecordRepository.findAllByIdWithPatient(List.of(28L))).thenReturn(List.of(rec));

        assertThatThrownBy(() -> service.getPayloadJson(List.of(28L)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("No eligible VA/APPROVED records");
    }

    // ─── submitBatch() ────────────────────────────────────────────────────────

    @Test
    void submitBatch_eligibleRecord_callsHhaClientAndAudit() throws Exception {
        EvvRecord rec = approvedVaRecord(1L, false);
        when(evvRecordRepository.findAllByIdWithPatient(List.of(1L))).thenReturn(List.of(rec));

        service.submitBatch(List.of(1L), 99L);

        verify(hhaClient).submitBatch(List.of(rec));
        verify(audit).log(eq(rec), eq(99L), eq("HHAEXCHANGE_SUBMITTED"), any());
    }

    @Test
    void submitBatch_nonVaRecord_isExcluded() {
        EvvRecord mdRecord = approvedVaRecord(2L, false);
        mdRecord.setStateCode("MD");
        when(evvRecordRepository.findAllByIdWithPatient(List.of(2L))).thenReturn(List.of(mdRecord));

        assertThatThrownBy(() -> service.submitBatch(List.of(2L), 99L))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("No eligible VA/APPROVED records");
    }

    @Test
    void submitBatch_notApprovedRecord_isExcluded() {
        EvvRecord rec = approvedVaRecord(3L, false);
        rec.setStatus("UNDER_REVIEW");
        when(evvRecordRepository.findAllByIdWithPatient(List.of(3L))).thenReturn(List.of(rec));

        assertThatThrownBy(() -> service.submitBatch(List.of(3L), 99L))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("No eligible VA/APPROVED records");
    }

    @Test
    void submitBatch_emptyIdList_throwsIllegalArgument() {
        when(evvRecordRepository.findAllByIdWithPatient(List.of())).thenReturn(List.of());

        assertThatThrownBy(() -> service.submitBatch(List.of(), 99L))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void submitBatch_hhaClientThrows_auditLogsFailureAndRethrows() throws Exception {
        EvvRecord rec = approvedVaRecord(4L, false);
        when(evvRecordRepository.findAllByIdWithPatient(List.of(4L))).thenReturn(List.of(rec));
        doThrow(new RuntimeException("timeout")).when(hhaClient).submitBatch(anyList());

        assertThatThrownBy(() -> service.submitBatch(List.of(4L), 99L))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("timeout");

        verify(audit).log(eq(rec), eq(99L), eq("HHAEXCHANGE_SUBMISSION_FAILED"), any());
    }

    // ─── resubmitCorrected() ─────────────────────────────────────────────────

    @Test
    void resubmitCorrected_correctedVaRecord_callsHhaClientAndAudit() throws Exception {
        EvvRecord rec = approvedVaRecord(5L, true);
        when(evvRecordRepository.findByIdWithPatient(5L)).thenReturn(Optional.of(rec));

        service.resubmitCorrected(5L, 99L);

        verify(hhaClient).submitBatch(List.of(rec));
        verify(audit).log(eq(rec), eq(99L), eq("HHAEXCHANGE_RESUBMITTED"), any());
    }

    @Test
    void resubmitCorrected_recordNotFound_throwsIllegalArgument() {
        when(evvRecordRepository.findByIdWithPatient(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.resubmitCorrected(99L, 1L))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("not found");
    }

    @Test
    void resubmitCorrected_notCorrectedRecord_throwsIllegalArgument() {
        EvvRecord rec = approvedVaRecord(6L, false); // isCorrected = false
        when(evvRecordRepository.findByIdWithPatient(6L)).thenReturn(Optional.of(rec));

        assertThatThrownBy(() -> service.resubmitCorrected(6L, 1L))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("no correction on file");
    }

    @Test
    void resubmitCorrected_nonVaRecord_throwsIllegalState() {
        EvvRecord rec = approvedVaRecord(7L, true);
        rec.setStateCode("MD");
        when(evvRecordRepository.findByIdWithPatient(7L)).thenReturn(Optional.of(rec));

        assertThatThrownBy(() -> service.resubmitCorrected(7L, 1L))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("only applicable to Virginia");
    }

    @Test
    void resubmitCorrected_nullCorrectionReasonCode_auditsWithEmptyString() throws Exception {
        EvvRecord rec = approvedVaRecord(9L, true);
        rec.setCorrectionReasonCode(null);
        when(evvRecordRepository.findByIdWithPatient(9L)).thenReturn(Optional.of(rec));

        service.resubmitCorrected(9L, 99L);

        org.mockito.ArgumentCaptor<java.util.Map> captor = org.mockito.ArgumentCaptor.forClass(java.util.Map.class);
        verify(audit).log(eq(rec), eq(99L), eq("HHAEXCHANGE_RESUBMITTED"), captor.capture());
        assertThat(captor.getValue()).containsEntry("correctionReasonCode", "");
    }

    @Test
    void resubmitCorrected_hhaClientThrows_auditLogsFailureAndRethrows() throws Exception {
        EvvRecord rec = approvedVaRecord(8L, true);
        when(evvRecordRepository.findByIdWithPatient(8L)).thenReturn(Optional.of(rec));
        doThrow(new RuntimeException("connection refused")).when(hhaClient).submitBatch(anyList());

        assertThatThrownBy(() -> service.resubmitCorrected(8L, 99L))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("connection refused");

        verify(audit).log(eq(rec), eq(99L), eq("HHAEXCHANGE_RESUBMISSION_FAILED"), any());
    }

    // ─── submitOfflineRecords() ───────────────────────────────────────────────

    @Test
    void submitOfflineRecords_approvedVaOfflineRecord_submitsAndReturnsCount() throws Exception {
        EvvRecord rec = approvedVaRecord(10L, false);
        rec.setIsOffline(true);
        rec.setSyncStatus("SYNCED");

        when(evvRecordRepository.findByIsOfflineTrue()).thenReturn(List.of(rec));
        when(evvRecordRepository.findBySyncStatus("SYNCED")).thenReturn(List.of());

        int count = service.submitOfflineRecords(99L);

        assertThat(count).isEqualTo(1);
        verify(hhaClient).submitBatch(List.of(rec));
        verify(audit).log(eq(rec), eq(99L), eq("HHAEXCHANGE_OFFLINE_SUBMITTED"), any());
    }

    @Test
    void submitOfflineRecords_noEligibleRecords_returnsZero() throws Exception {
        when(evvRecordRepository.findByIsOfflineTrue()).thenReturn(List.of());
        when(evvRecordRepository.findBySyncStatus("SYNCED")).thenReturn(List.of());

        int count = service.submitOfflineRecords(99L);

        assertThat(count).isEqualTo(0);
        verifyNoInteractions(hhaClient);
    }

    @Test
    void submitOfflineRecords_nonVaOfflineRecord_isExcluded() throws Exception {
        EvvRecord mdRecord = approvedVaRecord(11L, false);
        mdRecord.setStateCode("MD");
        mdRecord.setIsOffline(true);

        when(evvRecordRepository.findByIsOfflineTrue()).thenReturn(List.of(mdRecord));
        when(evvRecordRepository.findBySyncStatus("SYNCED")).thenReturn(List.of());

        int count = service.submitOfflineRecords(99L);

        assertThat(count).isEqualTo(0);
        verifyNoInteractions(hhaClient);
    }

    @Test
    void submitOfflineRecords_hhaClientThrows_auditLogsFailureAndRethrows() throws Exception {
        EvvRecord rec = approvedVaRecord(12L, false);
        rec.setIsOffline(true);

        when(evvRecordRepository.findByIsOfflineTrue()).thenReturn(List.of(rec));
        when(evvRecordRepository.findBySyncStatus("SYNCED")).thenReturn(List.of());
        doThrow(new RuntimeException("aggregator down")).when(hhaClient).submitBatch(anyList());

        assertThatThrownBy(() -> service.submitOfflineRecords(99L))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("aggregator down");

        verify(audit).log(eq(rec), eq(99L), eq("HHAEXCHANGE_OFFLINE_SUBMISSION_FAILED"), any());
    }

    @Test
    void submitOfflineRecords_deduplicatesOverlappingOfflineAndSyncedRecords() throws Exception {
        // Same record appears in both findByIsOfflineTrue and findBySyncStatus — should submit once
        EvvRecord rec = approvedVaRecord(13L, false);
        rec.setIsOffline(true);
        rec.setSyncStatus("SYNCED");

        when(evvRecordRepository.findByIsOfflineTrue()).thenReturn(List.of(rec));
        when(evvRecordRepository.findBySyncStatus("SYNCED")).thenReturn(List.of(rec));

        int count = service.submitOfflineRecords(99L);

        assertThat(count).isEqualTo(1);
        // submitBatch called with exactly one unique record
        verify(hhaClient, times(1)).submitBatch(argThat(list -> list.size() == 1));
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private EvvRecord approvedVaRecord(Long id, boolean corrected) {
        Patient patient = new Patient();
        patient.setMaNumber("MA" + id);

        EvvRecord rec = new EvvRecord();
        rec.setId(id);
        rec.setCaregiverId(7L);
        rec.setServiceType("Personal Care");
        rec.setStateCode("VA");
        rec.setStatus("APPROVED");
        rec.setIndividualName("Jane Doe");
        rec.setDateOfService(LocalDate.of(2026, 3, 20));
        rec.setTimeIn(OffsetDateTime.parse("2026-03-20T09:00:00-05:00"));
        rec.setTimeOut(OffsetDateTime.parse("2026-03-20T11:00:00-05:00"));
        rec.setPatient(patient);
        rec.setCreatedAt(OffsetDateTime.now());
        rec.setUpdatedAt(OffsetDateTime.now());
        rec.setIsOffline(false);
        rec.setEorApprovalRequired(false);
        rec.setIsCorrected(corrected);
        if (corrected) {
            rec.setCorrectionReasonCode("TIME_ERROR");
        }
        return rec;
    }
}
