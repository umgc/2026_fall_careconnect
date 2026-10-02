package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrRawPayload;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;

public interface EhrRawPayloadRepository extends JpaRepository<EhrRawPayload, Long> {

    /** Most recent stored body for one resource type, used to re-derive a mapping. */
    Optional<EhrRawPayload> findFirstByPatientIdAndSourceIdAndResourceTypeOrderByRetrievedAtDesc(
            Long patientId, Long sourceId, String resourceType);

    /** Retrieval history for one patient and source, newest first. */
    List<EhrRawPayload> findByPatientIdAndSourceIdOrderByRetrievedAtDesc(
            Long patientId, Long sourceId);

    /**
     * Retention purge: removes every payload the source answered before {@code cutoff}. One bulk
     * statement, so nothing is loaded into memory first. Called by
     * {@code EhrRawPayloadRetentionWorker}; returns the number of rows deleted.
     */
    @Modifying
    @Transactional
    @Query("delete from EhrRawPayload p where p.retrievedAt < :cutoff")
    int deleteRetrievedBefore(@Param("cutoff") OffsetDateTime cutoff);
}
