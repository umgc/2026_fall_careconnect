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
 * The Emergency Care Passport fields that have no home elsewhere in the schema (CC-12,
 * Increment 1): blood type, chronic conditions and one designated emergency contact. One row per
 * patient.
 * <p>
 * Allergies and medications are deliberately absent. They already live in
 * {@code patient_allergy} and {@code patient_medication}, and copying them here would give the
 * passport a second, drifting version of the same clinical facts.
 * <p>
 * Holding a value here does not make it visible. Whether a field is shown on the public passport
 * is decided only by {@link EmergencyPassportFieldVisibility}, and the default there is hidden.
 * <p>
 * {@code chronicConditions} is a single free-text summary, the reduced-scope default agreed for
 * M4. A structured one-row-per-condition table is a later change, not something to emulate by
 * parsing this column.
 * <p>
 * The emergency contact is entered for the passport and is independent of the patient's linked
 * family members, which the existing Vial of Life PDF lists. A designated contact need not be a
 * CareConnect user.
 * <p>
 * Stores a bare {@code patientId} rather than {@code @ManyToOne}, matching the EHR canonical
 * tables; the foreign key, with {@code ON DELETE CASCADE}, is applied by
 * {@code SchemaPatchRunner}. Timestamps come from {@link Auditable}.
 */
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(
        name = "emergency_passport_profile",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_emergency_passport_profile_patient",
                columnNames = "patient_id"))
public class EmergencyPassportProfile extends Auditable {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    /** Null when the patient has not recorded one. */
    @Enumerated(EnumType.STRING)
    @Column(name = "blood_type", length = 16)
    private BloodType bloodType;

    @Column(name = "chronic_conditions", columnDefinition = "TEXT")
    private String chronicConditions;

    @Column(name = "emergency_contact_name", length = 255)
    private String emergencyContactName;

    @Column(name = "emergency_contact_phone", length = 32)
    private String emergencyContactPhone;

    /** Free text as the patient describes it, e.g. "daughter" or "neighbor". */
    @Column(name = "emergency_contact_relationship", length = 64)
    private String emergencyContactRelationship;
}
