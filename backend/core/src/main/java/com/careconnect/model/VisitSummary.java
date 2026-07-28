package com.careconnect.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * Task 1.4 — visit summary persistence mirroring {@link CallSummary} for Ask AI indexing.
 */
@Entity
@Getter
@Setter
@NoArgsConstructor
@Table(
        name = "visit_summaries",
        indexes = {
                @Index(name = "idx_visit_summary_visit_id", columnList = "visit_id"),
                @Index(name = "idx_visit_summary_generated_at", columnList = "generated_at"),
                @Index(name = "idx_visit_summary_patient_id", columnList = "patient_id"),
                @Index(
                        name = "idx_visit_summary_caregiver_visibility",
                        columnList = "caregiver_visibility")
        })
public class VisitSummary extends Auditable {

    private static final int VISIT_ID_LENGTH = 120;
    private static final int STATUS_LENGTH = 24;
    private static final int RISK_LEVEL_LENGTH = 16;
    private static final int CAREGIVER_VISIBILITY_LENGTH = 16;
    private static final int SUMMARIZATION_ENGINE_LENGTH = 128;
    private static final String DEFAULT_CAREGIVER_VISIBILITY = "on_consent";

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "visit_id", nullable = false, length = VISIT_ID_LENGTH)
    private String visitId;

    @Column(name = "patient_id")
    private Long patientId;

    @Column(name = "summary_json", nullable = false, columnDefinition = "TEXT")
    private String summaryJson;

    @Column(name = "status", nullable = false, length = STATUS_LENGTH)
    private String status;

    @Column(name = "transcript_segment_count", nullable = false)
    private Integer transcriptSegmentCount = 0;

    @Column(name = "generated_by_user_id")
    private Long generatedByUserId;

    @Column(name = "error_message", columnDefinition = "TEXT")
    private String errorMessage;

    @Column(name = "generated_at", nullable = false)
    private LocalDateTime generatedAt;

    @Column(name = "risk_level", length = RISK_LEVEL_LENGTH)
    private String riskLevel;

    @Column(name = "caregiver_visibility", nullable = false, length = CAREGIVER_VISIBILITY_LENGTH)
    private String caregiverVisibility = DEFAULT_CAREGIVER_VISIBILITY;

    @Column(name = "summary_confidence", precision = 3, scale = 2)
    private BigDecimal summaryConfidence;

    @Column(name = "summarization_engine", length = SUMMARIZATION_ENGINE_LENGTH)
    private String summarizationEngine;

    @Column(name = "transcript_snapshot_version", length = 80)
    private String transcriptSnapshotVersion;

    @Column(name = "model_config_version", length = 160)
    private String modelConfigVersion;

    @Column(name = "transcript_available", nullable = false)
    private Boolean transcriptAvailable = Boolean.TRUE;
}
