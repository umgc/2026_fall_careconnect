package com.careconnect.repository;

import com.careconnect.model.Vital;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface VitalsRepository extends JpaRepository<Vital, Long> {

    @Query("SELECT v FROM Vital v WHERE v.patientId = :patientId ORDER BY v.recordedAt DESC")
    List<Vital> findByPatientIdOrderByRecordedAtDesc(@Param("patientId") Long patientId);

    @Query("SELECT v FROM Vital v WHERE v.patientId = :patientId AND v.recordedAt >= :since ORDER BY v.recordedAt DESC")
    List<Vital> findByPatientIdAndRecordedAtAfter(@Param("patientId") Long patientId, @Param("since") LocalDateTime since);

    @Query("SELECT v FROM Vital v WHERE v.patientId = :patientId ORDER BY v.recordedAt DESC")
    List<Vital> findRecentByPatientId(@Param("patientId") Long patientId, org.springframework.data.domain.Pageable pageable);

    @Query("SELECT v FROM Vital v WHERE v.patientId = :patientId AND v.vitalType = :vitalType ORDER BY v.recordedAt DESC")
    List<Vital> findByPatientIdAndVitalType(@Param("patientId") Long patientId, @Param("vitalType") String vitalType);
}
