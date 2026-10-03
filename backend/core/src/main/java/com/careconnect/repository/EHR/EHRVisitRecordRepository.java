package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrVisitRecord;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.List;

public interface EhrVisitRecordRepository extends JpaRepository<EhrVisitRecord, Long> {
    /** Visit history for a patient, most recent care first. */
    List<EhrVisitRecord> findByPatientIdOrderByServiceDateDesc(Long patientId);

    /** One source's view. Note rows from different sources may describe the same real visit:
     *  cross-source delta-flagging (FR-XSRC-03/04) is not implemented. */
    List<EhrVisitRecord> findByPatientIdAndSourceId(Long patientId, Long sourceId);

    /** Used to upsert rather than duplicate on re-sync; matches the unique constraint. */
    Optional<EhrVisitRecord> findByPatientIdAndSourceIdAndExternalVisitId(
            Long patientId, Long sourceId, String externalVisitId);
}
