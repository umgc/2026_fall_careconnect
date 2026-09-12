package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrSourceIdentity;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

/** Access to per-source demographic snapshots. */
public interface EhrSourceIdentityRepository extends JpaRepository<EhrSourceIdentity, Long> {

    /**
     * Looks up the snapshot an adapter should upsert into. This pair is unique, enforced by
     * {@code uq_ehr_source_identity_patient_source}, which is what makes a re-run of an
     * interrupted sync idempotent.
     */
    Optional<EhrSourceIdentity> findByPatientIdAndSourceId(Long patientId, Long sourceId);

    /** All snapshots for a patient, for the reconciler to diff across sources. */
    List<EhrSourceIdentity> findByPatientId(Long patientId);
}
