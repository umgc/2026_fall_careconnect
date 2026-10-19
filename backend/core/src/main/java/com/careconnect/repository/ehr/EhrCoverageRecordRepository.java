package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrCoverageRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.data.repository.query.Param;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.jpa.repository.Modifying;

import java.time.LocalDateTime;
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

    /**
     * Retention purge (#214), step one: who has coverage rows this application last stored before
     * {@code cutoff}. Measured from {@code updated_at}, as for {@code ehr_source_identity}: a row
     * still being synced is rewritten, so only data nobody has refreshed in the period ages out.
     */
    @Query("select distinct c.patientId as patientId, pt.dob as dob "
            + "from EhrCoverageRecord c left join Patient pt on pt.id = c.patientId "
            + "where c.updatedAt < :cutoff")
    List<PatientDateOfBirth> findPatientsWithCoverageUpdatedBefore(@Param("cutoff") LocalDateTime cutoff);

    /** Retention purge, step two: removes those rows for the given patients only. */
    @Modifying
    @Transactional
    @Query("delete from EhrCoverageRecord c where c.updatedAt < :cutoff and c.patientId in :patientIds")
    int deleteUpdatedBeforeForPatients(
            @Param("cutoff") LocalDateTime cutoff, @Param("patientIds") List<Long> patientIds);
}
