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
 * What one external source currently believes about a patient's identity — the demographic
 * snapshot reconciliation compares against the canonical {@code patient} record.
 * <p>
 * One row per (patient, source), upserted on each sync rather than appended. That shape is
 * required, not stylistic: {@code RecencyWinsIdentityReconciler} diffs this against
 * {@code patient} field by field under a row lock, and an append-only history has no stable
 * row to lock.
 * <p>
 * {@code sourceUpdatedAt} is an {@link Instant} deliberately. It is the field every recency
 * comparison runs on, and it is compared <em>across</em> sources; a zone-less type would let a
 * snapshot from a source in another offset appear newer than it is and win when it should
 * lose.
 * <p>
 * Carries no organization column — see the 2026-09-26 org-scoping reversal. Stores bare
 * {@code patientId}/{@code sourceId} rather than {@code @ManyToOne}, matching the rest of this
 * package; the foreign keys are applied by {@code SchemaPatchRunner}.
 */
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(
        name = "ehr_source_identity",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_ehr_source_identity_patient_source",
                columnNames = {"patient_id", "source_id"}),
        indexes = @Index(
                name = "idx_ehr_source_identity_patient",
                columnList = "patient_id"))
public class EhrSourceIdentity extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    /** References {@code ehr_source.id}. */
    @Column(name = "source_id", nullable = false)
    private Long sourceId;

    /**
     * The source's own last-modified time for this identity, normally FHIR
     * {@code meta.lastUpdated}. Never the time we fetched it — recency means the source's
     * recency, not ours.
     */
    @Column(name = "source_updated_at", nullable = false)
    private Instant sourceUpdatedAt;

    @Column(name = "given_name", length = 100)
    private String givenName;

    @Column(name = "family_name", length = 100)
    private String familyName;

    /**
     * Held as a real date, unlike {@code patient.dob} which is currently a String. The
     * reconciliation library compares field values as strings, so an adapter converts at the
     * boundary; storing a date as text here would lose that validation for no benefit. The
     * inconsistency with {@code patient.dob} is pre-existing and worth correcting separately.
     */
    @Column(name = "date_of_birth")
    private LocalDate dateOfBirth;

    @Column(name = "phone", length = 32)
    private String phone;

    @Column(name = "email", length = 254)
    private String email;

    @Column(name = "address_line1", length = 255)
    private String addressLine1;

    @Column(name = "address_line2", length = 255)
    private String addressLine2;

    @Column(name = "city", length = 100)
    private String city;

    @Column(name = "state", length = 50)
    private String state;

    @Column(name = "postal_code", length = 20)
    private String postalCode;
}
