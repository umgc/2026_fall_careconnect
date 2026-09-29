package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrCoverageRecord;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface EhrCoverageRecordRepository extends JpaRepository<EhrCoverageRecord, Long> {

    /** Every coverage held for this patient, newest source update first. */
    List<EhrCoverageRecord> findByPatientIdOrderBySourceUpdatedAtDesc(Long patientId);

    /** Coverage from one source only. */
    List<EhrCoverageRecord> findByPatientIdAndSourceId(Long patientId, Long sourceId);

    /** Used to upsert rather than duplicate on re-sync; matches the unique constraint. */
    Optional<EhrCoverageRecord> findByPatientIdAndSourceIdAndExternalCoverageId(
            Long patientId, Long sourceId, String externalCoverageId);
}
