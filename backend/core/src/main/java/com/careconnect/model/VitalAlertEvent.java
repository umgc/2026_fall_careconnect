package com.careconnect.model;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;

@Entity
@Table(name = "vital_alert_event")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class VitalAlertEvent {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "patient_user_id", nullable = false)
    private Long patientUserId;

    @Column(name = "metric_type", nullable = false, length = 64)
    private String metricType;

    @Column(name = "measured_value", nullable = false, length = 64)
    private String measuredValue;

    @Column(name = "alert_level", nullable = false, length = 16)
    private String alertLevel;

    @Column(name = "status", nullable = false, length = 32)
    private String status;

    @Column(name = "recipient_count", nullable = false)
    private Integer recipientCount;

    @Column(name = "success_count", nullable = false)
    private Integer successCount;

    @Column(name = "failure_count", nullable = false)
    private Integer failureCount;

    @Column(name = "failure_reason", length = 255)
    private String failureReason;

    @Column(name = "occurred_at", nullable = false)
    private Instant occurredAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @PrePersist
    public void onCreate() {
        Instant now = Instant.now();
        if (occurredAt == null) {
            occurredAt = now;
        }
        if (createdAt == null) {
            createdAt = now;
        }
    }
}
