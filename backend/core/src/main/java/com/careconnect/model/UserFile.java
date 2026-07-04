package com.careconnect.model;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;
import java.util.Arrays;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

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
        // Core healthcare
        PROFILE_IMAGE, MEDICAL_RECORD, CLINICAL_NOTE, PRESCRIPTION, LAB_RESULT,
        INSURANCE_DOCUMENT, CONSENT_FORM, CARE_PLAN,

        // Home Care Document Digitization: employment & onboarding intake document types
        EMPLOYMENT_APPLICATION, ONBOARDING_FORM, BACKGROUND_CHECK, CERTIFICATION,
        REFERENCE, EMPLOYMENT_CONTRACT, TAX_FORM, WORK_AUTHORIZATION, EMERGENCY_CONTACT,

        // Legacy hiring bucket retained from team-d-develop (see com.careconnect.model.forms)
        HIRING_DOCUMENT,

        // Fallback bucket for general/uncategorized documents
        OTHER_DOCUMENT;

        /**
         * Document types that belong to the employment / home-care intake workflow.
         * Kept in sync with the frontend {@code FileCategory.employmentIntake} list (8 types).
         * EMERGENCY_CONTACT and HIRING_DOCUMENT are valid categories but not intake types.
         */
        public static final Set<FileCategory> EMPLOYMENT_INTAKE = Set.of(
                EMPLOYMENT_APPLICATION, ONBOARDING_FORM, BACKGROUND_CHECK, CERTIFICATION,
                REFERENCE, EMPLOYMENT_CONTRACT, TAX_FORM, WORK_AUTHORIZATION);

        /**
         * Accepted client aliases (frontend values, legacy names and friendly synonyms)
         * that resolve to a canonical category. Keys are normalized (UPPER_SNAKE_CASE).
         */
        private static final Map<String, FileCategory> ALIASES = Map.ofEntries(
                Map.entry("PROFILE", PROFILE_IMAGE),
                Map.entry("PROFILE_PICTURE", PROFILE_IMAGE),
                Map.entry("MEDICAL", MEDICAL_RECORD),
                Map.entry("MEDICAL_REPORT", MEDICAL_RECORD),
                Map.entry("CLINICAL", CLINICAL_NOTE),
                Map.entry("CLINICAL_NOTES", CLINICAL_NOTE),
                Map.entry("LAB", LAB_RESULT),
                Map.entry("INSURANCE", INSURANCE_DOCUMENT),
                Map.entry("CONSENT", CONSENT_FORM),
                Map.entry("CARE", CARE_PLAN),
                Map.entry("EMPLOYMENT", EMPLOYMENT_APPLICATION),
                Map.entry("EMPLOYMENT_FORM", EMPLOYMENT_APPLICATION),
                Map.entry("APPLICATION", EMPLOYMENT_APPLICATION),
                Map.entry("ONBOARDING", ONBOARDING_FORM),
                Map.entry("BACKGROUND", BACKGROUND_CHECK),
                Map.entry("CERT", CERTIFICATION),
                Map.entry("CERTIFICATIONS", CERTIFICATION),
                Map.entry("LICENSE", CERTIFICATION),
                Map.entry("REFERENCES", REFERENCE),
                Map.entry("CONTRACT", EMPLOYMENT_CONTRACT),
                Map.entry("TAX", TAX_FORM),
                Map.entry("W4", TAX_FORM),
                Map.entry("W_4", TAX_FORM),
                Map.entry("I9", WORK_AUTHORIZATION),
                Map.entry("I_9", WORK_AUTHORIZATION),
                Map.entry("WORK_AUTH", WORK_AUTHORIZATION),
                Map.entry("EMERGENCY", EMERGENCY_CONTACT),
                Map.entry("HIRING", HIRING_DOCUMENT),
                Map.entry("DOCUMENT", OTHER_DOCUMENT),
                Map.entry("DOCUMENTS", OTHER_DOCUMENT),
                Map.entry("GENERAL", OTHER_DOCUMENT),
                Map.entry("OTHER", OTHER_DOCUMENT),
                Map.entry("AI_CHAT_UPLOAD", OTHER_DOCUMENT),
                Map.entry("CHAT_ATTACHMENT", OTHER_DOCUMENT),
                Map.entry("HEALTH_DATA_IMPORT", OTHER_DOCUMENT),
                Map.entry("BACKUP_FILE", OTHER_DOCUMENT));

        /**
         * Resolve a raw, client-supplied category string to a canonical {@link FileCategory}.
         * Matching is case- and separator-insensitive ({@code medical-report},
         * {@code Medical Report} and {@code MEDICAL_REPORT} all resolve identically) and
         * accepts both canonical names and {@link #ALIASES known aliases}.
         *
         * <p>A {@code null}/blank value defaults to {@link #OTHER_DOCUMENT}; any value that
         * cannot be mapped throws so callers can surface a clear validation error.</p>
         *
         * @throws IllegalArgumentException if the value does not map to a known category
         */
        public static FileCategory fromClientValue(String raw) {
            if (raw == null || raw.isBlank()) {
                return OTHER_DOCUMENT;
            }
            String key = raw.trim().toUpperCase().replace('-', '_').replace(' ', '_');
            try {
                return FileCategory.valueOf(key);
            } catch (IllegalArgumentException ignored) {
                // Not a canonical name; fall through to alias resolution.
            }
            FileCategory mapped = ALIASES.get(key);
            if (mapped != null) {
                return mapped;
            }
            throw new IllegalArgumentException(
                    "Invalid file category '" + raw + "'. Valid categories: " + canonicalNames());
        }

        /** @return whether this category is a hiring / onboarding intake document type. */
        public boolean isEmploymentIntake() {
            return EMPLOYMENT_INTAKE.contains(this);
        }

        /** @return comma-separated list of canonical category names, for error messages. */
        public static String canonicalNames() {
            return Arrays.stream(values()).map(Enum::name).collect(Collectors.joining(", "));
        }
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
