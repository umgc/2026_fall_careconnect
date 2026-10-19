package com.careconnect.model;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;
import java.util.Map;
import java.util.Set;

/**
 * Compliance status of one required document type for one subject (an employee
 * being onboarded or a care circle / care recipient). One row exists per
 * (subject, document type) once the document has ever changed state; document
 * types with no row yet are derived as MISSING / IN_PROGRESS / COMPLETE from
 * the uploaded files and digitized structured records that already exist.
 */
@Entity
@Table(name = "document_requirement_statuses",
        uniqueConstraints = @UniqueConstraint(name = "uq_doc_requirement_subject",
                columnNames = {"subject_type", "subject_id", "document_type"}))
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class DocumentRequirementStatus {

    /**
     * The required document set per subject type. Employees must complete the
     * full employment / home-care intake packet; care circles must have the
     * core care documents on file. Drives checklist rendering and the
     * missing-forms report on both backend and frontend.
     */
    public static final Map<SubjectType, Set<UserFile.FileCategory>> REQUIRED_DOCUMENTS = Map.of(
            SubjectType.EMPLOYEE, Set.of(
                    UserFile.FileCategory.EMPLOYMENT_APPLICATION,
                    UserFile.FileCategory.ONBOARDING_FORM,
                    UserFile.FileCategory.BACKGROUND_CHECK,
                    UserFile.FileCategory.CERTIFICATION,
                    UserFile.FileCategory.REFERENCE,
                    UserFile.FileCategory.EMPLOYMENT_CONTRACT,
                    UserFile.FileCategory.TAX_FORM,
                    UserFile.FileCategory.WORK_AUTHORIZATION,
                    UserFile.FileCategory.EMERGENCY_CONTACT),
            SubjectType.CARE_CIRCLE, Set.of(
                    UserFile.FileCategory.CONSENT_FORM,
                    UserFile.FileCategory.INSURANCE_DOCUMENT,
                    UserFile.FileCategory.CARE_PLAN,
                    UserFile.FileCategory.EMERGENCY_CONTACT));
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(name = "subject_type", nullable = false)
    @Enumerated(EnumType.STRING)
    private SubjectType subjectType;
    /**
     * users.id for EMPLOYEE subjects, patients.id for CARE_CIRCLE subjects.
     */
    @Column(name = "subject_id", nullable = false)
    private Long subjectId;
    @Column(name = "document_type", nullable = false)
    @Enumerated(EnumType.STRING)
    private UserFile.FileCategory documentType;
    @Column(name = "status", nullable = false)
    @Enumerated(EnumType.STRING)
    private ComplianceStatus status;
    /**
     * Most recent uploaded file serving as evidence for this requirement.
     */
    @Column(name = "user_file_id")
    private Long userFileId;
    /**
     * Digitized structured record captured for this requirement, if any.
     */
    @Column(name = "structured_entry_id")
    private Long structuredEntryId;
    /**
     * Reason supplied with the latest transition (mirrored into history).
     */
    @Column(name = "notes", length = 1024)
    private String notes;
    @Column(name = "updated_by")
    private Long updatedBy;
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;
    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    @PrePersist
    protected void onCreate() {
        LocalDateTime now = LocalDateTime.now();
        this.createdAt = now;
        this.updatedAt = now;
    }

    @PreUpdate
    protected void onUpdate() {
        this.updatedAt = LocalDateTime.now();
    }

    // Manual getters/setters for Lombok compatibility (matches UserFile style)
    public Long getId() {
        return id;
    }

    public SubjectType getSubjectType() {
        return subjectType;
    }

    public Long getSubjectId() {
        return subjectId;
    }

    public UserFile.FileCategory getDocumentType() {
        return documentType;
    }

    public ComplianceStatus getStatus() {
        return status;
    }

    public void setStatus(ComplianceStatus status) {
        this.status = status;
    }

    public Long getUserFileId() {
        return userFileId;
    }

    public void setUserFileId(Long userFileId) {
        this.userFileId = userFileId;
    }

    public Long getStructuredEntryId() {
        return structuredEntryId;
    }

    public void setStructuredEntryId(Long structuredEntryId) {
        this.structuredEntryId = structuredEntryId;
    }

    public String getNotes() {
        return notes;
    }

    public void setNotes(String notes) {
        this.notes = notes;
    }

    public Long getUpdatedBy() {
        return updatedBy;
    }

    public void setUpdatedBy(Long updatedBy) {
        this.updatedBy = updatedBy;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }

    /**
     * Whose document set a checklist tracks.
     */
    public enum SubjectType {
        /**
         * A staff member (caregiver) going through hiring / onboarding.
         */
        EMPLOYEE,
        /**
         * A care circle, keyed by the patient (care recipient) at its center.
         */
        CARE_CIRCLE;

        public static SubjectType fromClientValue(String raw) {
            if (raw == null || raw.isBlank()) {
                throw new IllegalArgumentException("subjectType is required (EMPLOYEE or CARE_CIRCLE)");
            }
            String key = raw.trim().toUpperCase().replace('-', '_').replace(' ', '_');
            try {
                return SubjectType.valueOf(key);
            } catch (IllegalArgumentException e) {
                throw new IllegalArgumentException(
                        "Invalid subjectType '" + raw + "'. Valid values: EMPLOYEE, CARE_CIRCLE");
            }
        }
    }

    /**
     * Checklist state of a single required document.
     */
    public enum ComplianceStatus {
        MISSING, IN_PROGRESS, COMPLETE, REJECTED;

        public static ComplianceStatus fromClientValue(String raw) {
            if (raw == null || raw.isBlank()) {
                throw new IllegalArgumentException(
                        "status is required (MISSING, IN_PROGRESS, COMPLETE or REJECTED)");
            }
            String key = raw.trim().toUpperCase().replace('-', '_').replace(' ', '_');
            try {
                return ComplianceStatus.valueOf(key);
            } catch (IllegalArgumentException e) {
                throw new IllegalArgumentException(
                        "Invalid status '" + raw + "'. Valid values: MISSING, IN_PROGRESS, COMPLETE, REJECTED");
            }
        }
    }
}
