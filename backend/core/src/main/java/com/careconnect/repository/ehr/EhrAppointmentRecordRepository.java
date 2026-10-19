package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrAppointmentRecord;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

/** Access to per-source appointment records. */
public interface EhrAppointmentRecordRepository extends JpaRepository<EhrAppointmentRecord, Long> {

    /**
     * The row an adapter should upsert into for one appointment. This triple is the idempotency
     * key that makes a re-run of an interrupted or repeated sync safe.
     */
    Optional<EhrAppointmentRecord> findByPatientIdAndSourceIdAndExternalAppointmentId(
            Long patientId, Long sourceId, String externalAppointmentId);

    /** All appointments for a patient across every source. */
    List<EhrAppointmentRecord> findByPatientId(Long patientId);
}
