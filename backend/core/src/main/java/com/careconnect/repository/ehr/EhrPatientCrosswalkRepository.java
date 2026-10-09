package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrPatientCrosswalk;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface EhrPatientCrosswalkRepository extends JpaRepository<EhrPatientCrosswalk, Long> {

    /** The patient's identifier in one source, if they have been linked to it. */
    Optional<EhrPatientCrosswalk> findByPatientIdAndSourceId(Long patientId, Long sourceId);

    /**
     * Reverse lookup used when a source reports an identifier and the owning patient must be
     * found. Returning the crosswalk row does not by itself authorize access to that patient;
     * callers still apply their own authorization check. (This previously cited FR-CERN-06 and
     * BR-11, which are not in SRS 1.4 Integrated -- see {@code EhrPatientCrosswalk}.)
     */
    Optional<EhrPatientCrosswalk> findBySourceIdAndExternalPatientId(
            Long sourceId, String externalPatientId);

    /** Every source this patient is linked to. */
    List<EhrPatientCrosswalk> findByPatientId(Long patientId);

    /* Find the user trying to link their accounts by the link token */
    Optional<EhrPatientCrosswalk> findByLinkToken(String linkToken);
}
