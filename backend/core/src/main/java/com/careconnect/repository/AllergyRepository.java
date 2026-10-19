package com.careconnect.repository;

import com.careconnect.model.Allergy;
import com.careconnect.model.Patient;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface AllergyRepository extends JpaRepository<Allergy, Long> {

    /**
     * Find all allergies for a specific patient
     */
    List<Allergy> findByPatientOrderByCreatedAtDesc(Patient patient);

    /**
     * Find active allergies for a specific patient
     */
    List<Allergy> findByPatientAndIsActiveTrueOrderByCreatedAtDesc(Patient patient);

    /**
     * Find allergies by patient ID
     */
    @Query("SELECT a FROM Allergy a WHERE a.patient.id = :patientId ORDER BY a.createdAt DESC")
    List<Allergy> findByPatientId(@Param("patientId") Long patientId);

    /**
     * Find active allergies by patient ID
     */
    @Query("SELECT a FROM Allergy a WHERE a.patient.id = :patientId AND a.isActive = true ORDER BY a.createdAt DESC")
    List<Allergy> findActiveAllergiesByPatientId(@Param("patientId") Long patientId);

    /**
     * Check if patient has specific allergen
     */
    boolean existsByPatientAndAllergenIgnoreCaseAndIsActiveTrue(Patient patient, String allergen);

    /**
     * Count active allergies for a patient
     */
    long countByPatientAndIsActiveTrue(Patient patient);
}
