package com.careconnect.repository.ehr;

import com.careconnect.model.ehr.EhrAuditEvent;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.List;

public interface EhrAuditEventRepository extends JpaRepository<EhrAuditEvent, Long> {

    /**
     * Retention purge, step one: who has retrieval attempts recorded before {@code cutoff}. A left
     * join, because this table carries no foreign key to {@code patient}: an event whose patient
     * row is gone comes back with a null date of birth, which the purge treats as unknown and
     * keeps.
     */
    @Query("select distinct e.patientId as patientId, pt.dob as dob "
            + "from EhrAuditEvent e left join Patient pt on pt.id = e.patientId "
            + "where e.eventTime < :cutoff")
    List<PatientDateOfBirth> findPatientsWithEventBefore(@Param("cutoff") OffsetDateTime cutoff);

    /** Retention purge, step two: removes those events for the given patients only. */
    @Modifying
    @Transactional
    @Query("delete from EhrAuditEvent e where e.eventTime < :cutoff and e.patientId in :patientIds")
    int deleteEventsBeforeForPatients(
            @Param("cutoff") OffsetDateTime cutoff, @Param("patientIds") List<Long> patientIds);
}
