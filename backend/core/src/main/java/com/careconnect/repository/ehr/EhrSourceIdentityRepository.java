package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrSourceIdentity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface EhrSourceIdentityRepository extends JpaRepository<EhrSourceIdentity, Long> {

    /** The current snapshot from one source. At most one exists, per the unique constraint. */
    Optional<EhrSourceIdentity> findByPatientIdAndSourceId(Long patientId, Long sourceId);

    /** Every source's view of this patient, for cross-source comparison. */
    List<EhrSourceIdentity> findByPatientId(Long patientId);

    /**
     * Retention purge, step one: who has a snapshot this application last wrote before
     * {@code cutoff}. Measured on {@code updated_at}, when we last stored it, and not on
     * {@code source_updated_at}: a source whose demographics have not changed in years still
     * reports an old {@code source_updated_at} on every sync, so a row re-created by the next
     * sync would be purged again the same night.
     */
    @Query("select distinct i.patientId as patientId, pt.dob as dob "
            + "from EhrSourceIdentity i left join Patient pt on pt.id = i.patientId "
            + "where i.updatedAt < :cutoff")
    List<PatientDateOfBirth> findPatientsWithSnapshotUpdatedBefore(@Param("cutoff") LocalDateTime cutoff);

    /** Retention purge, step two: removes those snapshots for the given patients only. */
    @Modifying
    @Transactional
    @Query("delete from EhrSourceIdentity i where i.updatedAt < :cutoff and i.patientId in :patientIds")
    int deleteUpdatedBeforeForPatients(
            @Param("cutoff") LocalDateTime cutoff, @Param("patientIds") List<Long> patientIds);

    /**
     * Unlink (FR-MCR-11, Addendum A1-Q1): removes every row this source holds for this patient.
     * Called by {@code MedicareConnectionService.disconnect} inside its transaction.
     */
    @Modifying
    @Transactional
    @Query("delete from EhrSourceIdentity e where e.patientId = :patientId and e.sourceId = :sourceId")
    int deleteAllForPatientAndSource(@Param("patientId") Long patientId, @Param("sourceId") Long sourceId);
}
