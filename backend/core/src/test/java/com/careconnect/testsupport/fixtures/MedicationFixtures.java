package com.careconnect.testsupport.fixtures;

import com.careconnect.model.Medication;
import com.careconnect.model.Patient;

/**
 * Shared medication fixture builders for backend unit tests.
 *
 * <p>
 * These fixtures intentionally keep data local and deterministic so unit tests
 * can validate service logic without live DB or external calls.
 * </p>
 */
public final class MedicationFixtures {

    private MedicationFixtures() {
        // Utility class
    }

    /**
     * Returns an active, persisted-like medication owned by the given patient.
     */
    public static Medication activeMedication(Long id, Patient patient) {
        return Medication.builder()
                .id(id)
                .patient(patient)
                .medicationName("Lisinopril")
                .dosage("10mg")
                .frequency("once daily")
                .route("oral")
                .isActive(true)
                .build();
    }

    /**
     * Returns the same medication after it has been deactivated.
     */
    public static Medication inactiveMedication(Long id, Patient patient) {
        final Medication medication = activeMedication(id, patient);
        medication.setIsActive(false);
        return medication;
    }
}
