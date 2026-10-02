package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrConflictStatus;
import com.careconnect.model.ehr.EhrIdentityConflict;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface EhrIdentityConflictRepository extends JpaRepository<EhrIdentityConflict, Long> {

    /**
     * The open conflict for one field, if any. Only {@code date_of_birth} can have one — the
     * database CHECK enforces that — so in practice this is the patient's pending DOB prompt.
     */
    Optional<EhrIdentityConflict> findByPatientIdAndFieldNameAndStatus(
            Long patientId, String fieldName, EhrConflictStatus status);

    /** Everything awaiting this patient. Drives the confirmation prompt. */
    List<EhrIdentityConflict> findByPatientIdAndStatus(Long patientId, EhrConflictStatus status);

    /**
     * Full history for one patient, newest first. This is the trail that makes a bad crosswalk
     * reconstructable, so it deliberately returns resolved rows too, not just open ones.
     */
    List<EhrIdentityConflict> findByPatientIdOrderByDetectedAtDesc(Long patientId);
}
