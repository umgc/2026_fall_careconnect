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
 * Insurance coverage as reported by one external source — a mapped FHIR {@code Coverage}.
 * <p>
 * Named for the canonical schema ({@code ehr_coverage_record}) rather than the earlier
 * {@code ehr_coverage}, so it does not become a second table alongside the one the plan
 * describes. That matters more than style here: this application applies schema with Hibernate
 * {@code ddl-auto=update}, which only ever adds, so two names would mean two tables rather than
 * a rename.
 * <p>
 * Still gated on §2.2 — no FR-EHR requirement covers Coverage retrieval yet. The table shape is
 * ready; the requirement backing it is not.
 */
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(
        name = "ehr_coverage_record",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_ehr_coverage_record_source_external",
                columnNames = {"patient_id", "source_id", "external_coverage_id"}),
        indexes = @Index(
                name = "idx_ehr_coverage_record_patient",
                columnList = "patient_id"))
public class EhrCoverageRecord extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** Was {@code client_id}; renamed to match the column it references. */
    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    /**
     * References {@code ehr_source.id}. Was a free-text source name, which made a column called
     * {@code source_id} hold something that was not an id and could not be constrained.
     */
    @Column(name = "source_id", nullable = false)
    private Long sourceId;

    /** The Coverage resource's own id within that source. */
    @Column(name = "external_coverage_id", length = 255)
    private String externalCoverageId;

    /**
     * The source's own last-modified time. An {@link Instant}, not {@code LocalDateTime}: it is
     * compared across sources, where a zone-less value can read as newer than it is.
     */
    @Column(name = "source_updated_at", nullable = false)
    private Instant sourceUpdatedAt;

    @Column(name = "beneficiary", length = 255)
    private String beneficiary;

    @Column(name = "subscriber_id", length = 255)
    private String subscriberId;

    @Column(name = "payor", length = 255)
    private String payor;

    @Column(name = "network", length = 255)
    private String network;

    /** FHIR Coverage.status, e.g. active, cancelled, entered-in-error. How the
     *  entered-in-error and cancelled cases are surfaced is still undecided. */
    @Column(name = "status", length = 32)
    private String status;

    /** Coverage type/plan description as the source words it. */
    @Column(name = "coverage_type", length = 255)
    private String coverageType;

    /** Was a LocalDateTime; a coverage period end is a date. */
    @Column(name = "expires_on")
    private LocalDate expiresOn;
}
