package com.careconnect.model.evv;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;
import java.util.Map;

@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(name = "evv_offline_queue")
public class EvvOfflineQueue {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "record_id", nullable = false)
    private Long recordId;

    @Column(name = "operation_type", nullable = false, length = 20) // CREATE|UPDATE|DELETE
    private String operationType;

    @Column(name = "caregiver_id", nullable = false)
    private Long caregiverId;

    @Column(name = "device_id", length = 100)
    private String deviceId;

    @Column(name = "queued_at", nullable = false)
    private OffsetDateTime queuedAt;

    @Column(name = "sync_attempts", nullable = false)
    @Builder.Default
    private Integer syncAttempts = 0;

    @Column(name = "last_sync_attempt")
    private OffsetDateTime lastSyncAttempt;

    @Column(name = "sync_status", nullable = false, length = 20) // PENDING|SYNCING|SYNCED|FAILED
    @Builder.Default
    private String syncStatus = "PENDING";

    @Column(name = "last_error")
    private String lastError;

    @Column(name = "priority", nullable = false)
    @Builder.Default
    private Integer priority = 1; // 1=normal, 2=high, 3=urgent

    // Store the full record data for offline operations
    @Convert(disableConversion = true)
    @Column(name = "record_data", columnDefinition = "jsonb")
    @JdbcTypeCode(SqlTypes.JSON)
    private Map<String, Object> recordData;

    @PrePersist
    void onCreate() {
        if (queuedAt == null) {
            queuedAt = OffsetDateTime.now();
        }
    }

    public void markSyncing() {
        this.syncStatus = "SYNCING";
        this.syncAttempts++;
        this.lastSyncAttempt = OffsetDateTime.now();
    }

    public void markSynced() {
        this.syncStatus = "SYNCED";
    }

    public void markFailed(String error) {
        this.syncStatus = "FAILED";
        this.lastError = error;
        this.lastSyncAttempt = OffsetDateTime.now();
    }
}

