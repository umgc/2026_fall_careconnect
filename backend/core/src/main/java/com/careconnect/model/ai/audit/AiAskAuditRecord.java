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

/**
 * Immutable Ask AI completion snapshot (FR-AI-10). Insert-only from the application.
 */
@Entity
@Table(name = "ai_ask_audit_record")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AiAskAuditRecord {

    @Id
    @Column(name = "audit_id", nullable = false, updatable = false)
    private UUID auditId;

    @Column(name = "request_id", nullable = false, unique = true, updatable = false)
    private UUID requestId;

    @Column(name = "session_id", updatable = false)
    private UUID sessionId;

    @Column(name = "client_request_id", length = 64, updatable = false)
    private String clientRequestId;

    @Column(name = "patient_id", nullable = false, updatable = false)
    private Long patientId;

    @Column(name = "caller_user_id", nullable = false, updatable = false)
    private Long callerUserId;

    @Column(name = "caller_role", nullable = false, length = 32, updatable = false)
    private String callerRole;

    @Column(name = "input_modality", nullable = false, length = 8, updatable = false)
    private String inputModality;

    @Column(name = "locale", nullable = false, length = 10, updatable = false)
    private String locale;

    @Column(name = "query_text_hash", nullable = false, length = 64, updatable = false)
    private String queryTextHash;

    @Column(name = "query_length", nullable = false, updatable = false)
    private int queryLength;

    @Column(name = "delivery_status", nullable = false, length = 24, updatable = false)
    private String deliveryStatus;

    @Column(name = "tier", nullable = false, updatable = false)
    private int tier;

    @Column(name = "held", nullable = false, updatable = false)
    private boolean held;

    @Column(name = "held_item_id", updatable = false)
    private UUID heldItemId;

    @Column(name = "error_code", length = 40, updatable = false)
    private String errorCode;

    @Column(name = "answer_text_hash", length = 64, updatable = false)
    private String answerTextHash;

    @Column(name = "answer_length", updatable = false)
    private Integer answerLength;

    @Column(name = "citations_json", nullable = false, columnDefinition = "TEXT", updatable = false)
    private String citationsJson;

    @Column(name = "escalation_json", nullable = false, columnDefinition = "TEXT", updatable = false)
    private String escalationJson;

    @Column(name = "trigger_codes", nullable = false, columnDefinition = "TEXT", updatable = false)
    private String triggerCodesJson;

    @Column(name = "validation_findings_json", columnDefinition = "TEXT", updatable = false)
    private String validationFindingsJson;

    @Column(name = "retrieval_meta_json", nullable = false, columnDefinition = "TEXT", updatable = false)
    private String retrievalMetaJson;

    @Column(name = "scope_json", nullable = false, columnDefinition = "TEXT", updatable = false)
    private String scopeJson;

    @Column(name = "model_provider", length = 32, updatable = false)
    private String modelProvider;

    @Column(name = "model_id", length = 128, updatable = false)
    private String modelId;

    @Column(name = "total_latency_ms", updatable = false)
    private Integer totalLatencyMs;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @PrePersist
    void onCreate() {
        if (createdAt == null) {
            createdAt = Instant.now();
        }
        if (citationsJson == null) {
            citationsJson = "[]";
        }
        if (escalationJson == null) {
            escalationJson = "{}";
        }
        if (triggerCodesJson == null) {
            triggerCodesJson = "[]";
        }
        if (retrievalMetaJson == null) {
            retrievalMetaJson = "{}";
        }
        if (scopeJson == null) {
            scopeJson = "{}";
        }
        if (inputModality == null) {
            inputModality = "TEXT";
        }
        if (locale == null) {
            locale = "en-US";
        }
    }
}
