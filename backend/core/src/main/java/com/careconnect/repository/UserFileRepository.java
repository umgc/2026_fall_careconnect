package com.careconnect.repository;

import com.careconnect.model.UserFile;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

@Repository
public interface UserFileRepository extends JpaRepository<UserFile, Long> {
    
    /**
     * Find all active files by owner
     */
    List<UserFile> findByOwnerIdAndOwnerTypeAndIsActiveTrue(Long ownerId, UserFile.OwnerType ownerType);
    
    /**
     * Find files by category for a specific owner
     */
    List<UserFile> findByOwnerIdAndOwnerTypeAndFileCategoryAndIsActiveTrue(
            Long ownerId, UserFile.OwnerType ownerType, UserFile.FileCategory fileCategory);
    
    /**
     * Find files accessible by a patient (owned by patient or associated caregivers/family)
     */
    @Query("SELECT f FROM UserFile f WHERE f.isActive = true AND " +
           "(f.patientId = :patientId OR " +
           "(f.ownerId = :patientId AND f.ownerType = 'PATIENT'))")
    List<UserFile> findFilesAccessibleByPatient(@Param("patientId") Long patientId);
    
    /**
     * Find files for a specific patient by category
     */
    @Query("SELECT f FROM UserFile f WHERE f.isActive = true AND " +
           "f.patientId = :patientId AND f.fileCategory = :category")
    List<UserFile> findByPatientIdAndFileCategory(@Param("patientId") Long patientId, 
                                                  @Param("category") UserFile.FileCategory category);
    
    /**
     * Find profile image for a user
     */
    Optional<UserFile> findFirstByOwnerIdAndOwnerTypeAndFileCategoryAndIsActiveTrue(
            Long ownerId, UserFile.OwnerType ownerType, UserFile.FileCategory fileCategory);
    
    /**
     * Find files by storage type (for migration purposes)
     */
    List<UserFile> findByStorageTypeAndIsActiveTrue(UserFile.StorageType storageType);
    
    /**
     * Count files by owner and category
     */
    long countByOwnerIdAndOwnerTypeAndFileCategoryAndIsActiveTrue(
            Long ownerId, UserFile.OwnerType ownerType, UserFile.FileCategory fileCategory);
    
    /**
     * Find active files owned by a user across a set of categories
     * (e.g. all employment / onboarding intake documents for a caregiver).
     */
    List<UserFile> findByOwnerIdAndOwnerTypeAndFileCategoryInAndIsActiveTrue(
            Long ownerId, UserFile.OwnerType ownerType, Collection<UserFile.FileCategory> categories);

    /**
     * Find active files linked to a patient (care-circle context) across a set of categories
     * (e.g. all intake documents associated with a care recipient).
     */
    List<UserFile> findByPatientIdAndFileCategoryInAndIsActiveTrue(
            Long patientId, Collection<UserFile.FileCategory> categories);

    /**
     * Find files that can be accessed by a caregiver for a specific patient
     * Includes files owned by the patient and files uploaded by caregivers for that patient
     */
    @Query("SELECT f FROM UserFile f WHERE f.isActive = true AND " +
           "f.patientId = :patientId AND " +
           "(f.ownerType = 'PATIENT' OR f.ownerType = 'CAREGIVER' OR f.ownerType = 'FAMILY_MEMBER')")
    List<UserFile> findFilesAccessibleByCaregiverForPatient(@Param("patientId") Long patientId);
}
