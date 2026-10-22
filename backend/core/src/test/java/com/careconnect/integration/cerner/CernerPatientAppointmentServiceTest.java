package com.careconnect.integration.cerner;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertSame;

import com.careconnect.model.ehr.EhrSourceIdentity;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;

/** Contract coverage for types declared by {@link CernerPatientAppointmentService}. */
class CernerPatientAppointmentServiceTest {

    @Test
    @Tag("M3-REQ-01")
    void patientSynchronizationRetainsSourceRecordAndNormalizedIdentity() {
        final EhrSourceIdentity identity = EhrSourceIdentity.builder()
                .givenName("Synthetic")
                .familyName("Patient")
                .build();

        final var synchronization =
                new CernerPatientAppointmentService.PatientSynchronization(
                        "cerner-patient-12742400", identity);

        assertEquals("cerner-patient-12742400", synchronization.sourceRecordId());
        assertSame(identity, synchronization.identity());
    }
}
