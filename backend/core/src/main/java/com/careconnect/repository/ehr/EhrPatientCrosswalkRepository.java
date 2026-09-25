package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrPatientCrosswalk;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

/** Access to source-issued patient identity mappings. */
public interface EhrPatientCrosswalkRepository extends JpaRepository<EhrPatientCrosswalk, Long> {

    /**
     * The external identifier an adapter should use to call its source's API for this patient.
     */
    Optional<EhrPatientCrosswalk> findByPatientIdAndSourceId(Long patientId, Long sourceId);

    /**
     * The internal patient a source's own identifier resolves to, for example when handling an
     * inbound webhook keyed by the source's id rather than ours.
     */
    Optional<EhrPatientCrosswalk> findBySourceIdAndExternalPatientId(
            Long sourceId, String externalPatientId);
}
