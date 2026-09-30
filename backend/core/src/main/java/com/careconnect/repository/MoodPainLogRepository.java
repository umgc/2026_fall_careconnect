package com.careconnect.repository;

import com.careconnect.model.MoodPainLog;
import com.careconnect.model.Patient;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface MoodPainLogRepository extends JpaRepository<MoodPainLog, Long> {

    /**
     * Find all mood pain logs for a specific patient, ordered by timestamp descending
     */
    List<MoodPainLog> findByPatientOrderByTimestampDesc(Patient patient);

    /**
     * Find mood pain logs for a patient with pagination
     */
    Page<MoodPainLog> findByPatientOrderByTimestampDesc(Patient patient, Pageable pageable);

    /**
     * Find mood pain logs for a patient within a date range
     */
    @Query("SELECT m FROM MoodPainLog m WHERE m.patient = :patient AND m.timestamp BETWEEN :startDate AND :endDate ORDER BY m.timestamp DESC")
    List<MoodPainLog> findByPatientAndTimestampBetween(
            @Param("patient") Patient patient,
            @Param("startDate") LocalDateTime startDate,
            @Param("endDate") LocalDateTime endDate
    );

    /**
     * Find the most recent mood pain log for a patient
     */
    MoodPainLog findFirstByPatientOrderByTimestampDesc(Patient patient);

    /**
     * Count total entries for a patient
     */
    long countByPatient(Patient patient);

    /**
     * Calculate average mood value for a patient in a date range
     */
    @Query("SELECT AVG(m.moodValue) FROM MoodPainLog m WHERE m.patient = :patient AND m.timestamp BETWEEN :startDate AND :endDate")
    Double avgMoodByPatientAndTimestampBetween(
            @Param("patient") Patient patient,
            @Param("startDate") LocalDateTime startDate,
            @Param("endDate") LocalDateTime endDate
    );

    /**
     * Calculate average pain value for a patient in a date range
     */
    @Query("SELECT AVG(m.painValue) FROM MoodPainLog m WHERE m.patient = :patient AND m.timestamp BETWEEN :startDate AND :endDate")
    Double avgPainByPatientAndTimestampBetween(
            @Param("patient") Patient patient,
            @Param("startDate") LocalDateTime startDate,
            @Param("endDate") LocalDateTime endDate
    );

    /**
     * Count mood entries for a patient in a date range
     */
    @Query("SELECT COUNT(m) FROM MoodPainLog m WHERE m.patient = :patient AND m.timestamp BETWEEN :startDate AND :endDate AND m.moodValue IS NOT NULL")
    Integer countMoodEntriesByPatientAndTimestampBetween(
            @Param("patient") Patient patient,
            @Param("startDate") LocalDateTime startDate,
            @Param("endDate") LocalDateTime endDate
    );

    /**
     * Count pain entries for a patient in a date range
     */
    @Query("SELECT COUNT(m) FROM MoodPainLog m WHERE m.patient = :patient AND m.timestamp BETWEEN :startDate AND :endDate AND m.painValue IS NOT NULL")
    Integer countPainEntriesByPatientAndTimestampBetween(
            @Param("patient") Patient patient,
            @Param("startDate") LocalDateTime startDate,
            @Param("endDate") LocalDateTime endDate
    );
}
