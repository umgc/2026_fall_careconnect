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

@Entity
@Getter
@Setter
@NoArgsConstructor
@Table(
        name = "call_summaries",
        indexes = {
                @Index(
                        name = "idx_call_summary_call_id",
                        columnList = "call_id"
                ),
                @Index(
                        name = "idx_call_summary_generated_at",
                        columnList = "generated_at"
                ),
                @Index(
                        name = "idx_call_summary_risk_level",
                        columnList = "risk_level"
                ),
                @Index(
                        name = "idx_call_summary_caregiver_visibility",
                        columnList = "caregiver_visibility"
                )
        }
)
public class CallSummary extends Auditable {

    /** Maximum length for call identifier columns. */
    private static final int
            CALL_ID_LENGTH = 120;

    /** Maximum length for status columns. */
    private static final int
            STATUS_LENGTH = 24;

    /** Maximum length for the SOAP risk-level column. */
    private static final int
            RISK_LEVEL_LENGTH = 16;

    /** Maximum length for the caregiver-visibility column. */
    private static final int
            CAREGIVER_VISIBILITY_LENGTH = 16;

    /** Maximum length for the summarization-engine column. */
    private static final int
            SUMMARIZATION_ENGINE_LENGTH = 128;

    /** Precision (total digits) for the summary-confidence decimal column. */
    private static final int
            SUMMARY_CONFIDENCE_PRECISION = 3;

    /** Scale (digits after the decimal point) for the summary-confidence column. */
    private static final int
            SUMMARY_CONFIDENCE_SCALE = 2;

    /** Default caregiver-visibility value when not explicitly set. */
    private static final String
            DEFAULT_CAREGIVER_VISIBILITY = "on_consent";

    /** Database identifier for the summary row. */
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** Call identifier associated with the generated summary. */
    @Column(name = "call_id", nullable = false, length = CALL_ID_LENGTH)
    private String callId;

    /** Serialized summary payload stored as JSON text. */
    @Column(name = "summary_json", nullable = false, columnDefinition = "TEXT")
    private String summaryJson;

    /** Current summary generation status. */
    @Column(name = "status", nullable = false, length = STATUS_LENGTH)
    private String status;

    /**
     * Number of transcript segments included in the summary.
     */
    @Column(name = "transcript_segment_count", nullable = false)
    private Integer transcriptSegmentCount;

    /**
     * User identifier of the generator when available.
     */
    @Column(name = "generated_by_user_id")
    private Long generatedByUserId;

    /** Error details captured during summary generation. */
    @Column(name = "error_message", columnDefinition = "TEXT")
    private String errorMessage;

    /** Timestamp when the summary was generated. */
    @Column(name = "generated_at", nullable = false)
    private LocalDateTime generatedAt;

    /**
     * SOAP risk level for the call (HIGH, MODERATE, LOW) when classified;
     * remains null when the summary did not yield a risk classification.
     * Denormalized from the SOAP payload for sorting and filtering.
     */
    @Column(name = "risk_level", length = RISK_LEVEL_LENGTH)
    private String riskLevel;

    /**
     * Caregiver visibility policy applied to the summary record
     * (auto, on_consent, hidden). Defaults to on_consent so that
     * caregivers cannot view the summary unless consent is granted.
     */
    @Column(name = "caregiver_visibility", nullable = false, length = CAREGIVER_VISIBILITY_LENGTH)
    private String caregiverVisibility = DEFAULT_CAREGIVER_VISIBILITY;

    /**
     * Overall confidence score for the generated summary, between 0.00 and 1.00.
     * Null when the summarization engine did not return an overall confidence.
     */
    @Column(
            name = "summary_confidence",
            precision = SUMMARY_CONFIDENCE_PRECISION,
            scale = SUMMARY_CONFIDENCE_SCALE
    )
    private BigDecimal summaryConfidence;

    /**
     * Identifier of the engine that produced the summary, including model
     * provider and version (for example, "aws_bedrock:amazon.nova-pro-v1:0").
     * Captured so that audit and rollback workflows can attribute records to
     * the engine version that produced them.
     */
    @Column(name = "summarization_engine", length = SUMMARIZATION_ENGINE_LENGTH)
    private String summarizationEngine;

    /**
     * Whether a usable transcript was available when the summary was generated.
     * False is set when the pipeline records an empty-state summary because no
     * transcript was produced for the call.
     */
    @Column(name = "transcript_available", nullable = false)
    private Boolean transcriptAvailable = Boolean.TRUE;
}
