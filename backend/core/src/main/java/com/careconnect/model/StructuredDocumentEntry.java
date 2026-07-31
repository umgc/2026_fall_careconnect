package com.careconnect.model;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * Structured (form-entry) record captured from an uploaded onboarding / intake
 * document. The original uploaded file ({@link #userFileId}) is preserved as
 * supporting evidence; this entity holds the key fields extracted from it so
 * records become searchable and document completion can be tracked.
 */
@Entity
@Table(name = "structured_document_entries")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class StructuredDocumentEntry {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** The uploaded file this structured record was captured from (required link). */
    @Column(name = "user_file_id", nullable = false)
    private Long userFileId;

    @Column(name = "document_type", nullable = false)
    @Enumerated(EnumType.STRING)
    private UserFile.FileCategory documentType;

    /** Patient context (care recipient the document pertains to). */
    @Column(name = "patient_id")
    private Long patientId;

    /** Employee context (caregiver / staff member the document pertains to). */
    @Column(name = "employee_user_id")
    private Long employeeUserId;

    /** Captured field values serialized as a JSON object (key -> value). */
    @Column(name = "fields_json", columnDefinition = "TEXT")
    private String fieldsJson;

    @Column(name = "created_by")
    private Long createdBy;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    @Column(name = "is_active", nullable = false)
    @Builder.Default
    private Boolean isActive = true;

    @PrePersist
    protected void onCreate() {
        LocalDateTime now = LocalDateTime.now();
        this.createdAt = now;
        this.updatedAt = now;
        if (this.isActive == null) {
            this.isActive = true;
        }
    }

    @PreUpdate
    protected void onUpdate() {
        this.updatedAt = LocalDateTime.now();
    }

    /**
     * Document types that support structured form entry: the hiring /
     * onboarding intake set plus insurance documents. Must stay aligned with the
     * frontend field templates (frontend/lib/services/structured_entry_service.dart).
     */
    public static final Set<UserFile.FileCategory> SUPPORTED_TYPES = Set.of(
            UserFile.FileCategory.EMPLOYMENT_APPLICATION,
            UserFile.FileCategory.ONBOARDING_FORM,
            UserFile.FileCategory.HIRING_DOCUMENT,
            UserFile.FileCategory.BACKGROUND_CHECK,
            UserFile.FileCategory.CERTIFICATION,
            UserFile.FileCategory.REFERENCE,
            UserFile.FileCategory.EMPLOYMENT_CONTRACT,
            UserFile.FileCategory.TAX_FORM,
            UserFile.FileCategory.WORK_AUTHORIZATION,
            UserFile.FileCategory.EMERGENCY_CONTACT,
            UserFile.FileCategory.INSURANCE_DOCUMENT);

    /**
     * Required field keys per supported document type. A structured entry cannot
     * be saved unless every required key is present with a non-blank value.
     * Keys mirror the frontend field templates.
     */
    public static final Map<UserFile.FileCategory, Set<String>> REQUIRED_FIELDS = Map.ofEntries(
            Map.entry(UserFile.FileCategory.EMPLOYMENT_APPLICATION,
                    Set.of("applicantName", "positionApplied", "applicationDate")),
            Map.entry(UserFile.FileCategory.ONBOARDING_FORM,
                    Set.of("employeeName", "startDate")),
            Map.entry(UserFile.FileCategory.HIRING_DOCUMENT,
                    Set.of("documentTitle", "employeeName")),
            Map.entry(UserFile.FileCategory.BACKGROUND_CHECK,
                    Set.of("subjectName", "screeningAgency", "screeningDate", "result")),
            Map.entry(UserFile.FileCategory.CERTIFICATION,
                    Set.of("certificationName", "holderName", "issuingAuthority", "issueDate")),
            Map.entry(UserFile.FileCategory.REFERENCE,
                    Set.of("referenceName", "relationship")),
            Map.entry(UserFile.FileCategory.EMPLOYMENT_CONTRACT,
                    Set.of("employeeName", "employerName", "contractStartDate")),
            Map.entry(UserFile.FileCategory.TAX_FORM,
                    Set.of("employeeName", "taxYear", "filingStatus")),
            Map.entry(UserFile.FileCategory.WORK_AUTHORIZATION,
                    Set.of("employeeName", "documentTitle", "documentNumber")),
            Map.entry(UserFile.FileCategory.EMERGENCY_CONTACT,
                    Set.of("contactName", "relationship", "phone")),
            Map.entry(UserFile.FileCategory.INSURANCE_DOCUMENT,
                    Set.of("policyHolderName", "insuranceProvider", "policyNumber")));

    /** Comma-separated, sorted list of supported document types (for error messages). */
    public static String supportedTypeNames() {
        return SUPPORTED_TYPES.stream().map(Enum::name).sorted().collect(Collectors.joining(", "));
    }

    // Manual getters/setters for Lombok compatibility (matches UserFile style)
    public Long getId() { return id; }
    public Long getUserFileId() { return userFileId; }
    public UserFile.FileCategory getDocumentType() { return documentType; }
    public Long getPatientId() { return patientId; }
    public Long getEmployeeUserId() { return employeeUserId; }
    public String getFieldsJson() { return fieldsJson; }
    public Long getCreatedBy() { return createdBy; }
    public LocalDateTime getCreatedAt() { return createdAt; }
    public LocalDateTime getUpdatedAt() { return updatedAt; }
    public Boolean getIsActive() { return isActive; }

    public void setDocumentType(UserFile.FileCategory documentType) { this.documentType = documentType; }
    public void setPatientId(Long patientId) { this.patientId = patientId; }
    public void setEmployeeUserId(Long employeeUserId) { this.employeeUserId = employeeUserId; }
    public void setFieldsJson(String fieldsJson) { this.fieldsJson = fieldsJson; }
    public void setIsActive(Boolean isActive) { this.isActive = isActive; }
}
