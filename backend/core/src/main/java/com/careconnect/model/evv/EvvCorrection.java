package com.careconnect.model.evv;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;
import java.util.Map;

@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(name = "evv_correction")
public class EvvCorrection {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "original_record_id", nullable = false)
    private EvvRecord originalRecord;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "corrected_record_id", nullable = false)
    private EvvRecord correctedRecord;

    @Column(name = "reason_code", nullable = false, length = 50)
    private String reasonCode;

    @Column(name = "explanation", nullable = false, length = 1000)
    private String explanation;

    @Column(name = "corrected_by", nullable = false)
    private Long correctedBy;

    @Column(name = "corrected_at", nullable = false)
    private OffsetDateTime correctedAt;

    @Column(name = "approval_required", nullable = false)
    @Builder.Default
    private Boolean approvalRequired = false;

    @Column(name = "approved_by")
    private Long approvedBy;

    @Column(name = "approved_at")
    private OffsetDateTime approvedAt;

    @Column(name = "approval_comment")
    private String approvalComment;

    // Store original values for audit trail
    @Convert(disableConversion = true)
    @Column(name = "original_values", columnDefinition = "jsonb")
    @JdbcTypeCode(SqlTypes.JSON)
    private Map<String, Object> originalValues;

    // Store corrected values for audit trail
    @Convert(disableConversion = true)
    @Column(name = "corrected_values", columnDefinition = "jsonb")
    @JdbcTypeCode(SqlTypes.JSON)
    private Map<String, Object> correctedValues;

    @PrePersist
    void onCreate() {
        if (correctedAt == null) {
            correctedAt = OffsetDateTime.now();
        }
    }

    public void approve(Long approverId, String comment) {
        this.approvedBy = approverId;
        this.approvedAt = OffsetDateTime.now();
        this.approvalComment = comment;
    }

    public void reject(Long reviewerId, String comment) {
        this.approvedBy = reviewerId; // Store who rejected it
        this.approvedAt = OffsetDateTime.now(); // Store when it was rejected
        this.approvalComment = comment;
        this.approvalRequired = false; // No longer requires approval
    }
}

