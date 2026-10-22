package com.careconnect.integration.cerner;

import com.careconnect.model.ehr.EhrAppointmentRecord;
import com.careconnect.model.ehr.EhrSourceIdentity;
import java.time.Instant;
import java.util.List;

/** Read-only Patient and bounded Appointment synchronization for Oracle Health/Cerner. */
public interface CernerPatientAppointmentService {

    EhrSourceIdentity synchronizePatient(long patientId);

    /** Returns the normalized identity together with the authorized source record identifier. */
    PatientSynchronization synchronizePatientWithSourceRecord(long patientId);

    List<EhrAppointmentRecord> synchronizeAppointments(
            long patientId, Instant startInclusive, Instant endExclusive);

    record PatientSynchronization(
            String sourceRecordId, EhrSourceIdentity identity) { }
}
