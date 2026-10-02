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

    /** A patient with at least one payload past the cutoff, and their stored date of birth. */
    interface PatientDateOfBirth {
        Long getPatientId();

        /** {@code patient.dob} as stored: free text, possibly null. */
        String getDob();
    }

    /**
     * Retention purge, step one: who has payloads the source answered before {@code cutoff}. The
     * date of birth comes back as stored because it is a varchar in two formats, which SQL cannot
     * compare; {@code EhrRawPayloadRetentionWorker} parses it and decides who is old enough.
     * One row per patient, not per payload.
     */
    @Query("select distinct p.patientId as patientId, pt.dob as dob "
            + "from EhrRawPayload p, Patient pt "
            + "where pt.id = p.patientId and p.retrievedAt < :cutoff")
    List<PatientDateOfBirth> findPatientsWithPayloadRetrievedBefore(@Param("cutoff") OffsetDateTime cutoff);

    /**
     * Retention purge, step two: removes the payloads the source answered before {@code cutoff}
     * for the given patients only. One bulk statement, so nothing is loaded into memory first.
     * Returns the number of rows deleted.
     */
    @Modifying
    @Transactional
    @Query("delete from EhrRawPayload p where p.retrievedAt < :cutoff and p.patientId in :patientIds")
    int deleteRetrievedBeforeForPatients(
            @Param("cutoff") OffsetDateTime cutoff, @Param("patientIds") List<Long> patientIds);
}
