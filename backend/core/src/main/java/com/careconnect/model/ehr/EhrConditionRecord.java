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
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.time.LocalDate;

/**
 * A condition / problem as reported by one external source — a projected FHIR {@code Condition}
 * (Team E brief S5; Cononical_5_1 Step 6).
 *
 * <p>Follows the typed-projection stem convention (non-negotiable per the brief, columns are ours):
 * {@code patient_id} + {@code source_id} (Long, NOT NULL), {@code external_condition_id} (String,
 * NOT NULL so the unique key dedups — NULL != NULL in PostgreSQL), {@code source_updated_at}
 * (Instant, NOT NULL), {@code extends Auditable}, and {@code LocalDate} for calendar dates. Sits
 * alongside {@link EhrCoverageRecord} and {@link EhrVisitRecord}; the Epic connector fills it from
 * JSON via {@code EpicCanonicalProjector}.
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

    /** References {@code ehr_source.id}. */
    @Column(name = "source_id", nullable = false)
    private Long sourceId;

    /** The resource's own id within that source. NOT NULL so the unique key dedups. */
    @Column(name = "external_condition_id", nullable = false, length = 255)
    private String externalConditionId;

    /** The source's own last-modified time ({@code meta.lastUpdated}); compared across sources. */
    @Column(name = "source_updated_at", nullable = false)
    private Instant sourceUpdatedAt;

    /** Human-readable condition name. */
    @Column(name = "condition_display", length = 512)
    private String conditionDisplay;

    /** Coding, e.g. ICD-10 / SNOMED. */
    @Column(name = "code", length = 128)
    private String code;

    /** FHIR Condition.clinicalStatus, e.g. active / resolved. */
    @Column(name = "clinical_status", length = 32)
    private String clinicalStatus;

    /** FHIR Condition.verificationStatus, e.g. confirmed / provisional. */
    @Column(name = "verification_status", length = 32)
    private String verificationStatus;

    /** Onset as a calendar date, when given to day precision. */
    @Column(name = "onset_date")
    private LocalDate onsetDate;

    /** When the condition was recorded (calendar date). */
    @Column(name = "recorded_date")
    private LocalDate recordedDate;
}
