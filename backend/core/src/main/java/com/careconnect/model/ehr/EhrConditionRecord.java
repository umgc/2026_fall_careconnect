package com.careconnect.model.ehr;

import com.careconnect.model.Auditable;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.Instant;
import java.util.List;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

/**
 * One source's normalized view of a FHIR {@code Condition}.
 *
 * <p>The row remains source-specific. Records from separate EHRs are not silently merged, and the
 * optional raw-payload link preserves the source resource for replay and audit. Public API field
 * names remain provisional until the unified OpenAPI contract is approved.
 */
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(
        name = "ehr_condition_record",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_ehr_condition_record_source_external",
                columnNames = {"patient_id", "source_id", "external_condition_id"}),
        indexes = @Index(
                name = "idx_ehr_condition_record_patient",
                columnList = "patient_id"))
public class EhrConditionRecord extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "source_id", nullable = false)
    private Long sourceId;

    @Column(name = "raw_payload_id")
    private Long rawPayloadId;

    @Column(name = "external_condition_id", nullable = false, length = 255)
    private String externalConditionId;

    @Column(name = "source_version_id", length = 255)
    private String sourceVersionId;

    @Column(name = "source_updated_at")
    private Instant sourceUpdatedAt;

    @Column(name = "clinical_status", length = 64)
    private String clinicalStatus;

    @Column(name = "verification_status", length = 64)
    private String verificationStatus;

    @Column(name = "severity", length = 255)
    private String severity;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "categories", nullable = false, columnDefinition = "jsonb")
    @Builder.Default
    private List<EhrCodeValue> categories = List.of();

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "condition_codes", nullable = false, columnDefinition = "jsonb")
    @Builder.Default
    private List<EhrCodeValue> conditionCodes = List.of();

    @Column(name = "condition_text", columnDefinition = "TEXT")
    private String conditionText;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "body_sites", nullable = false, columnDefinition = "jsonb")
    @Builder.Default
    private List<EhrCodeValue> bodySites = List.of();

    @Column(name = "onset_type", length = 32)
    private String onsetType;

    @Column(name = "onset_value", columnDefinition = "TEXT")
    private String onsetValue;

    @Column(name = "onset_precision", length = 16)
    private String onsetPrecision;

    @Column(name = "abatement_type", length = 32)
    private String abatementType;

    @Column(name = "abatement_value", columnDefinition = "TEXT")
    private String abatementValue;

    @Column(name = "abatement_precision", length = 16)
    private String abatementPrecision;

    @Column(name = "recorded_date", length = 40)
    private String recordedDate;

    @Column(name = "recorded_date_precision", length = 16)
    private String recordedDatePrecision;

    @Column(name = "encounter_reference", length = 512)
    private String encounterReference;

    @Column(name = "recorder_reference", length = 512)
    private String recorderReference;

    @Column(name = "recorder_display", length = 512)
    private String recorderDisplay;

    @Column(name = "hidden_from_active_list", nullable = false)
    @Builder.Default
    private Boolean hiddenFromActiveList = Boolean.FALSE;
}
