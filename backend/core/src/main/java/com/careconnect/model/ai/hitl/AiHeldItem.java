package com.careconnect.model.ai.hitl;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.util.UUID;

/**
 * Persisted Tier-2 Ask AI answer awaiting human release/reject.
 */
@Entity
@Table(
        name = "ai_held_item",
        indexes = {
                @Index(name = "idx_held_patient_status", columnList = "patient_id, status"),
                @Index(name = "idx_held_requester", columnList = "requester_user_id, created_at")
        })
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AiHeldItem {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "requester_user_id", nullable = false)
    private Long requesterUserId;

    @Column(name = "session_id")
    private UUID sessionId;

    @Column(name = "audit_id", nullable = false)
    private UUID auditId;

    @Column(name = "request_id")
    private UUID requestId;

    @Column(name = "source_surface", nullable = false, length = 32)
    private String sourceSurface;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 24)
    private AiHeldItemStatus status;

    @Column(name = "tier", nullable = false)
    private int tier;

    @Column(name = "trigger_codes", nullable = false, columnDefinition = "TEXT")
    private String triggerCodesJson;

    @Column(name = "query_text_hash", length = 64)
    private String queryTextHash;

    @Column(name = "draft_answer", nullable = false, columnDefinition = "TEXT")
    private String draftAnswer;

    @Column(name = "final_answer", columnDefinition = "TEXT")
    private String finalAnswer;

    @Column(name = "citations_json", nullable = false, columnDefinition = "TEXT")
    private String citationsJson;

    @Column(name = "validation_findings_json", columnDefinition = "TEXT")
    private String validationFindingsJson;

    @Column(name = "reviewer_user_id")
    private Long reviewerUserId;

    @Column(name = "reviewed_at")
    private Instant reviewedAt;

    @Column(name = "review_notes", length = 500)
    private String reviewNotes;

    @Column(name = "delivery_status", nullable = false, length = 32)
    private String deliveryStatus;

    @Column(name = "expires_at")
    private Instant expiresAt;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @PrePersist
    void onCreate() {
        final Instant now = Instant.now();
        if (id == null) {
            id = UUID.randomUUID();
        }
        if (createdAt == null) {
            createdAt = now;
        }
        updatedAt = now;
        if (tier == 0) {
            tier = 2;
        }
        if (status == null) {
            status = AiHeldItemStatus.PENDING_REVIEW;
        }
        if (sourceSurface == null) {
            sourceSurface = "ASK_AI";
        }
        if (deliveryStatus == null) {
            deliveryStatus = "HELD";
        }
        if (triggerCodesJson == null) {
            triggerCodesJson = "[]";
        }
        if (citationsJson == null) {
            citationsJson = "[]";
        }
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = Instant.now();
    }
}
