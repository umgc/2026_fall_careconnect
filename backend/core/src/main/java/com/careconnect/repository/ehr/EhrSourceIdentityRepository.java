package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrSourceIdentity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface EhrSourceIdentityRepository extends JpaRepository<EhrSourceIdentity, Long> {

    /** The current snapshot from one source. At most one exists, per the unique constraint. */
    Optional<EhrSourceIdentity> findByPatientIdAndSourceId(Long patientId, Long sourceId);

    /** Every source's view of this patient, for cross-source comparison. */
    List<EhrSourceIdentity> findByPatientId(Long patientId);
}
