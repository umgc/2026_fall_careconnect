package com.careconnect.model.ehr;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
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
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;
import java.util.Map;

/**
 * Append-only audit record of a single retrieval attempt against an external EHR source,
 * generalizing the EVV audit pattern across every {@code EhrApiClient} implementation.
 * <p>
 * Scoped by {@code (patientId, source)} per ADR-08: an adapter records only its own
 * source-scoped activity and never writes to the canonical patient record.
 */
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(
        name = "ehr_audit_event",
        indexes = @Index(
                name = "idx_ehr_audit_event_patient_time",
                columnList = "patient_id, event_time"))
public class EhrAuditEvent {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    /** Source identifier as reported by {@code EhrApiClient.getSource()}, e.g. MEDICARE. */
    @Column(name = "source", nullable = false, length = 64)
    private String source;

    /** FHIR resource the attempt targeted, e.g. Patient, Coverage, ExplanationOfBenefit. */
    @Column(name = "resource_type", nullable = false, length = 64)
    private String resourceType;

    @Enumerated(EnumType.STRING)
    @Column(name = "outcome", nullable = false, length = 16)
    private EhrRetrievalOutcome outcome;

    @Column(name = "event_time", nullable = false)
    private OffsetDateTime eventTime;

    /** Null when the retrieval was system-initiated rather than triggered by a user. */
    @Column(name = "actor_user_id")
    private Long actorUserId;

    /** Records returned by the attempt; null when the attempt did not complete. */
    @Column(name = "record_count")
    private Integer recordCount;

    /**
     * Attempt metadata such as error codes and latency. Never store access tokens
     * (NFR-SEC-03) or retrieved clinical content here; this column is not PHI-bearing.
     */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "details", columnDefinition = "jsonb")
    private Map<String, Object> details;

    @PrePersist
    void onCreate() {
        if (eventTime == null) {
            eventTime = OffsetDateTime.now();
        }
    }
}
