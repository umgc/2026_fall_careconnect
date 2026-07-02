package com.careconnect.model;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "user_files")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class UserFile {
    
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @Column(name = "filename", nullable = false)
    private String filename;
    
    @Column(name = "original_filename", nullable = false)
    private String originalFilename;
    
    @Column(name = "content_type")
    private String contentType;
    
    @Column(name = "file_size")
    private Long fileSize;
    
    @Lob
    @Column(name = "file_data", nullable = true)
    @Basic(fetch = FetchType.LAZY)
    private byte[] fileData;
    
    @Column(name = "owner_id", nullable = false)
    private Long ownerId;
    
    @Column(name = "owner_type", nullable = false)
    @Enumerated(EnumType.STRING)
    private OwnerType ownerType;
    
    @Column(name = "file_category", nullable = false)
    @Enumerated(EnumType.STRING)
    private FileCategory fileCategory;
    
    @Column(name = "patient_id")
    private Long patientId; // For files owned by patients or accessible by caregivers
    
    @Column(name = "storage_type", nullable = false)
    @Enumerated(EnumType.STRING)
    @Builder.Default
    private StorageType storageType = StorageType.DATABASE;
    
    @Column(name = "s3_path")
    private String s3Path; // For backward compatibility with S3 files
    
    @Column(name = "description")
    private String description;
    
    @Column(name = "uploaded_at", nullable = false)
    private LocalDateTime uploadedAt;
    
    @Column(name = "updated_at")
    private LocalDateTime updatedAt;
    
    @Column(name = "is_active", nullable = false)
    @Builder.Default
    private Boolean isActive = true;
    
    @PrePersist
    protected void onCreate() {
        LocalDateTime now = LocalDateTime.now();
        this.uploadedAt = now;
        this.updatedAt = now;
        if (this.isActive == null) {
            this.isActive = true;
        }
    }
    
    @PreUpdate
    protected void onUpdate() {
        this.updatedAt = LocalDateTime.now();
    }
    
    public enum OwnerType {
        PATIENT, CAREGIVER, FAMILY_MEMBER, ADMIN
    }
    
    public enum FileCategory {
        PROFILE_IMAGE, MEDICAL_RECORD, CLINICAL_NOTE, PRESCRIPTION, LAB_RESULT,
        INSURANCE_DOCUMENT, CONSENT_FORM, CARE_PLAN, OTHER_DOCUMENT,
        // Hiring & onboarding document digitization (see com.careconnect.model.forms)
        ONBOARDING_FORM, HIRING_DOCUMENT
    }
    
    public enum StorageType {
        DATABASE, S3
    }
    
    // Manual getters for Lombok compatibility
    public Long getId() { return id; }
    public String getFilename() { return filename; }
    public String getOriginalFilename() { return originalFilename; }
    public String getContentType() { return contentType; }
    public Long getFileSize() { return fileSize; }
    public FileCategory getFileCategory() { return fileCategory; }
    public LocalDateTime getUploadedAt() { return uploadedAt; }
    public Boolean getIsActive() { return isActive; }
    public StorageType getStorageType() { return storageType; }
    public String getS3Path() { return s3Path; }
    public Long getOwnerId() { return ownerId; }
    public String getDescription() { return description; }
    public LocalDateTime getUpdatedAt() { return updatedAt; }
    public Long getPatientId() { return patientId; }
    public OwnerType getOwnerType() { return ownerType; }
    
    // Manual setters
    public void setDescription(String description) { this.description = description; }
    public void setPatientId(Long patientId) { this.patientId = patientId; }
    public void setIsActive(Boolean isActive) { this.isActive = isActive; }
}
