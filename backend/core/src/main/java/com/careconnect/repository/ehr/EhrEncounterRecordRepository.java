package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrEncounterRecord;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

/** Access to source-separated normalized Encounter records. */
public interface EhrEncounterRecordRepository extends JpaRepository<EhrEncounterRecord, Long> {

    Optional<EhrEncounterRecord> findByPatientIdAndSourceIdAndExternalEncounterId(
            Long patientId, Long sourceId, String externalEncounterId);

    List<EhrEncounterRecord> findByPatientIdAndSourceId(Long patientId, Long sourceId);
}
