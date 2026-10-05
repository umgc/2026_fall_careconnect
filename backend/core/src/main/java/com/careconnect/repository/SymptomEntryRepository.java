package com.careconnect.repository;

import com.careconnect.model.SymptomEntry;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.util.List;

@Repository
public interface SymptomEntryRepository extends JpaRepository<SymptomEntry, Long> {

    // listing symptoms by patient
    List<SymptomEntry> findByPatientIdOrderByTakenAtDesc(Long patientId);

    // Already existing analytics queries:
    @Query("SELECT COUNT(s) " +
            "FROM SymptomEntry s " +
            "WHERE s.patient.id = :patientId " +
            "AND s.takenAt BETWEEN :from AND :to " +
            "AND s.completed = true")
    long countCompleted(@Param("patientId") Long patientId,
                        @Param("from") Instant from,
                        @Param("to") Instant to);

    @Query("SELECT COUNT(s) " +
            "FROM SymptomEntry s " +
            "WHERE s.patient.id = :patientId " +
            "AND s.takenAt BETWEEN :from AND :to")
    long countTotal(@Param("patientId") Long patientId,
                    @Param("from") Instant from,
                    @Param("to") Instant to);
}
