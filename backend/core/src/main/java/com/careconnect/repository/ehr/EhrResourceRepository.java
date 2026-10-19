package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrResource;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
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

    /**
     * Newest {@code last_synced_at} across a user's rows for a source — the watermark a DELTA
     * re-sync filters {@code _lastUpdated} against. Null when the user has no rows for the source.
     */
    @Query("select max(e.lastSyncedAt) from EhrResource e "
            + "where e.userId = :userId and e.source = :source")
    Instant findMaxLastSyncedAt(@Param("userId") Long userId, @Param("source") String source);
}
