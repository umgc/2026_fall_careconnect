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
 * A medication as reported by one external source — a projected FHIR {@code MedicationRequest},
 * {@code MedicationStatement} or {@code Medication} (Team E brief S5; Cononical_5_1 Step 6).
 *
 * <p>Follows the typed-projection stem convention (non-negotiable per the brief, columns are ours):
 * {@code patient_id} + {@code source_id} (Long, NOT NULL), {@code external_medication_id} (String,
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
        name = "ehr_medication_record",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_ehr_medication_record_source_external",
                columnNames = {"patient_id", "source_id", "external_medication_id"}),
        indexes = @Index(
                name = "idx_ehr_medication_record_patient",
                columnList = "patient_id"))
public class EhrMedicationRecord extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    /** References {@code ehr_source.id}. */
    @Column(name = "source_id", nullable = false)
    private Long sourceId;

    /** The resource's own id within that source. NOT NULL so the unique key dedups. */
    @Column(name = "external_medication_id", nullable = false, length = 255)
    private String externalMedicationId;

    /** The source's own last-modified time ({@code meta.lastUpdated}); compared across sources. */
    @Column(name = "source_updated_at", nullable = false)
    private Instant sourceUpdatedAt;

    /** Human-readable drug name. */
    @Column(name = "medication_display", length = 512)
    private String medicationDisplay;

    /** RxNorm coding, when present. */
    @Column(name = "rxnorm_code", length = 128)
    private String rxnormCode;

    /** Free-text sig / dosage instruction. */
    @Column(name = "dosage_text", length = 1024)
    private String dosageText;

    /** Route of administration, e.g. oral / IV. */
    @Column(name = "route", length = 128)
    private String route;

    /** Frequency, e.g. BID / daily. */
    @Column(name = "frequency", length = 128)
    private String frequency;

    /** When the medication was authored (calendar date). */
    @Column(name = "authored_on")
    private LocalDate authoredOn;

    /** Status-gated value, e.g. active / completed. */
    @Column(name = "status", length = 32)
    private String status;
}
