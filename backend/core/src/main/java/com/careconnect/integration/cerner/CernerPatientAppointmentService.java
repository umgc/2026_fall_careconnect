package com.careconnect.integration.cerner;

import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrAppointmentRecord;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.model.ehr.EhrSourceIdentity;
import com.fasterxml.jackson.databind.JsonNode;

import java.time.Instant;
import java.time.LocalDateTime;
import java.util.List;

/** Read-only Patient and bounded Appointment synchronization for Oracle Health/Cerner. */
public interface CernerPatientAppointmentService {

    EhrSourceIdentity synchronizePatient(long patientId);

    /** Returns the normalized identity together with the authorized source record identifier. */
    PatientSynchronization synchronizePatientWithSourceRecord(long patientId);

    /**
     * Synchronizes Appointment records for the given patient within the provided time window \(`startInclusive`, `endExclusive`\).
     */
    List<EhrAppointmentRecord> synchronizeAppointments(
            long patientId, Instant startInclusive, Instant endExclusive);

    record PatientSynchronization(
            String sourceRecordId, EhrSourceIdentity identity) { }

//    /** Patient mapping with optional fields absent. */
//    EhrSourceIdentity synchronizePatientWithOptionalFieldsAbsent(long patientId);
//
//    /** Additional Patient mapping edge cases. */
//    EhrSourceIdentity synchronizePatientEdgeCases(long patientId);

    /** Appointment successful token refresh. */
    List<EhrAppointmentRecord> synchronizeAppointmentsWithTokenRefresh(
            long patientId, Instant startInclusive, Instant endExclusive);

    /** Empty Appointment results at the service/integration level. */
    List<EhrAppointmentRecord> synchronizeAppointmentsAllowingEmptyResults(
            long patientId, Instant startInclusive, Instant endExclusive);

    /** Patient and Appointment pagination and rate limiting. */
    List<EhrAppointmentRecord> synchronizeAppointmentsWithPaginationAndRateLimiting(
            long patientId, Instant startInclusive, Instant endExclusive);

    /** Patient\-reference or participant mismatches. */
    List<EhrAppointmentRecord> synchronizeAppointmentsWithReferenceMismatchHandling(
            long patientId, Instant startInclusive, Instant endExclusive);

//    /** Missing or malformed Appointment date parameters. */
//    List<EhrAppointmentRecord> synchronizeAppointmentsWithDateValidation(
//            long patientId, Instant startInclusive, Instant endExclusive);

//    /** Patient\-not\-found controller response. */
//    EhrSourceIdentity synchronizePatientOrNotFound(long patientId);

//    /** Timeout and rate\-limit controller error envelopes. */
//    List<EhrAppointmentRecord> synchronizeAppointmentsWithTimeoutAndRateLimitHandling(
//            long patientId, Instant startInclusive, Instant endExclusive);

    /** Patient and Appointment expected\-output fixture validation. */
    boolean validatePatientAndAppointmentExpectedOutputFixtures(
            long patientId, Instant startInclusive, Instant endExclusive);

}
