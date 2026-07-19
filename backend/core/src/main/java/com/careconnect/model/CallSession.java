package com.careconnect.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.LocalDateTime;
import java.util.UUID;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/** Durable authorization and ownership record for a video call. */
@Entity
@Getter
@Setter
@NoArgsConstructor
@Table(
        name = "call_sessions",
        uniqueConstraints = @UniqueConstraint(name = "uq_call_sessions_call_id", columnNames = "call_id"))
public class CallSession extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "call_id", nullable = false, length = 120)
    private String callId;

    /** Patient profile primary key (patient.id), not the patient's users.id. */
    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "created_by_user_id", nullable = false)
    private Long createdByUserId;

    @Column(name = "scheduled_visit_id")
    private Long scheduledVisitId;

    @Column(name = "chime_meeting_id", length = 255)
    private String chimeMeetingId;

    @Column(name = "status", nullable = false, length = 24)
    private String status;

    @Column(name = "ended_at")
    private LocalDateTime endedAt;

    @Column(name = "termination_claim_id")
    private UUID terminationClaimId;

    @Column(name = "termination_claimed_by_user_id")
    private Long terminationClaimedByUserId;

    @Column(name = "termination_lease_until")
    private LocalDateTime terminationLeaseUntil;

    @Column(name = "termination_attempt_count", nullable = false)
    private int terminationAttemptCount;

    @Column(name = "termination_next_retry_at")
    private LocalDateTime terminationNextRetryAt;

    @Column(name = "termination_last_error", columnDefinition = "TEXT")
    private String terminationLastError;

    /** Comma-delimited immutable user-id snapshot captured when termination starts. */
    @Column(name = "termination_notify_user_ids", columnDefinition = "TEXT")
    private String terminationNotifyUserIds;
}
