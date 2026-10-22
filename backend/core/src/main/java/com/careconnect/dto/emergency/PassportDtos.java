package com.careconnect.dto.emergency;

import com.careconnect.model.emergency.BloodType;
import com.careconnect.model.emergency.PassportField;
import com.fasterxml.jackson.annotation.JsonInclude;

import java.time.Instant;
import java.util.List;
import java.util.Map;

/**
 * Request and response shapes for the Emergency Care Passport (CC-12, Increment 2).
 */
public final class PassportDtos {

    private PassportDtos() {
    }

    /** One allergy as the passport shows it. {@code severity} is the {@code AllergySeverity} name. */
    public record AllergyItem(String allergen, String severity, String reaction) {
    }

    /** One active, approved medication as the passport shows it. */
    public record MedicationItem(String name, String dosage, String frequency) {
    }

    public record EmergencyContact(String name, String relationship, String phone) {
    }

    /** The patient-entered passport fields. A PUT replaces all of them; an omitted field is cleared. */
    public record ProfileRequest(
            BloodType bloodType,
            String chronicConditions,
            String emergencyContactName,
            String emergencyContactRelationship,
            String emergencyContactPhone) {
    }

    public record VisibilityRequest(Boolean isPublic) {
    }

    /** The state of the patient's QR code. Never carries the raw token. */
    public record TokenStatus(boolean active, Instant createdAt, Instant lastScannedAt) {
    }

    /**
     * Everything the patient's passport page needs (design screen 1).
     *
     * @param sharing every {@link PassportField}, true only where the patient opted in
     * @param token   null when the patient has never made a code or has revoked it
     * @param ready   an active code and at least one shared section
     * @param lastUpdated          the latest change to any section with content, shared or not;
     *                             null when every section is empty
     * @param lastUpdatedBySection when each section with content last changed; an empty section
     *                             has no entry. Blood type, conditions and contact share one profile
     *                             row, so they share its date.
     */
    public record PassportView(
            String name,
            Integer age,
            BloodType bloodType,
            String chronicConditions,
            EmergencyContact emergencyContact,
            List<AllergyItem> allergies,
            List<MedicationItem> medications,
            Map<PassportField, Boolean> sharing,
            TokenStatus token,
            boolean ready,
            Instant lastUpdated,
            Map<PassportField, Instant> lastUpdatedBySection) {
    }

    /**
     * Returned once, when a code is made. {@code token} and {@code url} are never available again;
     * the patient saves the QR or makes a new code.
     */
    public record NewTokenResponse(String token, String url, Instant createdAt) {
    }

    /**
     * What a scan shows (design screen 3). Name and age are always present when known; every other
     * section is present only if the patient made it public AND it has content. A hidden section is
     * absent, not null or empty, so the response does not reveal that it exists. An empty shared
     * list is also absent: "no allergies listed" must not read as "no allergies".
     * <p>
     * {@code lastUpdated} is the latest change to the sections shown, so a responder can judge how
     * current they are. Hidden sections never count, or the date would hint at data the patient chose
     * not to show; absent when no section is shown.
     */
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public record PublicPassport(
            String name,
            Integer age,
            BloodType bloodType,
            List<AllergyItem> allergies,
            List<MedicationItem> medications,
            String chronicConditions,
            EmergencyContact emergencyContact,
            Instant lastUpdated) {
    }
}
