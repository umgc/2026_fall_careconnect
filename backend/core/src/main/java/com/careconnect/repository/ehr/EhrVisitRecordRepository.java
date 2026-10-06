package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrVisitRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.data.repository.query.Param;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.jpa.repository.Modifying;

import java.time.LocalDateTime;
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

    /**
     * Unlink (FR-MCR-11, Addendum A1-Q1): removes every row this source holds for this patient.
     * Called by {@code MedicareConnectionService.disconnect} inside its transaction.
     */
    @Modifying
    @Transactional
    @Query("delete from EhrVisitRecord e where e.patientId = :patientId and e.sourceId = :sourceId")
    int deleteAllForPatientAndSource(@Param("patientId") Long patientId, @Param("sourceId") Long sourceId);

    /**
     * Retention purge (#214), step one: who has visit rows this application last stored before
     * {@code cutoff}. Measured from {@code updated_at}, as for {@code ehr_source_identity}.
     */
    @Query("select distinct v.patientId as patientId, pt.dob as dob "
            + "from EhrVisitRecord v left join Patient pt on pt.id = v.patientId "
            + "where v.updatedAt < :cutoff")
    List<PatientDateOfBirth> findPatientsWithVisitUpdatedBefore(@Param("cutoff") LocalDateTime cutoff);

    /** Retention purge, step two: removes those rows for the given patients only. */
    @Modifying
    @Transactional
    @Query("delete from EhrVisitRecord v where v.updatedAt < :cutoff and v.patientId in :patientIds")
    int deleteUpdatedBeforeForPatients(
            @Param("cutoff") LocalDateTime cutoff, @Param("patientIds") List<Long> patientIds);
}
