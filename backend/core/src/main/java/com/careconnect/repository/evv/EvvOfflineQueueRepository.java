package com.careconnect.repository.evv;

import com.careconnect.model.evv.EvvOfflineQueue;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.OffsetDateTime;
import java.util.List;

@Repository
public interface EvvOfflineQueueRepository extends JpaRepository<EvvOfflineQueue, Long> {

    List<EvvOfflineQueue> findByCaregiverIdAndSyncStatus(Long caregiverId, String syncStatus);

    List<EvvOfflineQueue> findBySyncStatusOrderByPriorityDescQueuedAtAsc(String syncStatus);

    @Query("SELECT q FROM EvvOfflineQueue q WHERE q.syncStatus = 'PENDING' AND q.syncAttempts < :maxAttempts ORDER BY q.priority DESC, q.queuedAt ASC")
    List<EvvOfflineQueue> findPendingSyncItems(@Param("maxAttempts") Integer maxAttempts);

    @Query("SELECT q FROM EvvOfflineQueue q WHERE q.syncStatus = 'FAILED' AND q.lastSyncAttempt < :retryAfter ORDER BY q.priority DESC, q.queuedAt ASC")
    List<EvvOfflineQueue> findFailedItemsForRetry(@Param("retryAfter") OffsetDateTime retryAfter);

    @Query("SELECT q FROM EvvOfflineQueue q WHERE q.caregiverId = :caregiverId AND q.syncStatus IN ('PENDING', 'SYNCING') ORDER BY q.priority DESC, q.queuedAt ASC")
    List<EvvOfflineQueue> findPendingItemsByCaregiver(@Param("caregiverId") Long caregiverId);

    void deleteByRecordIdAndSyncStatus(Long recordId, String syncStatus);
}

