package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrConditionRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;

public interface EhrConditionRecordRepository extends JpaRepository<EhrConditionRecord, Long> {

    /** Every condition held for this patient, newest source update first. */
    List<EhrConditionRecord> findByPatientIdOrderBySourceUpdatedAtDesc(Long patientId);

    /** Conditions from one source only. */
    List<EhrConditionRecord> findByPatientIdAndSourceId(Long patientId, Long sourceId);

    /** Used to upsert rather than duplicate on re-sync; matches the unique constraint. */
    Optional<EhrConditionRecord> findByPatientIdAndSourceIdAndExternalConditionId(
            Long patientId, Long sourceId, String externalConditionId);

    /** Disconnect cleanup: removes every row this source holds for this patient. */
    @Modifying
    @Transactional
    @Query("delete from EhrConditionRecord e where e.patientId = :patientId and e.sourceId = :sourceId")
    int deleteAllForPatientAndSource(@Param("patientId") Long patientId, @Param("sourceId") Long sourceId);
}
