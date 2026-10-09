package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrConflictResolver;
import com.careconnect.model.ehr.EhrConflictStatus;
import com.careconnect.model.ehr.EhrIdentityConflict;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

public interface EhrIdentityConflictRepository extends JpaRepository<EhrIdentityConflict, Long> {

    /**
     * The open conflict for one field, if any. Only {@code date_of_birth} can have one — the
     * database CHECK enforces that — so in practice this is the patient's pending DOB prompt.
     */
    Optional<EhrIdentityConflict> findByPatientIdAndFieldNameAndStatus(
            Long patientId, String fieldName, EhrConflictStatus status);

    /** Whether this exact candidate value from this source was already finalized with this status and resolver. */
    boolean existsByPatientIdAndSourceIdAndFieldNameAndIncomingValueAndStatusAndResolvedBy(
            Long patientId, Long sourceId, String fieldName, String incomingValue,
            EhrConflictStatus status, EhrConflictResolver resolvedBy);

    /** Everything awaiting this patient. Drives the confirmation prompt. */
    List<EhrIdentityConflict> findByPatientIdAndStatus(Long patientId, EhrConflictStatus status);

    /**
     * Full history for one patient, newest first. This is the trail that makes a bad crosswalk
     * reconstructable, so it deliberately returns resolved rows too, not just open ones.
     */
    List<EhrIdentityConflict> findByPatientIdOrderByDetectedAtDesc(Long patientId);

    /**
     * Retention purge, step one: who has conflicts that were <em>resolved</em> before
     * {@code cutoff}. Measured on {@code resolved_at}, the later of the row's two dates, so the
     * decision trail is kept for the full period after it was closed.
     * <p>
     * A {@code PENDING} row is never a candidate, however old: it is a question still waiting for
     * the patient, not a record of something that happened. Its {@code resolved_at} is null, which
     * already excludes it; the status test says so explicitly, so the exclusion does not depend on
     * a null comparison.
     */
    @Query("select distinct c.patientId as patientId, pt.dob as dob "
            + "from EhrIdentityConflict c left join Patient pt on pt.id = c.patientId "
            + "where c.status <> com.careconnect.model.ehr.EhrConflictStatus.PENDING "
            + "and c.resolvedAt < :cutoff")
    List<PatientDateOfBirth> findPatientsWithConflictResolvedBefore(@Param("cutoff") Instant cutoff);

    /** Retention purge, step two: removes those resolved conflicts for the given patients only. */
    @Modifying
    @Transactional
    @Query("delete from EhrIdentityConflict c "
            + "where c.status <> com.careconnect.model.ehr.EhrConflictStatus.PENDING "
            + "and c.resolvedAt < :cutoff and c.patientId in :patientIds")
    int deleteResolvedBeforeForPatients(
            @Param("cutoff") Instant cutoff, @Param("patientIds") List<Long> patientIds);

    /**
     * Unlink (FR-MCR-11, Addendum A1-Q1): removes every row this source holds for this patient.
     * Called by {@code MedicareConnectionService.disconnect} inside its transaction.
     */
    @Modifying
    @Transactional
    @Query("delete from EhrIdentityConflict e where e.patientId = :patientId and e.sourceId = :sourceId")
    int deleteAllForPatientAndSource(@Param("patientId") Long patientId, @Param("sourceId") Long sourceId);
}
