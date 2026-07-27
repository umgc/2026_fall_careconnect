package com.careconnect.model.ai.audit;

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

/** Post-HITL delivery snapshot; keeps the original audit record immutable. */
@Entity
@Table(name = "ai_ask_audit_delivery_supplement")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AiAskAuditDeliverySupplement {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "audit_id", nullable = false, updatable = false)
    private UUID auditId;

    @Column(name = "delivery_status", nullable = false, length = 24, updatable = false)
    private String deliveryStatus;

    @Column(name = "final_answer_hash", length = 64, updatable = false)
    private String finalAnswerHash;

    @Column(name = "citations_json", nullable = false, columnDefinition = "TEXT", updatable = false)
    private String citationsJson;

    @Column(name = "reviewer_user_id", updatable = false)
    private Long reviewerUserId;

    @Column(name = "reviewed_at", nullable = false, updatable = false)
    private Instant reviewedAt;

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
        if (citationsJson == null) {
            citationsJson = "[]";
        }
    }
}
