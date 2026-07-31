package com.careconnect.model.visibility;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * WBS 3.15.5: caregiver summary visibility grant
 *
 * One row per (caregiver, patient) pair for tracking the current {@link VisibilityStatus}
 * A caregiver can view a patient's summaries when there is a row with
 * status GRANTED. No row, PENDING_REVIEW, and REVOKED are all no access states
 */
@Entity
@Table(name = "caregiver_summary_visibility",
       uniqueConstraints = @UniqueConstraint(
               name = "uq_caregiver_summary_visibility_pair",
               columnNames = {"caregiver_user_id", "patient_user_id"}),
       indexes = {
               @Index(name = "idx_caregiver_summary_visibility_caregiver",
                      columnList = "caregiver_user_id"),
               @Index(name = "idx_caregiver_summary_visibility_patient_status",
                      columnList = "patient_user_id, status")
       })
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class CaregiverSummaryVisibility {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "caregiver_user_id", nullable = false)
    private Long caregiverUserId;

    @Column(name = "patient_user_id", nullable = false)
    private Long patientUserId;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    @Builder.Default
    private VisibilityStatus status = VisibilityStatus.PENDING_REVIEW;

    /** User who requested access (typically the caregiver or a coordinator). */
    @Column(name = "requested_by")
    private Long requestedBy;

    /** Reviewer who last granted/revoked through the review gate. */
    @Column(name = "reviewed_by")
    private Long reviewedBy;

    @Column(name = "reviewed_at")
    private LocalDateTime reviewedAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @Version
    @Column(name = "version", nullable = false)
    @Builder.Default
    private Long version = 0L;

    @PrePersist
    void onCreate() {
        LocalDateTime now = LocalDateTime.now();
        if (createdAt == null) createdAt = now;
        updatedAt = now;
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = LocalDateTime.now();
    }

    public boolean isGranted() {
        return status == VisibilityStatus.GRANTED;
    }
}
