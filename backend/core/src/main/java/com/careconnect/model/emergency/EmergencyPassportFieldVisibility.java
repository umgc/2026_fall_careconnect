package com.careconnect.model.emergency;

import com.careconnect.model.Auditable;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
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

/**
 * A patient's opt-in for showing one {@link PassportField} on their public Emergency Care
 * Passport (CC-12, Increment 1). One row per (patient, field).
 * <p>
 * Nothing is public by default. A missing row means hidden, and so does {@code isPublic = false};
 * only an explicit {@code true} shows a field. Readers must treat the two the same way, which is
 * why {@code EmergencyPassportFieldVisibilityRepository.findPublicFields} is the one place that
 * answers "what may be shown".
 * <p>
 * Kept as its own table rather than a flag on {@code patient_allergy} / {@code patient_medication}:
 * those tables belong to other features, and the passport's consent rules should not be spread
 * across them.
 * <p>
 * Stores a bare {@code patientId}; the foreign key, with {@code ON DELETE CASCADE}, is applied by
 * {@code SchemaPatchRunner}. Timestamps come from {@link Auditable}, so {@code updated_at} records
 * when the patient last changed this choice.
 */
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(
        name = "emergency_passport_field_visibility",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_emergency_passport_visibility_patient_field",
                columnNames = {"patient_id", "field_key"}))
public class EmergencyPassportFieldVisibility extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Enumerated(EnumType.STRING)
    @Column(name = "field_key", nullable = false, length = 30)
    private PassportField fieldKey;

    @Column(name = "is_public", nullable = false)
    @Builder.Default
    private Boolean isPublic = false;
}
