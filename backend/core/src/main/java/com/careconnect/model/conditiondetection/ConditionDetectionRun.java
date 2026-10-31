package com.careconnect.model.conditiondetection;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.UUID;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * One condition model's analysis of one call. The row is both the durable work item the
 * worker leases and the per-model status the post-call screen shows.
 */
@Entity
@Getter
@Setter
@NoArgsConstructor
@Table(
        name = "condition_detection_runs",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_condition_detection_runs_call_model",
                columnNames = {"call_id", "model_id"}),
        indexes = @Index(
                name = "idx_condition_detection_runs_patient",
                columnList = "patient_id, created_at"))
public class ConditionDetectionRun {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "call_id", nullable = false, length = 120)
    private String callId;

    /** Patient profile primary key (patients.id), not the patient's users.id. */
    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    /** The patient's users.id; matches call_attendees.user_id and transcript actor ids. */
    @Column(name = "patient_user_id", nullable = false)
    private Long patientUserId;

    @Column(name = "model_id", nullable = false, length = 100)
    private String modelId;

    @Enumerated(EnumType.STRING)
    @Column(name = "input_kind", nullable = false, length = 30)
    private ConditionInputKind inputKind;

    @Column(name = "config_version", length = 160)
    private String configVersion;

    @Enumerated(EnumType.STRING)
    @Column(name = "state", nullable = false, length = 20)
    private ConditionRunState state;

    @Enumerated(EnumType.STRING)
    @Column(name = "skip_reason", length = 60)
    private ConditionSkipReason skipReason;

    @Column(name = "claim_token")
    private UUID claimToken;

    @Column(name = "claimed_until")
    private LocalDateTime claimedUntil;

    @Column(name = "attempt_count", nullable = false)
    private int attemptCount;

    @Column(name = "next_attempt_at", nullable = false)
    private LocalDateTime nextAttemptAt;

    @Column(name = "last_error", columnDefinition = "TEXT")
    private String lastError;

    @Column(name = "speech_seconds")
    private Double speechSeconds;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @Column(name = "completed_at")
    private LocalDateTime completedAt;

    @PrePersist
    void onCreate() {
        final LocalDateTime now = LocalDateTime.now(ZoneOffset.UTC);
        if (createdAt == null) {
            createdAt = now;
        }
        updatedAt = now;
        if (nextAttemptAt == null) {
            nextAttemptAt = now;
        }
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = LocalDateTime.now(ZoneOffset.UTC);
    }
}
