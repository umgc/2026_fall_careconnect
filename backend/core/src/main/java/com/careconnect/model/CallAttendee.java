package com.careconnect.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.LocalDateTime;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/** Persisted Chime attendee identity for a call (speaker-ID roster source of truth). */
@Entity
@Getter
@Setter
@NoArgsConstructor
@Table(
        name = "call_attendees",
        uniqueConstraints = {
            @UniqueConstraint(
                    name = "uq_call_attendees_call_chime",
                    columnNames = {"call_id", "chime_attendee_id"})
        },
        indexes = {
            @Index(name = "idx_call_attendees_call_id", columnList = "call_id"),
            @Index(name = "idx_call_attendees_user_id", columnList = "user_id")
        })
public class CallAttendee {

    /** Maximum length for call identifier columns. */
    private static final int CALL_ID_LENGTH = 120;

    /** Maximum length for Chime attendee identifier values. */
    private static final int CHIME_ATTENDEE_ID_LENGTH = 255;

    /** Maximum length for role values. */
    private static final int ROLE_LENGTH = 40;

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "call_id", nullable = false, length = CALL_ID_LENGTH)
    private String callId;

    @Column(name = "chime_attendee_id", nullable = false, length = CHIME_ATTENDEE_ID_LENGTH)
    private String chimeAttendeeId;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "role", nullable = false, length = ROLE_LENGTH)
    private String role;

    @Column(name = "joined_at", nullable = false)
    private LocalDateTime joinedAt;

    @Column(name = "left_at")
    private LocalDateTime leftAt;
}
