package com.careconnect.model.ai.audit;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.util.UUID;

/**
 * Append-only Ask AI lifecycle event (FR-AI-10 / REQ-SC-9).
 */
@Entity
@Table(
        name = "ai_ask_audit_event",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_ai_ask_audit_event_seq",
                columnNames = {"audit_id", "event_sequence"}))
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AiAskAuditEvent {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "audit_id", nullable = false, updatable = false)
    private UUID auditId;

    @Column(name = "event_type", nullable = false, length = 48, updatable = false)
    private String eventType;

    @Column(name = "event_sequence", nullable = false, updatable = false)
    private int eventSequence;

    @Column(name = "actor_user_id", updatable = false)
    private Long actorUserId;

    @Column(name = "payload_json", nullable = false, columnDefinition = "TEXT", updatable = false)
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
        if (payloadJson == null) {
            payloadJson = "{}";
        }
    }
}
