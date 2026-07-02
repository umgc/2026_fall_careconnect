package com.careconnect.repository;

import com.careconnect.model.FamilyMemberLink;
import com.careconnect.model.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface FamilyMemberLinkRepository extends JpaRepository<FamilyMemberLink, Long> {
    
    // Find all active and non-expired links for a patient
    List<FamilyMemberLink> findByPatientUserAndStatus(User patientUser, FamilyMemberLink.LinkStatus status);
    
    // Find all active and non-expired links for a family member
    List<FamilyMemberLink> findByFamilyUserAndStatus(User familyUser, FamilyMemberLink.LinkStatus status);
    
    // Find specific active link between family member and patient
    Optional<FamilyMemberLink> findByFamilyUserAndPatientUserAndStatus(
        User familyUser, User patientUser, FamilyMemberLink.LinkStatus status);

    // Check if active and non-expired link exists
    @Query("SELECT CASE WHEN COUNT(fml) > 0 THEN true ELSE false END FROM FamilyMemberLink fml WHERE fml.familyUser = :familyUser AND fml.patientUser = :patientUser AND fml.status = 'ACTIVE' AND (fml.expiresAt IS NULL OR fml.expiresAt > :now)")
    boolean existsActiveNonExpiredLink(@Param("familyUser") User familyUser, @Param("patientUser") User patientUser, @Param("now") LocalDateTime now);
    
    @Query("SELECT fml FROM FamilyMemberLink fml WHERE fml.familyUser.id = :familyUserId AND fml.status = 'ACTIVE' AND (fml.expiresAt IS NULL OR fml.expiresAt > :now)")
    List<FamilyMemberLink> findActivePatientsByFamilyMember(@Param("familyUserId") Long familyUserId, @Param("now") LocalDateTime now);
    
    @Query("SELECT fml FROM FamilyMemberLink fml WHERE fml.patientUser.id = :patientUserId AND fml.status = 'ACTIVE' AND (fml.expiresAt IS NULL OR fml.expiresAt > :now)")
    List<FamilyMemberLink> findActiveFamilyMembersByPatient(@Param("patientUserId") Long patientUserId, @Param("now") LocalDateTime now);
    
    // Optimized queries using denormalized patient_id (faster, no joins needed)
    @Query("SELECT fml FROM FamilyMemberLink fml WHERE fml.patientId = :patientId AND fml.status = 'ACTIVE' AND (fml.expiresAt IS NULL OR fml.expiresAt > :now)")
    List<FamilyMemberLink> findActiveFamilyMembersByPatientId(@Param("patientId") Long patientId, @Param("now") LocalDateTime now);
    
    boolean existsByFamilyUserAndPatientUserAndStatus(
        User familyUser, User patientUser, FamilyMemberLink.LinkStatus status);
    
    @Query("SELECT COUNT(f) > 0 FROM FamilyMemberLink f " +
           "WHERE f.familyUser.id = :familyMemberUserId " +
           "AND (f.patientId = :patientId OR f.patientUser.id = :patientId) " +
           "AND f.status = 'ACTIVE' " +
           "AND (f.expiresAt IS NULL OR f.expiresAt > :now)")
    boolean existsByFamilyMemberUserIdAndPatientId(
        @Param("familyMemberUserId") Long familyMemberUserId,
        @Param("patientId") Long patientId,
        @Param("now") LocalDateTime now);

    @Query("SELECT CASE WHEN COUNT(f) > 0 THEN true ELSE false END FROM FamilyMemberLink f " +
           "WHERE f.familyUser.id = :familyMemberUserId " +
           "AND (f.patientId = :patientId OR f.patientUser.id = :patientId) " +
           "AND f.status = 'ACTIVE' " +
           "AND (f.expiresAt IS NULL OR f.expiresAt > :now)")
    boolean existsActiveNonExpiredLinkByUserIds(
        @Param("familyMemberUserId") Long familyMemberUserId,
        @Param("patientId") Long patientId,
        @Param("now") LocalDateTime now);
}
