package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrConflictStatus;
import com.careconnect.model.ehr.EhrIdentityConflict;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

/** Access to field-level identity conflicts awaiting or holding a resolution. */
public interface EhrIdentityConflictRepository extends JpaRepository<EhrIdentityConflict, Long> {

    /**
     * Conflicts a patient still needs to act on. Backs the post-link confirmation flow, which
     * re-reads this on every login rather than holding pending state in client memory.
     */
    List<EhrIdentityConflict> findByPatientIdAndStatus(Long patientId, EhrConflictStatus status);

    /** Cheap check for whether to surface the confirmation prompt or badge at all. */
    boolean existsByPatientIdAndStatus(Long patientId, EhrConflictStatus status);

    /**
     * The single open conflict for a field, if any. Uniqueness is enforced by the partial index
     * {@code uq_ehr_identity_conflict_open} so a repeated sync updates rather than duplicates.
     */
    Optional<EhrIdentityConflict> findByPatientIdAndSourceIdAndFieldNameAndStatus(
            Long patientId, Long sourceId, String fieldName, EhrConflictStatus status);
}
