package com.careconnect.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * JPA entity representing a persisted call summary produced from a
 * post-call transcript.
 *
 * <p>Adds {@code patientId} on 2026-07-04 to carry the RBAC scope for
 * indexing into the SUMMARY_CREATED event (PR #244 column, WBS 3.11.5
 * emit). The column is nullable so historic rows survive; new
 * summaries populate it from the call context at persistence time.
 */
@Entity
@Table(
        name = "call_summaries",
        indexes = {
                @Index(name = "idx_call_summary_call_id", columnList = "call_id"),
                @Index(name = "idx_call_summary_generated_at", columnList = "generated_at"),
                @Index(name = "idx_call_summary_risk_level", columnList = "risk_level"),
                @Index(name = "idx_call_summary_caregiver_visibility",
                        columnList = "caregiver_visibility")
                // patient_id index owned by Flyway migration V2607032251
        }
)
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CallSummary extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "call_id", nullable = false)
    private String callId;

    /**
     * Patient this summary is about. Nullable for historic rows that
     * predate the column (PR #244); populated for new summaries via
     * the call context at persistence time. Carried on SUMMARY_CREATED
     * events as the RBAC scope key.
     */
    @Column(name = "patient_id")
    private Long patientId;

    @Column(name = "generated_at")
    private LocalDateTime generatedAt;

    @Column(name = "summary_json", columnDefinition = "TEXT")
    private String summaryJson;

    @Column(name = "status")
    private String status;

    @Column(name = "risk_level")
    private String riskLevel;

    @Column(name = "caregiver_visibility")
    private String caregiverVisibility;

    @Column(name = "summary_confidence")
    private BigDecimal summaryConfidence;

    @Column(name = "summarization_engine")
    private String summarizationEngine;

    @Column(name = "transcript_available")
    private Boolean transcriptAvailable;

    @Column(name = "generated_by_user_id")
    private Long generatedByUserId;

    @PrePersist
    void onCreate() {
        if (generatedAt == null) {
            generatedAt = LocalDateTime.now();
        }
    }
}