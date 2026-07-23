package com.careconnect.model.ai.hitl;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.util.UUID;

/**
 * Append-only HITL / safety audit event (REQ-SC-9 subset for hold lifecycle).
 */
@Entity
@Table(name = "ai_safety_audit_event")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AiSafetyAuditEvent {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "audit_id", nullable = false)
    private UUID auditId;

    @Column(name = "held_item_id")
    private UUID heldItemId;

    @Column(name = "event_type", nullable = false, length = 40)
    private String eventType;

    @Column(name = "actor_user_id")
    private Long actorUserId;

    @Column(name = "payload_json", columnDefinition = "TEXT")
    private String payloadJson;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @PrePersist
    void onCreate() {
        if (id == null) {
            id = UUID.randomUUID();
        }
        if (createdAt == null) {
            createdAt = Instant.now();
        }
    }
}
