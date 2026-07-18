package com.careconnect.service.evv;

import com.careconnect.model.evv.EvvOfflineQueue;
import com.careconnect.model.evv.EvvRecord;
import com.careconnect.repository.evv.EvvOfflineQueueRepository;
import com.careconnect.repository.evv.EvvRecordRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.OffsetDateTime;
import java.util.Collections;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class EvvOfflineSyncServiceTest {

    @Mock
    private EvvOfflineQueueRepository offlineQueueRepository;

    @Mock
    private EvvRecordRepository recordRepository;

    @Mock
    private EvvSubmissionService submissionService;

    @Mock
    private AuditLogger audit;

    @InjectMocks
    private EvvOfflineSyncService evvOfflineSyncService;

    // ====== Helper builders ======

    private EvvOfflineQueue buildQueueItem(String operationType, Long recordId, Long caregiverId, int syncAttempts) {
        return EvvOfflineQueue.builder()
                .id(1L)
                .recordId(recordId)
                .operationType(operationType)
                .caregiverId(caregiverId)
                .syncAttempts(syncAttempts)
                .syncStatus("PENDING")
                .priority(1)
                .queuedAt(OffsetDateTime.now())
                .build();
    }

    private EvvRecord buildRecord(Long id) {
        return EvvRecord.builder()
                .id(id)
                .serviceType("HOME_HEALTH")
                .individualName("John Doe")
                .caregiverId(10L)
                .status("UNDER_REVIEW")
                .stateCode("DC")
                .isOffline(true)
                .syncStatus("PENDING")
                .eorApprovalRequired(false)
                .isCorrected(false)
                .createdAt(OffsetDateTime.now())
                .updatedAt(OffsetDateTime.now())
                .build();
    }

    // ====== syncOfflineRecords tests ======

    @Test
    void syncOfflineRecords_noPendingItems_doesNothing() throws Exception {
        when(offlineQueueRepository.findPendingSyncItems(3)).thenReturn(Collections.emptyList());

        evvOfflineSyncService.syncOfflineRecords();

        verify(offlineQueueRepository, never()).save(any());
    }

    @Test
    void syncOfflineRecords_itemSyncSucceeds_savesRecord() throws Exception {
        final EvvOfflineQueue item = buildQueueItem("UPDATE", 1L, 10L, 0);
        final EvvRecord record = buildRecord(1L);

        when(offlineQueueRepository.findPendingSyncItems(3)).thenReturn(List.of(item));
        when(offlineQueueRepository.save(any(EvvOfflineQueue.class))).thenReturn(item);
        when(recordRepository.findById(1L)).thenReturn(Optional.of(record));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(record);
        doNothing().when(audit).log(any(), any(), any(), any());

        evvOfflineSyncService.syncOfflineRecords();

        verify(recordRepository).save(any(EvvRecord.class));
    }

    @Test
    void syncOfflineRecords_itemSyncFails_marksFailedAndSaves() throws Exception {
        final EvvOfflineQueue item = buildQueueItem("UPDATE", 999L, 10L, 0);

        when(offlineQueueRepository.findPendingSyncItems(3)).thenReturn(List.of(item));
        // First save call (markSyncing), then the inner failure path save
        when(offlineQueueRepository.save(any(EvvOfflineQueue.class))).thenReturn(item);
        when(recordRepository.findById(999L)).thenReturn(Optional.empty());

        evvOfflineSyncService.syncOfflineRecords();

        // The outer catch in syncOfflineRecords calls markFailed + save
        assertThat(item.getSyncStatus()).isEqualTo("FAILED");
        verify(offlineQueueRepository, atLeastOnce()).save(item);
    }

    @Test
    void syncOfflineRecords_outerException_doesNotPropagate() throws Exception {
        when(offlineQueueRepository.findPendingSyncItems(3))
                .thenThrow(new RuntimeException("DB down"));

        // Should swallow the exception
        evvOfflineSyncService.syncOfflineRecords();
    }

    // ====== syncQueueItem tests ======

    @Test
    void syncQueueItem_createOperation_marksSyncedAndSavesAsPendingReview() throws Exception {
        final EvvOfflineQueue item = buildQueueItem("CREATE", 1L, 10L, 0);
        final EvvRecord record = buildRecord(1L);

        when(offlineQueueRepository.save(any(EvvOfflineQueue.class))).thenReturn(item);
        when(recordRepository.findById(1L)).thenReturn(Optional.of(record));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(record);
        doNothing().when(audit).log(any(), any(), any(), any());

        evvOfflineSyncService.syncQueueItem(item);

        assertThat(record.getStatus()).isEqualTo("PENDING_REVIEW");
        assertThat(item.getSyncStatus()).isEqualTo("SYNCED");
    }

    @Test
    void syncQueueItem_withLocationFields_includesLocationDetailsInAuditLog() throws Exception {
        // Arrange: record carries legacy, check-in, and check-out location data —
        // existing tests above only ever sync records with every location field
        // null, leaving the "non-null" branch of each OR-condition unexercised.
        final EvvOfflineQueue item = buildQueueItem("UPDATE", 1L, 10L, 0);
        final EvvRecord record = buildRecord(1L);
        record.setLocationLat(38.9);
        record.setLocationLng(-77.0);
        record.setLocationSource("GPS");
        record.setCheckinLocationLat(38.91);
        record.setCheckinLocationLng(-77.01);
        record.setCheckoutLocationLat(38.92);
        record.setCheckoutLocationLng(-77.02);

        when(offlineQueueRepository.save(any(EvvOfflineQueue.class))).thenReturn(item);
        when(recordRepository.findById(1L)).thenReturn(Optional.of(record));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(record);
        doNothing().when(audit).log(any(), any(), any(), any());

        evvOfflineSyncService.syncQueueItem(item);

        final org.mockito.ArgumentCaptor<java.util.Map> captor =
                org.mockito.ArgumentCaptor.forClass(java.util.Map.class);
        verify(audit).log(eq(record), any(), eq("OFFLINE_SYNCED"), captor.capture());
        assertThat(captor.getValue())
                .containsEntry("locationLat", 38.9)
                .containsEntry("checkinLocationLat", 38.91)
                .containsEntry("checkoutLocationLat", 38.92);
    }

    @Test
    void syncQueueItem_createOperation_confirmedStatus_queuesForSubmission() throws Exception {
        final EvvOfflineQueue item = buildQueueItem("CREATE", 1L, 10L, 0);

        // Use a spy so we can override getStatus() after setStatus is called
        final EvvRecord record = spy(buildRecord(1L));

        when(offlineQueueRepository.save(any(EvvOfflineQueue.class))).thenReturn(item);
        when(recordRepository.findById(1L)).thenReturn(Optional.of(record));
        when(recordRepository.save(any(EvvRecord.class))).thenAnswer(inv -> {
            // After save, make getStatus() return "CONFIRMED"
            doReturn("CONFIRMED").when(record).getStatus();
            return record;
        });
        doNothing().when(submissionService).queueForSubmission(any(), any());
        doNothing().when(audit).log(any(), any(), any(), any());

        evvOfflineSyncService.syncQueueItem(item);

        verify(submissionService).queueForSubmission(eq(record), eq(10L));
    }

    @Test
    void syncQueueItem_updateOperation_marksSynced() throws Exception {
        final EvvOfflineQueue item = buildQueueItem("UPDATE", 1L, 10L, 0);
        final EvvRecord record = buildRecord(1L);

        when(offlineQueueRepository.save(any(EvvOfflineQueue.class))).thenReturn(item);
        when(recordRepository.findById(1L)).thenReturn(Optional.of(record));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(record);
        doNothing().when(audit).log(any(), any(), any(), any());

        evvOfflineSyncService.syncQueueItem(item);

        assertThat(item.getSyncStatus()).isEqualTo("SYNCED");
        verify(recordRepository).save(any(EvvRecord.class));
    }

    @Test
    void syncQueueItem_deleteOperation_doesNothing() throws Exception {
        final EvvOfflineQueue item = buildQueueItem("DELETE", 1L, 10L, 0);
        final EvvRecord record = buildRecord(1L);

        when(offlineQueueRepository.save(any(EvvOfflineQueue.class))).thenReturn(item);
        when(recordRepository.findById(1L)).thenReturn(Optional.of(record));
        doNothing().when(audit).log(any(), any(), any(), any());

        evvOfflineSyncService.syncQueueItem(item);

        // No record save for DELETE
        verify(recordRepository, never()).save(any(EvvRecord.class));
        assertThat(item.getSyncStatus()).isEqualTo("SYNCED");
    }

    @Test
    void syncQueueItem_recordNotFound_marksFailedAndRethrows() throws Exception {
        final EvvOfflineQueue item = buildQueueItem("UPDATE", 999L, 10L, 0);

        when(offlineQueueRepository.save(any(EvvOfflineQueue.class))).thenReturn(item);
        when(recordRepository.findById(999L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> evvOfflineSyncService.syncQueueItem(item))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("Record not found");

        assertThat(item.getSyncStatus()).isEqualTo("FAILED");
    }

    @Test
    void syncQueueItem_exception_marksFailedAndRethrows() throws Exception {
        final EvvOfflineQueue item = buildQueueItem("UPDATE", 1L, 10L, 0);
        final EvvRecord record = buildRecord(1L);

        when(offlineQueueRepository.save(any(EvvOfflineQueue.class))).thenReturn(item);
        when(recordRepository.findById(1L)).thenReturn(Optional.of(record));
        when(recordRepository.save(any(EvvRecord.class))).thenThrow(new RuntimeException("DB write failed"));

        assertThatThrownBy(() -> evvOfflineSyncService.syncQueueItem(item))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("DB write failed");

        assertThat(item.getSyncStatus()).isEqualTo("FAILED");
    }

    // ====== retryFailedSyncs tests ======

    @Test
    void retryFailedSyncs_itemBelowMaxAttempts_resetsToPending() throws Exception {
        final EvvOfflineQueue item = buildQueueItem("UPDATE", 1L, 10L, 1); // attempts = 1 < 3
        item.setSyncStatus("FAILED");

        when(offlineQueueRepository.findFailedItemsForRetry(any(OffsetDateTime.class)))
                .thenReturn(List.of(item));
        when(offlineQueueRepository.save(any(EvvOfflineQueue.class))).thenReturn(item);

        evvOfflineSyncService.retryFailedSyncs();

        assertThat(item.getSyncStatus()).isEqualTo("PENDING");
        verify(offlineQueueRepository).save(item);
    }

    @Test
    void retryFailedSyncs_itemAtMaxAttempts_skips() throws Exception {
        final EvvOfflineQueue item = buildQueueItem("UPDATE", 1L, 10L, 3); // attempts = 3 >= 3
        item.setSyncStatus("FAILED");

        when(offlineQueueRepository.findFailedItemsForRetry(any(OffsetDateTime.class)))
                .thenReturn(List.of(item));

        evvOfflineSyncService.retryFailedSyncs();

        // Should NOT reset to PENDING and should NOT save
        assertThat(item.getSyncStatus()).isEqualTo("FAILED");
        verify(offlineQueueRepository, never()).save(any());
    }

    // ====== syncCaregiverOfflineData tests ======

    @Test
    void syncCaregiverOfflineData_syncsAllItems() throws Exception {
        final Long caregiverId = 10L;
        final EvvOfflineQueue item = buildQueueItem("UPDATE", 1L, caregiverId, 0);
        final EvvRecord record = buildRecord(1L);

        when(offlineQueueRepository.findPendingItemsByCaregiver(caregiverId)).thenReturn(List.of(item));
        when(offlineQueueRepository.save(any(EvvOfflineQueue.class))).thenReturn(item);
        when(recordRepository.findById(1L)).thenReturn(Optional.of(record));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(record);
        doNothing().when(audit).log(any(), any(), any(), any());

        evvOfflineSyncService.syncCaregiverOfflineData(caregiverId);

        verify(recordRepository).save(any(EvvRecord.class));
    }

    @Test
    void syncCaregiverOfflineData_itemFails_continuesWithNext() throws Exception {
        final Long caregiverId = 10L;
        final EvvOfflineQueue failingItem = buildQueueItem("UPDATE", 999L, caregiverId, 0);
        final EvvOfflineQueue successItem = buildQueueItem("UPDATE", 1L, caregiverId, 0);
        successItem.setId(2L);

        final EvvRecord record = buildRecord(1L);

        when(offlineQueueRepository.findPendingItemsByCaregiver(caregiverId))
                .thenReturn(List.of(failingItem, successItem));
        when(offlineQueueRepository.save(any(EvvOfflineQueue.class))).thenReturn(failingItem);
        // First item: record not found → throws
        when(recordRepository.findById(999L)).thenReturn(Optional.empty());
        // Second item: record found → succeeds
        when(recordRepository.findById(1L)).thenReturn(Optional.of(record));
        when(recordRepository.save(any(EvvRecord.class))).thenReturn(record);
        doNothing().when(audit).log(any(), any(), any(), any());

        // Should not throw despite the first item failing
        evvOfflineSyncService.syncCaregiverOfflineData(caregiverId);

        verify(recordRepository).findById(1L);
    }

    // ====== getOfflineQueueStatus tests ======

    @Test
    void getOfflineQueueStatus_returnsRepositoryResult() throws Exception {
        final Long caregiverId = 10L;
        final EvvOfflineQueue item = buildQueueItem("CREATE", 1L, caregiverId, 0);

        when(offlineQueueRepository.findByCaregiverIdAndSyncStatus(caregiverId, "PENDING"))
                .thenReturn(List.of(item));

        final List<EvvOfflineQueue> result = evvOfflineSyncService.getOfflineQueueStatus(caregiverId);

        assertThat(result).hasSize(1);
        assertThat(result.get(0).getCaregiverId()).isEqualTo(caregiverId);
    }
}
