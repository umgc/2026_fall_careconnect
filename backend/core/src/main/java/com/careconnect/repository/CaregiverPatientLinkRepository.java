package com.careconnect.repository;

import com.careconnect.model.CaregiverPatientLink;
import com.careconnect.model.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface CaregiverPatientLinkRepository extends JpaRepository<CaregiverPatientLink, Long> {

    // Find all active links for a caregiver
    List<CaregiverPatientLink> findByCaregiverUserAndStatus(User caregiverUser, CaregiverPatientLink.LinkStatus status);

    // Find all active links for a patient
    List<CaregiverPatientLink> findByPatientUserAndStatus(User patientUser, CaregiverPatientLink.LinkStatus status);

    // Find specific active link between caregiver and patient
    Optional<CaregiverPatientLink> findByCaregiverUserAndPatientUserAndStatus(
            User caregiverUser, User patientUser, CaregiverPatientLink.LinkStatus status);

    Optional<CaregiverPatientLink> findTopByCaregiverUserAndPatientUserAndStatusOrderByUpdatedAtDesc(
            User caregiverUser, User patientUser, CaregiverPatientLink.LinkStatus status);

    // Check if link exists between caregiver and patient
    boolean existsByCaregiverUserAndPatientUserAndStatus(
        User caregiverUser, User patientUser, CaregiverPatientLink.LinkStatus status);

    // Check if active and non-expired link exists
    @Query("SELECT CASE WHEN COUNT(cpl) > 0 THEN true ELSE false END FROM CaregiverPatientLink cpl WHERE cpl.caregiverUser = :caregiverUser AND cpl.patientUser = :patientUser AND cpl.status = 'ACTIVE' AND (cpl.expiresAt IS NULL OR cpl.expiresAt > :now)")
    boolean existsActiveNonExpiredLink(@Param("caregiverUser") User caregiverUser, @Param("patientUser") User patientUser, @Param("now") LocalDateTime now);

    // Check if active and non-expired link exists, by user IDs (no need to load full User entities)
    @Query("SELECT CASE WHEN COUNT(cpl) > 0 THEN true ELSE false END FROM CaregiverPatientLink cpl WHERE cpl.caregiverUser.id = :caregiverUserId AND cpl.patientUser.id = :patientUserId AND cpl.status = 'ACTIVE' AND (cpl.expiresAt IS NULL OR cpl.expiresAt > :now)")
    boolean existsActiveNonExpiredLinkByUserIds(@Param("caregiverUserId") Long caregiverUserId, @Param("patientUserId") Long patientUserId, @Param("now") LocalDateTime now);

    // Find all patients for a caregiver (active and non-expired links only)
    @Query("SELECT cpl FROM CaregiverPatientLink cpl WHERE cpl.caregiverUser = :caregiverUser AND cpl.status = 'ACTIVE' AND (cpl.expiresAt IS NULL OR cpl.expiresAt > :now)")
    List<CaregiverPatientLink> findActivePatientsByCaregiver(@Param("caregiverUser") User caregiverUser, @Param("now") LocalDateTime now);

    // Find all caregivers for a patient (active and non-expired links only)
    @Query("SELECT cpl FROM CaregiverPatientLink cpl WHERE cpl.patientUser = :patientUser AND cpl.status = 'ACTIVE' AND (cpl.expiresAt IS NULL OR cpl.expiresAt > :now)")
    List<CaregiverPatientLink> findActiveCaregiversByPatient(@Param("patientUser") User patientUser, @Param("now") LocalDateTime now);

    // Find expired links that need status update
    @Query("SELECT cpl FROM CaregiverPatientLink cpl WHERE cpl.expiresAt IS NOT NULL AND cpl.expiresAt < :now AND cpl.status = 'ACTIVE'")
    List<CaregiverPatientLink> findExpiredActiveLinks(@Param("now") LocalDateTime now);

    // Find temporary links
    List<CaregiverPatientLink> findByLinkTypeAndStatus(CaregiverPatientLink.LinkType linkType, CaregiverPatientLink.LinkStatus status);

    // Find links created by a specific user
    List<CaregiverPatientLink> findByCreatedBy(User createdBy);
}
