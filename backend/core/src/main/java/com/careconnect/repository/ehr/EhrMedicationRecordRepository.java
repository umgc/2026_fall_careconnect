package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrMedicationRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface EhrMedicationRecordRepository extends JpaRepository<EhrMedicationRecord, Long> {

    /** Every medication held for this patient, newest source update first. */
    List<EhrMedicationRecord> findByPatientIdOrderBySourceUpdatedAtDesc(Long patientId);

    /** Medications from one source only. */
    List<EhrMedicationRecord> findByPatientIdAndSourceId(Long patientId, Long sourceId);

    /** Used to upsert rather than duplicate on re-sync; matches the unique constraint. */
    Optional<EhrMedicationRecord> findByPatientIdAndSourceIdAndExternalMedicationId(
            Long patientId, Long sourceId, String externalMedicationId);

    /** Disconnect cleanup: removes every row this source holds for this patient. */
    @Modifying
    @Transactional
    @Query("delete from EhrMedicationRecord e where e.patientId = :patientId and e.sourceId = :sourceId")
    int deleteAllForPatientAndSource(@Param("patientId") Long patientId, @Param("sourceId") Long sourceId);

    /**
     * Retention purge (#214), step one: who has medication rows this application last stored before
     * {@code cutoff}. Measured from {@code updated_at}, as for {@code ehr_source_identity}: a row
     * still being synced is rewritten, so only data nobody has refreshed in the period ages out.
     */
    @Query("select distinct m.patientId as patientId, pt.dob as dob "
            + "from EhrMedicationRecord m left join Patient pt on pt.id = m.patientId "
            + "where m.updatedAt < :cutoff")
    List<PatientDateOfBirth> findPatientsWithMedicationUpdatedBefore(@Param("cutoff") LocalDateTime cutoff);

    /** Retention purge, step two: removes those rows for the given patients only. */
    @Modifying
    @Transactional
    @Query("delete from EhrMedicationRecord m where m.updatedAt < :cutoff and m.patientId in :patientIds")
    int deleteUpdatedBeforeForPatients(
            @Param("cutoff") LocalDateTime cutoff, @Param("patientIds") List<Long> patientIds);
}
