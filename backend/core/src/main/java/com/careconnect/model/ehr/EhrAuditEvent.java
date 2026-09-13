package com.careconnect.model.ehr;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;

/**
 * Append-only audit of every EHR retrieval/connect attempt (Findings R6).
 *
 * <p>Modeled on {@link com.careconnect.model.evv.EvvAuditEvent} for shape and on
 * {@code AiAskAuditService} for its fail-soft, hashed-PHI discipline: no raw FHIR content is
 * stored — only a per-user salted hash and coarse outcome. Written by
 * {@link com.careconnect.service.ehr.EhrAuditService} in a {@code REQUIRES_NEW} transaction so
 * an audit failure never aborts the request path.
 */
@Entity
@Table(
        name = "ehr_audit_event",
        indexes = {
                @Index(name = "idx_ehr_audit_user", columnList = "user_id"),
                @Index(name = "idx_ehr_audit_user_time", columnList = "user_id, event_time")
        })
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class EhrAuditEvent {

    public static final String OUTCOME_OK = "OK";
    public static final String OUTCOME_EMPTY = "EMPTY";
    public static final String OUTCOME_ERROR = "ERROR";

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "source", nullable = false, length = 32)
    private String source;

    @Column(name = "event_type", nullable = false, length = 48)
    private String eventType;

    @Column(name = "resource_type", length = 48)
    private String resourceType;

    /** SHA-256(detail|userId) — never raw PHI. */
    @Column(name = "detail_hash", length = 64)
    private String detailHash;

    @Column(name = "outcome", length = 16)
    private String outcome;

    @Column(name = "event_time", nullable = false)
    private Instant eventTime;

    @PrePersist
    void onCreate() {
        if (eventTime == null) {
            eventTime = Instant.now();
        }
    }
}
