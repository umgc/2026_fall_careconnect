package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrCoverageRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.data.repository.query.Param;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.jpa.repository.Modifying;

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

    /**
     * Unlink (FR-MCR-11, Addendum A1-Q1): removes every row this source holds for this patient.
     * Called by {@code MedicareConnectionService.disconnect} inside its transaction.
     */
    @Modifying
    @Transactional
    @Query("delete from EhrCoverageRecord e where e.patientId = :patientId and e.sourceId = :sourceId")
    int deleteAllForPatientAndSource(@Param("patientId") Long patientId, @Param("sourceId") Long sourceId);
}
