package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrObservationRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;

public interface EhrObservationRecordRepository extends JpaRepository<EhrObservationRecord, Long> {

    /** Every observation held for this patient, newest source update first. */
    List<EhrObservationRecord> findByPatientIdOrderBySourceUpdatedAtDesc(Long patientId);

    /** Observations from one source only. */
    List<EhrObservationRecord> findByPatientIdAndSourceId(Long patientId, Long sourceId);

    /** Used to upsert rather than duplicate on re-sync; matches the unique constraint. */
    Optional<EhrObservationRecord> findByPatientIdAndSourceIdAndExternalObservationId(
            Long patientId, Long sourceId, String externalObservationId);

    /** Disconnect cleanup: removes every row this source holds for this patient. */
    @Modifying
    @Transactional
    @Query("delete from EhrObservationRecord e where e.patientId = :patientId and e.sourceId = :sourceId")
    int deleteAllForPatientAndSource(@Param("patientId") Long patientId, @Param("sourceId") Long sourceId);
}
