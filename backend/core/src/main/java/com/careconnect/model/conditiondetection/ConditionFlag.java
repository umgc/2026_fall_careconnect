package com.careconnect.model.conditiondetection;

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
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * One condition's screening result from one run. A row is stored for every condition the
 * model reports, including level 0, so "no indicator" is distinguishable from "not run".
 */
@Entity
@Getter
@Setter
@NoArgsConstructor
@Table(
        name = "condition_flags",
        indexes = {
            @Index(name = "idx_condition_flags_call", columnList = "call_id"),
            @Index(name = "idx_condition_flags_patient", columnList = "patient_id, created_at")
        })
public class ConditionFlag {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "run_id", nullable = false)
    private Long runId;

    @Column(name = "call_id", nullable = false, length = 120)
    private String callId;

    /** Patient profile primary key (patients.id). */
    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "model_id", nullable = false, length = 100)
    private String modelId;

    @Enumerated(EnumType.STRING)
    @Column(name = "condition_name", nullable = false, length = 40)
    private ConditionName conditionName;

    /** 0 means no indicator; higher is more severe. The scale is model-specific. */
    @Column(name = "severity_level", nullable = false)
    private int severityLevel;

    @Column(name = "severity_label", nullable = false, length = 30)
    private String severityLabel;

    /** Model-native score, kept for audit; never sent to clients. */
    @Column(name = "raw_score")
    private Double rawScore;

    @Column(name = "evidence_summary", length = 500)
    private String evidenceSummary;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    void onCreate() {
        if (createdAt == null) {
            createdAt = LocalDateTime.now(ZoneOffset.UTC);
        }
    }
}
