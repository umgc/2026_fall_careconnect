package com.careconnect.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.LocalDateTime;
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
}
