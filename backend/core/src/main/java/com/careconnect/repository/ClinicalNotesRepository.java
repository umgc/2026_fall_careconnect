package com.careconnect.repository;

import com.careconnect.model.ClinicalNote;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface ClinicalNotesRepository extends JpaRepository<ClinicalNote, Long> {

    @Query("SELECT c FROM ClinicalNote c WHERE c.patientId = :patientId ORDER BY c.createdAt DESC")
    List<ClinicalNote> findByPatientIdOrderByCreatedAtDesc(@Param("patientId") Long patientId);

    @Query("SELECT c FROM ClinicalNote c WHERE c.patientId = :patientId AND c.isActive = true ORDER BY c.createdAt DESC")
    List<ClinicalNote> findActiveByPatientIdOrderByCreatedAtDesc(@Param("patientId") Long patientId);

    @Query("SELECT c FROM ClinicalNote c WHERE c.patientId = :patientId ORDER BY c.createdAt DESC")
    List<ClinicalNote> findRecentByPatientId(@Param("patientId") Long patientId, org.springframework.data.domain.Pageable pageable);
}
