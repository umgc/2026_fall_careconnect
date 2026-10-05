package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrResource;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

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

    /**
     * Retention purge, step one: who has a mirrored resource this application last synced before
     * {@code cutoff}. Measured on {@code last_synced_at}, when we last stored the row, so a patient
     * who is still syncing keeps a fresh mirror that the next sync re-writes rather than one the
     * purge removes — the same reasoning as {@code ehr_source_identity.updated_at}. Rows that have
     * no {@code patient_id} yet (the column is additive and nullable) are skipped: the age rule
     * needs a patient. One row per patient, not per resource.
     */
    @Query("select distinct r.patientId as patientId, pt.dob as dob "
            + "from EhrResource r left join Patient pt on pt.id = r.patientId "
            + "where r.patientId is not null and r.lastSyncedAt < :cutoff")
    List<PatientDateOfBirth> findPatientsWithResourceSyncedBefore(@Param("cutoff") Instant cutoff);

    /** Retention purge, step two: removes those mirrored resources for the given patients only. */
    @Modifying
    @Transactional
    @Query("delete from EhrResource r where r.lastSyncedAt < :cutoff and r.patientId in :patientIds")
    int deleteSyncedBeforeForPatients(
            @Param("cutoff") Instant cutoff, @Param("patientIds") List<Long> patientIds);
}
