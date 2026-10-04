package com.careconnect.model.ehr;

import com.careconnect.model.Auditable;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;

/**
 * Which source is currently freshest for one field of one patient — the row the reconciliation
 * algorithm locks.
 * <p>
 * This table exists for its lock, not its data. {@code IdentityFieldProvenanceStore.lockOrCreate}
 * takes {@code SELECT ... FOR UPDATE} against {@code (patient_id, field_name)} and holds it for
 * the rest of that field's processing — the read of {@code patient}, the conditional write back,
 * and the audit row. Without it, two adapters landing seconds apart can interleave so the
 * <em>older</em> value wins, which surfaces as an intermittent data bug rather than an error.
 * The library's adversarial test demonstrates exactly that against a deliberately non-locking
 * store.
 * <p>
 * A row is created empty purely so there is something to lock the first time a field is touched.
 * Both {@code sourceId} and {@code sourceUpdatedAt} are therefore nullable, and null means "no
 * source has established provenance for this field yet" — which the store must surface as
 * {@code Optional.empty()}, falling back to the patient record's own timestamp.
 * <p>
 * Carries no organization column: {@code orgId} was removed from the library's interfaces on
 * 2026-09-29 because nothing in this codebase could supply one. Do not re-add it without a real
 * tenant model, and do not change the {@code (patient_id, field_name)} key without re-running
 * the adversarial proof — the concurrency guarantee rests on it.
 */
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(
        name = "ehr_identity_field_provenance",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_ehr_identity_field_provenance_patient_field",
                columnNames = {"patient_id", "field_name"}))
public class EhrIdentityFieldProvenance extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    /** Same field-name vocabulary as {@code ehr_identity_conflict.field_name}. */
    @Column(name = "field_name", nullable = false, length = 64)
    private String fieldName;

    /** Null until a source establishes provenance. References {@code ehr_source.id}. */
    @Column(name = "source_id")
    private Long sourceId;

    /** Null until a source establishes provenance. */
    @Column(name = "source_updated_at")
    private Instant sourceUpdatedAt;
}
