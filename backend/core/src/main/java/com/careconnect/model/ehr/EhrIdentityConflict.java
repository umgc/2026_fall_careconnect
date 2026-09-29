package com.careconnect.model.ehr;

import com.careconnect.model.Auditable;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;

/**
 * Audit row for every identity field where a source disagreed with the canonical
 * {@code patient} record — written whether the incoming value won or lost.
 * <p>
 * Recording both outcomes is the point. Recency-wins resolves non-DOB fields automatically and
 * silently, so this table is the only thing that makes a bad crosswalk — an external record
 * attached to the wrong patient — discoverable and reversible afterwards. Skipping the
 * {@code REJECTED} rows would halve its value for no saving.
 * <p>
 * <strong>{@code PENDING} is scoped to date_of_birth by a database CHECK, not by convention.</strong>
 * The 2026-09-26 reversal held DOB for patient confirmation while every other field keeps
 * resolving automatically. Nothing in application code prevents a bug writing a {@code PENDING}
 * row for {@code phone}, which would silently reintroduce exactly the risk that reversal
 * accepted everywhere except DOB — so {@code ck_ehr_identity_conflict_pending_dob} enforces it
 * where it cannot be forgotten.
 * <p>
 * Both CHECK constraints and the partial unique index are applied by {@code SchemaPatchRunner};
 * Hibernate will not create them.
 */
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(
        name = "ehr_identity_conflict",
        indexes = {
                @Index(
                        name = "idx_ehr_identity_conflict_patient_field",
                        columnList = "patient_id, field_name"),
                @Index(
                        name = "idx_ehr_identity_conflict_detected_at",
                        columnList = "detected_at")
        })
public class EhrIdentityConflict extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    /** The source that disagreed. References {@code ehr_source.id}. */
    @Column(name = "source_id", nullable = false)
    private Long sourceId;

    /**
     * Canonical field name, e.g. {@code date_of_birth}, {@code family_name}, {@code phone}.
     * Shares its vocabulary with {@code ehr_identity_field_provenance.field_name} and with the
     * keys of {@code SourceIdentitySnapshot.fields}.
     */
    @Column(name = "field_name", nullable = false, length = 64)
    private String fieldName;

    /** What {@code patient} held at the moment the disagreement was detected. */
    @Column(name = "canonical_value_before", columnDefinition = "TEXT")
    private String canonicalValueBefore;

    /** What the source offered. */
    @Column(name = "incoming_value", columnDefinition = "TEXT")
    private String incomingValue;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private EhrConflictStatus status;

    /**
     * Null while {@code PENDING}, set when the conflict closes. {@code SYSTEM} for automatic
     * recency resolution, {@code PATIENT} for a confirmed date_of_birth.
     */
    @Enumerated(EnumType.STRING)
    @Column(name = "resolved_by", length = 16)
    private EhrConflictResolver resolvedBy;

    /** The source's own last-modified time for the incoming value; an Instant for the same
     *  cross-source comparison reason as {@code EhrSourceIdentity}. */
    @Column(name = "source_updated_at", nullable = false)
    private Instant sourceUpdatedAt;

    @Column(name = "detected_at", nullable = false)
    private Instant detectedAt;

    /** Null while {@code PENDING}. For an automatic resolution this equals {@code detectedAt},
     *  since detection and resolution happen in one transaction. */
    @Column(name = "resolved_at")
    private Instant resolvedAt;
}
