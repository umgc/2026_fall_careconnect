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
 * One source's normalized FHIR {@code Encounter}; it is intentionally distinct from a claim-based
 * {@link EhrVisitRecord}.
 *
 * <p>Repeated types, participants, locations, reasons and references remain structured JSON
 * collections instead of being flattened into display strings. Storage orchestration must retain
 * the complete original resource through {@link EhrRawPayload} before this record is persisted.
 */
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(
        name = "ehr_encounter_record",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_ehr_encounter_record_source_external",
                columnNames = {"patient_id", "source_id", "external_encounter_id"}),
        indexes = @Index(
                name = "idx_ehr_encounter_record_patient",
                columnList = "patient_id"))
public class EhrEncounterRecord extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "source_id", nullable = false)
    private Long sourceId;

    @Column(name = "raw_payload_id")
    private Long rawPayloadId;

    @Column(name = "external_encounter_id", nullable = false, length = 255)
    private String externalEncounterId;

    @Column(name = "source_version_id", length = 255)
    private String sourceVersionId;

    @Column(name = "source_updated_at")
    private Instant sourceUpdatedAt;

    @Column(name = "status", nullable = false, length = 64)
    private String status;

    @Column(name = "class_system", length = 512)
    private String classSystem;

    @Column(name = "class_code", length = 255)
    private String classCode;

    @Column(name = "class_display", length = 512)
    private String classDisplay;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "encounter_types", nullable = false, columnDefinition = "jsonb")
    @Builder.Default
    private List<EhrCodeValue> encounterTypes = List.of();

    @Column(name = "period_start", length = 40)
    private String periodStart;

    @Column(name = "period_start_precision", length = 16)
    private String periodStartPrecision;

    @Column(name = "period_end", length = 40)
    private String periodEnd;

    @Column(name = "period_end_precision", length = 16)
    private String periodEndPrecision;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "participants", nullable = false, columnDefinition = "jsonb")
    @Builder.Default
    private List<EhrEncounterParticipantValue> participants = List.of();

    @Column(name = "service_provider_reference", length = 512)
    private String serviceProviderReference;

    @Column(name = "service_provider_display", length = 512)
    private String serviceProviderDisplay;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "locations", nullable = false, columnDefinition = "jsonb")
    @Builder.Default
    private List<EhrReferenceValue> locations = List.of();

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "reason_codes", nullable = false, columnDefinition = "jsonb")
    @Builder.Default
    private List<EhrCodeValue> reasonCodes = List.of();

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "diagnosis_references", nullable = false, columnDefinition = "jsonb")
    @Builder.Default
    private List<EhrReferenceValue> diagnosisReferences = List.of();

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "appointment_references", nullable = false, columnDefinition = "jsonb")
    @Builder.Default
    private List<EhrReferenceValue> appointmentReferences = List.of();
}
