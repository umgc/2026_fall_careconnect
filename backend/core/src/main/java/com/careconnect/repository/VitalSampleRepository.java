package com.careconnect.repository;

import com.careconnect.model.VitalSample;
import com.careconnect.model.Patient;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

@Repository
public interface VitalSampleRepository extends JpaRepository<VitalSample, Long> {

    /**
     * Find all vital samples for a patient within a time range
     */
    List<VitalSample> findByPatientAndTimestampBetweenOrderByTimestampDesc(
            Patient patient,
            Instant fromTime,
            Instant toTime
    );

    /**
     * Find the most recent vital sample for a patient
     */
    Optional<VitalSample> findFirstByPatientOrderByTimestampDesc(Patient patient);

    /**
     * Find vital sample by patient and exact timestamp (for updates)
     */
    Optional<VitalSample> findByPatientAndTimestamp(Patient patient, Instant timestamp);

    /**
     * Count total vital samples for a patient
     */
    long countByPatient(Patient patient);

    /**
     * Find vital samples by patient ID and time range
     */
    @Query("SELECT v FROM VitalSample v WHERE v.patient.id = :patientId AND v.timestamp BETWEEN :fromTime AND :toTime ORDER BY v.timestamp DESC")
    List<VitalSample> findByPatientIdAndTimestampBetween(
            @Param("patientId") Long patientId,
            @Param("fromTime") Instant fromTime,
            @Param("toTime") Instant toTime
    );
}
