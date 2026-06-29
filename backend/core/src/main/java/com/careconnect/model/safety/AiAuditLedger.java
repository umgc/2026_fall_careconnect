package com.careconnect.model.safety;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;
import java.util.Map;

/**
 * WBS 3.15.6
 * Immutable audit ledger for AI events
 * records queries/responses/validation events/confirmation events
 * Write-once enforced at:
 *   1. DB trigger (V74) which rejects UPDATE/DELETE in PostgreSQL
 *   2. JPA callbacks (@PreUpdate / @PreRemove) at the app level
 * just to ensure that anyone who bypasses the service 
 * and writes to the repo directly is denied write access
 * 
 * WBS: 3.15.1
 * Confirmation Service
 * integration method: @Autowired AiAuditLedgerService →
 *   logConfirmation(CONFIRMATION_SERVICE, ...)
 * note: REQUIRES_NEW has to be added
 * ────────────────────────────────────────
 * WBS: 3.15.3
 * Secondary validation pass
 * integration method: logValidation(ASK_AI or SUMMARY, ...)
 * ────────────────────────────────────────
 * WBS: 3.12.10
 * AI query/response audit (Ravichandra)
 * integration method: logQuery(ASK_AI, ...) + logResponse(ASK_AI, ...)
 * ────────────────────────────────────────
 * WBS: 3.15.5
 * Caregiver visibility
 * integration method: log(CONFIRMATION, CAREGIVER_VISIBILITY, ...)
 * ────────────────────────────────────────
 * WBS: 4.11.x
 * Safety/consent tests
 * integration method: I have to verify the trigger works in Postgres w/ Docker
 * note: Needs manual V74 application
 */

@Getter @Setter @Builder @NoArgsConstructor @AllArgsConstructor
@Entity @Table(name = "ai_audit_ledger")
public class AiAuditLedger {

    /* TODO: not a fan of strings instead of enums as the entity fields
    * but that's what EvvAuditEvent did with eventType.
    * That needs reviewing
    */ 

    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** QUERY | RESPONSE | VALIDATION | CONFIRMATION */
    @Column(name = "event_type", nullable = false, length = 50)
    private String eventType;

    /** Null for system events */
    @Column(name = "actor_user_id")
    private Long actorUserId;

    /** Null for events outside the scope of a patient */
    @Column(name = "patient_id")
    private Long patientId;

    /** Relates events in the same user session */
    @Column(name = "session_id", length = 128)
    private String sessionId;

    /** ASK_AI | SUMMARY | CONFIRMATION_SERVICE | CAREGIVER_VISIBILITY */
    @Column(name = "source_feature", nullable = false, length = 100)
    private String sourceFeature;

    /** Event-specific text: query text, response excerpt, validation result, etc. */
    @Convert(disableConversion = true)
    @Column(name = "payload", columnDefinition = "jsonb")
    @JdbcTypeCode(SqlTypes.JSON)
    private Map<String, Object> payload;

    @Column(name = "occurred_at", nullable = false)
    private OffsetDateTime occurredAt;

    @PrePersist
    void onCreate() {
        if (occurredAt == null) occurredAt = OffsetDateTime.now();
    }

    @PreUpdate
    void onUpdate() {
        throw new UnsupportedOperationException(
                "AiAuditLedger records are immutable, updates are not allowed.");
    }

    @PreRemove
    void onRemove() {
        throw new UnsupportedOperationException(
                "AiAuditLedger records are immutable, deletes are not allowed.");
    }
}
