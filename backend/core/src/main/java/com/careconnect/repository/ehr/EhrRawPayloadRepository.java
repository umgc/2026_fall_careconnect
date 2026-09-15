package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrRawPayload;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

/** Access to raw FHIR resources fetched from EHR sources. */
public interface EhrRawPayloadRepository extends JpaRepository<EhrRawPayload, Long> {

    /**
     * The payload already stored for this resource, if any. A re-fetch of the same resource
     * updates this row instead of stacking a duplicate raw copy.
     */
    Optional<EhrRawPayload> findByPatientIdAndSourceIdAndResourceTypeAndExternalResourceId(
            Long patientId, Long sourceId, String resourceType, String externalResourceId);
}
