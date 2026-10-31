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
 * An observation / result as reported by one external source — a projected FHIR {@code Observation}
 * (Team E brief S5; Cononical_5_1 Step 6).
 *
 * <p>Follows the typed-projection stem convention (non-negotiable per the brief, columns are ours):
 * {@code patient_id} + {@code source_id} (Long, NOT NULL), {@code external_observation_id} (String,
 * NOT NULL so the unique key dedups — NULL != NULL in PostgreSQL), {@code source_updated_at}
 * (Instant, NOT NULL), {@code extends Auditable}, and {@code LocalDate} for calendar dates. Sits
 * alongside {@link EhrCoverageRecord} and {@link EhrVisitRecord}; the Epic connector fills it from
 * JSON via {@code EpicCanonicalProjector}.
 *
 * <p>{@code value_quantity} is a {@code Double}; swap to {@code BigDecimal} if exact decimal
 * precision becomes a requirement (brief: columns are ours).
 */
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(
        name = "ehr_observation_record",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_ehr_observation_record_source_external",
                columnNames = {"patient_id", "source_id", "external_observation_id"}),
        indexes = @Index(
                name = "idx_ehr_observation_record_patient",
                columnList = "patient_id"))
public class EhrObservationRecord extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    /** References {@code ehr_source.id}. */
    @Column(name = "source_id", nullable = false)
    private Long sourceId;

    /** The resource's own id within that source. NOT NULL so the unique key dedups. */
    @Column(name = "external_observation_id", nullable = false, length = 255)
    private String externalObservationId;

    /** The source's own last-modified time ({@code meta.lastUpdated}); compared across sources. */
    @Column(name = "source_updated_at", nullable = false)
    private Instant sourceUpdatedAt;

    /** Human-readable observation name. */
    @Column(name = "observation_display", length = 512)
    private String observationDisplay;

    /** LOINC coding, when present. */
    @Column(name = "loinc_code", length = 128)
    private String loincCode;

    /** Category, e.g. vital-signs / laboratory. */
    @Column(name = "category", length = 64)
    private String category;

    /** Numeric result value. */
    @Column(name = "value_quantity")
    private Double valueQuantity;

    /** UCUM unit for {@link #valueQuantity}. */
    @Column(name = "value_unit", length = 64)
    private String valueUnit;

    /** Non-numeric result, when the observation is not a quantity. */
    @Column(name = "value_string", length = 512)
    private String valueString;

    /** Reference range as the source words it. */
    @Column(name = "reference_range", length = 255)
    private String referenceRange;

    /** When the observation was taken (calendar date). */
    @Column(name = "effective_date")
    private LocalDate effectiveDate;

    /** Status-gated value, e.g. final / amended. */
    @Column(name = "status", length = 32)
    private String status;
}
