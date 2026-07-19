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

/** A user authorized to join a durable call session. */
@Entity
@Getter
@Setter
@NoArgsConstructor
@Table(
        name = "call_participants",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_call_participants_session_user",
                columnNames = {"call_session_id", "user_id"}))
public class CallParticipant extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "call_session_id", nullable = false)
    private Long callSessionId;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "invited_by_user_id")
    private Long invitedByUserId;

    @Column(name = "status", nullable = false, length = 24)
    private String status;

    @Column(name = "joined_at")
    private LocalDateTime joinedAt;

    @Column(name = "left_at")
    private LocalDateTime leftAt;
}
