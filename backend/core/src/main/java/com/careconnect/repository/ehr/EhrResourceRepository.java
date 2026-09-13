package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrResource;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

/**
 * Persistence for the Epic FHIR resource mirror {@link EhrResource} (Epic Phase 1).
 */
public interface EhrResourceRepository extends JpaRepository<EhrResource, Long> {

    Optional<EhrResource> findByUserIdAndSourceAndResourceTypeAndResourceFhirId(
            Long userId, String source, String resourceType, String resourceFhirId);

    List<EhrResource> findByUserIdAndSource(Long userId, String source);

    void deleteByUserIdAndSource(Long userId, String source);
}
