package com.careconnect.testsupport.fixtures;

import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrConflictStatus;
import com.careconnect.model.ehr.EhrIdentityConflict;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.model.ehr.EhrSourceIdentity;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Map;

/**
 * Shared fixtures for EHR identity reconciliation tests.
 *
 * <p>Keeps source codes, snapshot demographics, and conflict shapes stable so reconciliation
 * tests can assert on behavior rather than restating setup.
 */
public final class EhrFixtures {

    /** Fixed detection timestamp so assertions never depend on wall-clock time. */
    public static final LocalDateTime DETECTED_AT = LocalDateTime.of(2026, 9, 12, 10, 0);

    /** Fixed source-side update timestamp, used for recency comparisons. */
    public static final LocalDateTime SOURCE_UPDATED_AT = LocalDateTime.of(2026, 9, 11, 8, 30);

    private EhrFixtures() {
        // Utility class
    }

    /** Returns an unsaved athenahealth source registry row. */
    public static EhrSource athenaSource() {
        return EhrSource.builder()
                .code("ATHENA")
                .displayName("athenahealth")
                .build();
    }

    /** Returns an unsaved Epic source registry row, for cross-source conflict tests. */
    public static EhrSource epicSource() {
        return EhrSource.builder()
                .code("EPIC")
                .displayName("Epic")
                .build();
    }

    /** Returns an unsaved patient with no linked user, sufficient for FK targets. */
    public static Patient unsavedPatient() {
        return Patient.builder()
                .firstName("Jane")
                .lastName("Smith")
                .email("jane.smith@example.com")
                .build();
    }

    /** Returns an unsaved per-source snapshot for the given patient and source. */
    public static EhrSourceIdentity snapshot(final Patient patient, final EhrSource source) {
        return EhrSourceIdentity.builder()
                .patient(patient)
                .source(source)
                .sourcePatientId("a-12345")
                .firstName("Jane")
                .lastName("Smith")
                .dateOfBirth(LocalDate.of(1985, 3, 2))
                .phone("555-0100")
                .email("jane.smith@example.com")
                .addressLine1("456 Oak Ave")
                .city("Baltimore")
                .state("MD")
                .postalCode("21201")
                .sourceUpdatedAt(SOURCE_UPDATED_AT)
                .fetchedAt(DETECTED_AT)
                .rawPayload(Map.of("resourceType", "Patient", "id", "a-12345"))
                .build();
    }

    /** Returns an unsaved pending conflict for one field. */
    public static EhrIdentityConflict pendingConflict(
            final Patient patient,
            final EhrSource source,
            final String fieldName,
            final String canonicalValue,
            final String incomingValue) {
        return EhrIdentityConflict.builder()
                .patient(patient)
                .source(source)
                .fieldName(fieldName)
                .canonicalValue(canonicalValue)
                .incomingValue(incomingValue)
                .status(EhrConflictStatus.PENDING)
                .detectedAt(DETECTED_AT)
                .build();
    }
}
